package com.docuray.docuray.scanner

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Size
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.min

class DocScannerView(
    private val context: Context,
    private val activity: Activity,
    messenger: BinaryMessenger,
    viewId: Int
) : FrameLayout(context), PlatformView, MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "DocuRay-DocScannerView"
    }

    private val methodChannel = MethodChannel(messenger, "com.docuray/scanner_view_$viewId")
    private val mainHandler = Handler(Looper.getMainLooper())

    private val previewView = PreviewView(context).apply {
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        scaleType = PreviewView.ScaleType.FIT_CENTER
        layoutParams = LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
    }

    private val overlayView = DocumentOverlayView(context).apply {
        layoutParams = LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
    }

    private val cornerDetector = CornerDetector(context)
    private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var imageCapture: ImageCapture? = null
    private var camera: Camera? = null
    private var cameraProvider: ProcessCameraProvider? = null

    // Scanner state
    private var isAutoMode = true
    private var captureType = "Document"
    private var currentFlashMode = "off"
    private var isCapturing = false
    private var isInferring = false
    private var isPaused = false
    private var lastInferenceTime = 0L

    // Adaptive prediction frame rate controller (25 - 30 FPS target)
    private var targetInferenceIntervalMs = 35L
    private var rollingLatencyMs = 30f
    private var droppedFramesCount = 0

    // Stability tracking
    private var latestNormalizedPoints: FloatArray? = null
    private var stableStartTime = 0L
    private val stabilityRequiredTimeMs = 500L

    private var currentStatus = "searching"
    private var isDiagnosticsEnabled = false
    private var lastMetricsUpdateTime = 0L

    init {
        addView(previewView)
        addView(overlayView)
        methodChannel.setMethodCallHandler(this)
        startCamera()
    }

    override fun getView(): View = this

    override fun dispose() {
        methodChannel.setMethodCallHandler(null)
        pauseScanner()
        cameraExecutor.shutdown()
        cornerDetector.close()
    }

    private fun startCamera() {
        if (isPaused) return
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            try {
                if (isPaused) return@addListener
                cameraProvider = future.get()

                // Configure all 3 use cases with identical 4:3 target aspect ratio
                val preview = Preview.Builder()
                    .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                    .build().also {
                        it.setSurfaceProvider(previewView.surfaceProvider)
                    }

                imageCapture = ImageCapture.Builder()
                    .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                    .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                    .build()

                val imageAnalyzer = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                    .setTargetResolution(Size(640, 480))
                    .build().also { analyzer ->
                        analyzer.setAnalyzer(cameraExecutor) { proxy ->
                            processImageFrame(proxy)
                        }
                    }

                cameraProvider?.unbindAll()
                val lifecycleOwner = activity as? LifecycleOwner
                if (lifecycleOwner != null && !isPaused) {
                    camera = cameraProvider?.bindToLifecycle(
                        lifecycleOwner,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        imageCapture,
                        imageAnalyzer
                    )
                    applyFlashMode(currentFlashMode)
                    Log.d(TAG, "Camera bound to lifecycle successfully (RATIO_4_3)")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Camera initialization failed: ${e.message}", e)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun processImageFrame(imageProxy: ImageProxy) {
        val tAcquire0 = System.nanoTime()
        try {
            if (isPaused || !isAutoMode || isCapturing) {
                return
            }

            val now = System.currentTimeMillis()
            // Dynamic adaptive inference rate (15 FPS, 12 FPS, 10 FPS, or 8 FPS)
            if (isInferring || now - lastInferenceTime < targetInferenceIntervalMs) {
                droppedFramesCount++
                return
            }

            isInferring = true
            lastInferenceTime = now
            val acquireMs = (System.nanoTime() - tAcquire0) / 1_000_000f

            val tConvert0 = System.nanoTime()
            val bitmap = imageProxy.toBitmap()
            val convertMs = (System.nanoTime() - tConvert0) / 1_000_000f
            val rotation = imageProxy.imageInfo.rotationDegrees.toFloat()

            val result = cornerDetector.detectFromBitmap(bitmap, rotation, acquireMs, convertMs)
            bitmap.recycle()

            // Update adaptive prediction interval based on rolling latency
            result.metrics?.let { m ->
                m.droppedFrames = droppedFramesCount
                rollingLatencyMs = 0.8f * rollingLatencyMs + 0.2f * m.totalMs
                targetInferenceIntervalMs = when {
                    rollingLatencyMs < 35f -> 33L  // ~30 FPS
                    rollingLatencyMs < 50f -> 40L  // ~25 FPS
                    rollingLatencyMs < 70f -> 50L  // ~20 FPS
                    else -> 66L                   // ~15 FPS
                }

                if (isDiagnosticsEnabled) {
                    mainHandler.post {
                        overlayView.updateMetrics(m)
                    }
                    if (now - lastMetricsUpdateTime > 200L) {
                        lastMetricsUpdateTime = now
                        mainHandler.post {
                            methodChannel.invokeMethod("onMetricsUpdate", metricsToMap(m))
                        }
                    }
                }
            }

            val viewW = previewView.width.toFloat()
            val viewH = previewView.height.toFloat()

            if (isAutoMode && !isPaused && !isCapturing && result.isValid && viewW > 0 && viewH > 0) {
                val coords = result.corners
                latestNormalizedPoints = coords.clone()

                // Calculate FIT_CENTER mapping from rotated camera frame to PreviewView overlay
                val rotW = if (rotation == 90f || rotation == 270f) imageProxy.height.toFloat() else imageProxy.width.toFloat()
                val rotH = if (rotation == 90f || rotation == 270f) imageProxy.width.toFloat() else imageProxy.height.toFloat()

                val scale = min(viewW / rotW, viewH / rotH)
                val fittedW = rotW * scale
                val fittedH = rotH * scale
                val offsetX = (viewW - fittedW) / 2f
                val offsetY = (viewH - fittedH) / 2f

                val mappedPoints = FloatArray(8)
                for (i in 0 until 8 step 2) {
                    mappedPoints[i] = offsetX + (coords[i] * fittedW)
                    mappedPoints[i + 1] = offsetY + (coords[i + 1] * fittedH)
                }

                val cornerList = ArrayList<Double>(8)
                for (c in coords) {
                    cornerList.add(c.toDouble())
                }

                mainHandler.post {
                    overlayView.updatePoints(mappedPoints)
                    methodChannel.invokeMethod("onCornersDetected", mapOf("corners" to cornerList))
                }

                // Check temporal stability using TemporalTracker
                val tracker = cornerDetector.temporalTracker
                if (tracker.isStableForCapture) {
                    if (stableStartTime == 0L) {
                        stableStartTime = System.currentTimeMillis()
                        updateStatus("holdSteady")
                        mainHandler.post { overlayView.setIsReady(false) }
                    } else {
                        val duration = System.currentTimeMillis() - stableStartTime
                        if (duration >= stabilityRequiredTimeMs && isAutoMode && !isCapturing && !isPaused) {
                            isCapturing = true
                            mainHandler.post { overlayView.setIsReady(true) }
                            updateStatus("ready")
                            mainHandler.post { triggerAutoCapture() }
                        } else if (duration >= 300L) {
                            mainHandler.post { overlayView.setIsReady(true) }
                            updateStatus("ready")
                        }
                    }
                } else {
                    stableStartTime = 0L
                    mainHandler.post { overlayView.setIsReady(false) }
                    updateStatus("detected")
                }
            } else {
                mainHandler.post {
                    overlayView.updatePoints(null)
                    overlayView.setIsReady(false)
                }
                stableStartTime = 0L
                if (isAutoMode) {
                    updateStatus("searching")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in processImageFrame: ${e.message}", e)
        } finally {
            imageProxy.close()
            isInferring = false
        }
    }

    private fun metricsToMap(m: ProfileMetrics): Map<String, Any> {
        return mapOf(
            "acquireMs" to m.acquireMs,
            "convertMs" to m.convertMs,
            "resizeMs" to m.resizeMs,
            "inferenceMs" to m.inferenceMs,
            "decodeMs" to m.decodeMs,
            "maskMs" to m.maskMs,
            "contourMs" to m.contourMs,
            "totalMs" to m.totalMs,
            "fps" to m.fps,
            "droppedFrames" to m.droppedFrames,
            "backend" to m.backend,
            "confidence" to m.confidence,
            "hasDocument" to m.hasDocument
        )
    }

    private fun updateStatus(status: String) {
        if (currentStatus != status) {
            currentStatus = status
            mainHandler.post {
                methodChannel.invokeMethod("onStatusChanged", mapOf("status" to status))
            }
        }
    }

    private fun triggerAutoCapture() {
        if (isPaused || !isAutoMode) return
        methodChannel.invokeMethod("onAutoCapture", emptyMap<String, Any>())
        takePhotoInternal(null)
    }

    fun setFlashMode(mode: String) {
        currentFlashMode = mode.lowercase()
        applyFlashMode(currentFlashMode)
    }

    private fun applyFlashMode(mode: String) {
        when (mode) {
            "on" -> {
                imageCapture?.flashMode = ImageCapture.FLASH_MODE_ON
                try {
                    camera?.cameraControl?.enableTorch(true)
                } catch (_: Exception) {}
            }
            "auto" -> {
                try {
                    camera?.cameraControl?.enableTorch(false)
                } catch (_: Exception) {}
                imageCapture?.flashMode = ImageCapture.FLASH_MODE_AUTO
            }
            else -> {
                try {
                    camera?.cameraControl?.enableTorch(false)
                } catch (_: Exception) {}
                imageCapture?.flashMode = ImageCapture.FLASH_MODE_OFF
            }
        }
    }

    fun setAutoMode(auto: Boolean) {
        isAutoMode = auto
        if (!auto) {
            mainHandler.post {
                overlayView.updatePoints(null)
                overlayView.setIsReady(false)
            }
            latestNormalizedPoints = null
            stableStartTime = 0L
            cornerDetector.resetStabilization()
            updateStatus("manual")
        } else {
            stableStartTime = 0L
            cornerDetector.resetStabilization()
            updateStatus("searching")
        }
    }

    fun setCaptureType(type: String) {
        captureType = type
        mainHandler.post {
            overlayView.setCaptureType(type)
        }
    }

    fun takePhoto(result: MethodChannel.Result) {
        takePhotoInternal(result)
    }

    private fun takePhotoInternal(result: MethodChannel.Result?) {
        val capture = imageCapture ?: run {
            result?.error("ERR", "Camera not initialized", null)
            isCapturing = false
            return
        }

        isCapturing = true
        val tempFile = File(context.cacheDir, "cap_${System.currentTimeMillis()}.jpg")
        val outputOptions = ImageCapture.OutputFileOptions.Builder(tempFile).build()

        capture.takePicture(
            outputOptions,
            ContextCompat.getMainExecutor(context),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                    cameraExecutor.execute {
                        try {
                            // 1. Correct EXIF orientation to make the image upright
                            val exif = ExifInterface(tempFile.absolutePath)
                            val orientation = exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
                            val matrix = Matrix()
                            when (orientation) {
                                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                            }

                            val rawBitmap = BitmapFactory.decodeFile(tempFile.absolutePath)
                            val uprightBitmap = if (!matrix.isIdentity) {
                                Bitmap.createBitmap(rawBitmap, 0, 0, rawBitmap.width, rawBitmap.height, matrix, true)
                            } else {
                                rawBitmap
                            }

                            val rawFile = File(context.cacheDir, "raw_${System.currentTimeMillis()}.jpg")
                            FileOutputStream(rawFile).use { out ->
                                uprightBitmap.compress(Bitmap.CompressFormat.JPEG, 95, out)
                            }

                            var croppedPath = rawFile.absolutePath
                            val pts = latestNormalizedPoints?.clone()

                            // 2. Perform perspective warp only if Auto Mode and valid corners exist
                            if (isAutoMode && pts != null && pts.size == 8) {
                                val doublePoints = pts.map { it.toDouble() }
                                croppedPath = DocumentProcessingEngine.cropImage(
                                    context.cacheDir,
                                    rawFile.absolutePath,
                                    doublePoints
                                )
                            }

                            // Cleanup
                            if (uprightBitmap !== rawBitmap) rawBitmap.recycle()
                            uprightBitmap.recycle()
                            tempFile.delete()

                            val response = mapOf(
                                "rawPath" to rawFile.absolutePath,
                                "croppedPath" to croppedPath,
                                "corners" to (if (isAutoMode && pts != null) pts.toList() else emptyList<Float>())
                            )

                            mainHandler.post {
                                isCapturing = false
                                overlayView.updatePoints(null)
                                overlayView.setIsReady(false)
                                if (result != null) {
                                    result.success(response)
                                } else {
                                    methodChannel.invokeMethod("onPhotoCaptured", response)
                                }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error processing captured photo: ${e.message}", e)
                            mainHandler.post {
                                isCapturing = false
                                result?.error("ERR", e.message, null)
                            }
                        }
                    }
                }

                override fun onError(exception: ImageCaptureException) {
                    Log.e(TAG, "ImageCapture error: ${exception.message}", exception)
                    mainHandler.post {
                        isCapturing = false
                        result?.error("ERR", exception.message, null)
                    }
                }
            }
        )
    }

    fun pauseScanner() {
        isPaused = true
        try {
            camera?.cameraControl?.enableTorch(false)
            cameraProvider?.unbindAll()
            camera = null
            Log.d(TAG, "Camera stopped and unbound from lifecycle.")
        } catch (e: Exception) {
            Log.e(TAG, "pauseScanner error: ${e.message}")
        }
        mainHandler.post {
            overlayView.updatePoints(null)
            overlayView.setIsReady(false)
        }
        latestNormalizedPoints = null
        stableStartTime = 0L
        cornerDetector.resetStabilization()
    }

    fun resumeScanner() {
        isPaused = false
        isCapturing = false
        stableStartTime = 0L
        cornerDetector.resetStabilization()
        startCamera()
        updateStatus(if (isAutoMode) "searching" else "manual")
        Log.d(TAG, "Camera resumed.")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setFlashMode" -> {
                val mode = call.argument<String>("mode") ?: "off"
                setFlashMode(mode)
                result.success(true)
            }
            "setAutoMode" -> {
                val auto = call.argument<Boolean>("isAuto") ?: true
                setAutoMode(auto)
                result.success(true)
            }
            "setCaptureType" -> {
                val type = call.argument<String>("type") ?: "Document"
                setCaptureType(type)
                result.success(true)
            }
            "takePhoto" -> {
                takePhoto(result)
            }
            "pauseScanner" -> {
                pauseScanner()
                result.success(true)
            }
            "resumeScanner" -> {
                resumeScanner()
                result.success(true)
            }
            "setDiagnosticsEnabled" -> {
                isDiagnosticsEnabled = call.argument<Boolean>("enabled") ?: false
                mainHandler.post {
                    overlayView.setDiagnosticsEnabled(isDiagnosticsEnabled)
                }
                result.success(true)
            }
            "getProfileMetrics" -> {
                result.success(metricsToMap(cornerDetector.latestMetrics))
            }
            "benchmarkBackends" -> {
                cameraExecutor.execute {
                    val benchResults = cornerDetector.benchmarkBackends()
                    mainHandler.post {
                        result.success(benchResults)
                    }
                }
            }
            "setBackend" -> {
                val backendName = call.argument<String>("backend") ?: "CPU_3_THREADS"
                val backend = try {
                    BackendType.valueOf(backendName)
                } catch (_: Exception) {
                    BackendType.CPU_3_THREADS
                }
                cameraExecutor.execute {
                    val success = cornerDetector.initializeBackend(backend)
                    mainHandler.post {
                        result.success(success)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }
}
