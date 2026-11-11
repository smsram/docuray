package com.docuray.docuray

import android.content.Context
import android.graphics.BitmapFactory
import android.os.Bundle
import com.docuray.docuray.scanner.CornerDetector
import com.docuray.docuray.scanner.DocScannerViewFactory
import com.docuray.docuray.scanner.DocumentProcessingEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val bgExecutor = Executors.newSingleThreadExecutor()
    private var cornerDetector: CornerDetector? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
                        else -> {
                            runOnUiThread { result.notImplemented() }
                        }
                    }
                } catch (e: Exception) {
                    runOnUiThread { result.error("PROCESSING_ERR", e.message, null) }
                }
            }
        }
    }

    override fun onDestroy() {
        cornerDetector?.close()
        bgExecutor.shutdown()
        super.onDestroy()
    }
}
