package com.smsram.docuray

import android.content.Context
import android.graphics.BitmapFactory
import android.os.Bundle
import com.smsram.docuray.scanner.CornerDetector
import com.smsram.docuray.scanner.DocScannerViewFactory
import com.smsram.docuray.scanner.DocumentProcessingEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.OpenCVLoader
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val bgExecutor = Executors.newSingleThreadExecutor()
    private var cornerDetector: CornerDetector? = null
    private val REQUEST_CODE_SAF_CREATE = 1001
    private var pendingSafResult: MethodChannel.Result? = null
    private var pendingSourcePath: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Thread-safe centralized OpenCV initialization
        DocumentProcessingEngine.initializeOpenCV()
        applySavedTheme()
    }

    private fun applySavedTheme() {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val savedTheme = prefs.getString("flutter.theme_mode", null)
            if (savedTheme == "dark") {
                window.setBackgroundDrawableResource(R.drawable.launch_background_dark)
            } else if (savedTheme == "light") {
                window.setBackgroundDrawableResource(R.drawable.launch_background)
            }
        } catch (_: Exception) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Register DocScannerView PlatformView
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "doc_scanner_view",
            DocScannerViewFactory(this, flutterEngine.dartExecutor.binaryMessenger)
        )

        // 2. Register Document Processing Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.docuray/document_processing").setMethodCallHandler { call, result ->
            bgExecutor.execute {
                try {
                    when (call.method) {
                        "processPage" -> {
                            val path = call.argument<String>("path") ?: ""
                            val points = call.argument<List<Double>>("points")
                            val degrees = call.argument<Int>("degrees") ?: 0
                            val filter = call.argument<String>("filter") ?: "original"
                            val b = (call.argument<Number>("brightness")?.toFloat()) ?: 0f
                            val c = (call.argument<Number>("contrast")?.toFloat()) ?: 0f
                            val s = (call.argument<Number>("sharpness")?.toFloat()) ?: 0f
                            val maxDim = call.argument<Int>("maxDimension") ?: 0
                            val quality = call.argument<Int>("quality") ?: 90
                            val outPath = DocumentProcessingEngine.processPage(
                                cacheDir, path, points, degrees, filter, b, c, s, maxDim, quality
                            )
                            runOnUiThread { result.success(outPath) }
                        }
                        "cropImage" -> {
                            val path = call.argument<String>("path") ?: ""
                            val points = call.argument<List<Double>>("points") ?: emptyList()
                            val outPath = DocumentProcessingEngine.cropImage(cacheDir, path, points)
                            runOnUiThread { result.success(outPath) }
                        }
                        "rotateImage" -> {
                            val path = call.argument<String>("path") ?: ""
                            val degrees = call.argument<Int>("degrees") ?: 0
                            val outPath = DocumentProcessingEngine.rotateImage(cacheDir, path, degrees)
                            runOnUiThread { result.success(outPath) }
                        }
                        "applyFilter" -> {
                            val path = call.argument<String>("path") ?: ""
                            val filter = call.argument<String>("filter") ?: "Original"
                            val outPath = DocumentProcessingEngine.applyFilter(cacheDir, path, filter)
                            runOnUiThread { result.success(outPath) }
                        }
                        "adjustImage" -> {
                            val path = call.argument<String>("path") ?: ""
                            val b = (call.argument<Number>("brightness")?.toFloat()) ?: 0f
                            val c = (call.argument<Number>("contrast")?.toFloat()) ?: 0f
                            val e = (call.argument<Number>("exposure")?.toFloat()) ?: 0f
                            val s = (call.argument<Number>("sharpness")?.toFloat()) ?: 0f
                            val outPath = DocumentProcessingEngine.adjustImage(cacheDir, path, b, c, e, s)
                            runOnUiThread { result.success(outPath) }
                        }
                        "detectCorners" -> {
                            val path = call.argument<String>("path") ?: ""
                            if (cornerDetector == null) {
                                cornerDetector = CornerDetector(this)
                            }
                            val file = File(path)
                            if (!file.exists()) {
                                runOnUiThread { result.error("NOT_FOUND", "File not found", null) }
                                return@execute
                            }
                            val bmp = BitmapFactory.decodeFile(file.absolutePath)
                            if (bmp == null) {
                                runOnUiThread { result.error("DECODE_ERR", "Could not decode image", null) }
                                return@execute
                            }
                            val cornerResult = cornerDetector!!.detectFromBitmap(bmp, 0f)
                            bmp.recycle()

                            val resMap = mapOf(
                                "corners" to cornerResult.corners.toList(),
                                "confidence" to cornerResult.confidence,
                                "isValid" to cornerResult.isValid
                            )
                            runOnUiThread { result.success(resMap) }
                        }
                        "isOpenCVAvailable" -> {
                            val available = DocumentProcessingEngine.isOpenCVAvailable()
                            runOnUiThread { result.success(available) }
                        }
                        "savePdfToDevice" -> {
                            val sourcePath = call.argument<String>("sourcePath") ?: ""
                            val suggestedName = call.argument<String>("suggestedName") ?: "Document.pdf"
                            val mimeType = call.argument<String>("mimeType") ?: "application/pdf"

                            val sourceFile = File(sourcePath)
                            if (!sourceFile.exists()) {
                                runOnUiThread { result.error("FILE_NOT_FOUND", "Source file does not exist", null) }
                                return@execute
                            }

                            runOnUiThread {
                                pendingSafResult = result
                                pendingSourcePath = sourcePath
                                try {
                                    val intent = android.content.Intent(android.content.Intent.ACTION_CREATE_DOCUMENT).apply {
                                        addCategory(android.content.Intent.CATEGORY_OPENABLE)
                                        type = mimeType
                                        putExtra(android.content.Intent.EXTRA_TITLE, suggestedName)
                                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                                            putExtra(
                                                android.provider.DocumentsContract.EXTRA_INITIAL_URI,
                                                android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI
                                            )
                                        }
                                    }
                                    startActivityForResult(intent, REQUEST_CODE_SAF_CREATE)
                                } catch (e: Exception) {
                                    pendingSafResult = null
                                    pendingSourcePath = null
                                    result.error("SAF_ERROR", "Could not open system file picker: ${e.message}", null)
                                }
                            }
                        }
                        else -> {
                            runOnUiThread { result.notImplemented() }
                        }
                    }
                } catch (e: Exception) {
                    android.util.Log.e("DocuRay", "MethodChannel error during ${call.method}", e)
                    runOnUiThread { result.error("PROCESSING_ERR", e.message, null) }
                } catch (t: Throwable) {
                    android.util.Log.e("DocuRay", "MethodChannel fatal error during ${call.method}", t)
                    runOnUiThread { result.error("PROCESSING_FATAL", t.message, null) }
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_SAF_CREATE) {
            val localResult = pendingSafResult
            val sourcePath = pendingSourcePath
            pendingSafResult = null
            pendingSourcePath = null

            if (resultCode == android.app.Activity.RESULT_OK && data?.data != null && sourcePath != null) {
                val targetUri = data.data!!
                bgExecutor.execute {
                    try {
                        val sourceFile = File(sourcePath)
                        contentResolver.openOutputStream(targetUri)?.use { output ->
                            sourceFile.inputStream().use { input ->
                                input.copyTo(output)
                            }
                            output.flush()
                        }
                        runOnUiThread { localResult?.success(targetUri.toString()) }
                    } catch (e: Exception) {
                        android.util.Log.e("DocuRay", "Error writing to SAF URI: $targetUri", e)
                        runOnUiThread { localResult?.error("IO_ERROR", "Failed to write file to device: ${e.message}", null) }
                    }
                }
            } else {
                localResult?.success(null)
            }
        }
    }

    override fun onDestroy() {
        cornerDetector?.close()
        bgExecutor.shutdown()
        super.onDestroy()
    }
}
