package com.smsram.docuray.scanner

import android.content.Context
import android.graphics.*
import android.media.ExifInterface
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.*
import org.opencv.core.Point
import org.opencv.imgproc.Imgproc
import org.opencv.photo.Photo
import java.io.File
import java.io.FileOutputStream
import kotlin.math.*

object DocumentProcessingEngine {

    @Volatile
    private var isInitialized = false
    @Volatile
    private var initError: String? = null
    private val initLock = Any()

    /**
     * Initializes OpenCV native library exactly once in a thread-safe manner.
     * Safely catches both Exception and Throwable (e.g. UnsatisfiedLinkError).
     * Avoids class-loading crashes in static initializers.
     */
    fun initializeOpenCV(): Boolean {
        if (isInitialized) return true
        synchronized(initLock) {
            if (isInitialized) return true
            try {
                val success = OpenCVLoader.initDebug()
                if (success) {
                    isInitialized = true
                    initError = null
                    android.util.Log.i("DocuRay", "OpenCV native library loaded successfully (v${Core.VERSION})")
                    return true
                } else {
                    initError = "OpenCVLoader.initDebug() returned false"
                    android.util.Log.e("DocuRay", "OpenCV initialization failed: $initError")
                    return false
                }
            } catch (t: Throwable) {
                initError = "OpenCV native library failed to load: ${t.message}"
                android.util.Log.e("DocuRay", "OpenCV native loading exception", t)
                return false
            }
        }
    }

    fun isOpenCVAvailable(): Boolean {
        return if (isInitialized) true else initializeOpenCV()
    }

    fun getInitializationError(): String? = initError

    /**
     * Shared intermediate preprocessing data matching the Python OpenCV pipeline:
     * - normL: Normalized L-channel (CV_8U) after 2-stage illumination and micro-crease flattening
     * - fineStrokeSignal: Sharpness-gated fine stroke detector signal (CV_32F)
     * - aClean: Paper-color-cast neutralized A-channel (CV_32F)
     * - bClean: Paper-color-cast neutralized B-channel (CV_32F)
     */
    data class PreprocessedData(
        var key: String,
        val width: Int,
        val height: Int,
        val normL: Mat,
        val fineStrokeSignal: Mat,
        val aClean: Mat,
        val bClean: Mat
    )

    private var cachedPreproc: PreprocessedData? = null

    @Synchronized
    fun clearPreprocCache() {
        cachedPreproc?.let {
            if (!it.normL.empty()) it.normL.release()
            if (!it.fineStrokeSignal.empty()) it.fineStrokeSignal.release()
            if (!it.aClean.empty()) it.aClean.release()
            if (!it.bClean.empty()) it.bClean.release()
        }
        cachedPreproc = null
    }

    /**
     * Unified single-pass processing pipeline:
     * EXIF correction -> Homography warp (if points) -> Rotation -> Filter -> Adjustments -> Save.
     * Reuses shared preprocessed data when switching filters on the same image.
     */
    fun processPage(
        cacheDir: File,
        uriString: String,
        points: List<Double>?,
        degrees: Int = 0,
        filterType: String = "original",
        brightness: Float = 0f,
        contrast: Float = 0f,
        sharpness: Float = 0f,
        maxDimension: Int = 0,
        quality: Int = 90
    ): String {
        val path = uriString.replace("file://", "")
        val srcFile = File(path)
        if (!srcFile.exists()) {
            throw Exception("File does not exist: $path")
        }

        // 1. Determine inSampleSize if downsampling is requested (e.g. for preview)
        var sampleSize = 1
        if (maxDimension > 0) {
            val boundsOptions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, boundsOptions)
            val maxSide = max(boundsOptions.outWidth, boundsOptions.outHeight)
            if (maxSide > maxDimension) {
                sampleSize = 1
                while (maxSide / (sampleSize * 2) >= maxDimension) {
                    sampleSize *= 2
                }
            }
        }

        val decodeOptions = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }

        var currentBitmap: Bitmap = BitmapFactory.decodeFile(path, decodeOptions)
            ?: throw Exception("Cannot decode image from $path")

        val bitmapsToRecycle = mutableListOf<Bitmap>()
        bitmapsToRecycle.add(currentBitmap)

        try {
            // 2. Correct EXIF Orientation if needed
            val exifRotation = getExifRotation(path)
            if (exifRotation != 0) {
                val matrix = Matrix().apply { postRotate(exifRotation.toFloat()) }
                val rotated = Bitmap.createBitmap(
                    currentBitmap, 0, 0, currentBitmap.width, currentBitmap.height, matrix, true
                )
                if (rotated !== currentBitmap) {
                    bitmapsToRecycle.add(rotated)
                    currentBitmap = rotated
                }
            }

            // 3. Perspective Homography Warp (if 4 valid corners provided)
            if (points != null && points.size >= 8) {
                val isFullFrame = points[0] <= 0.01 && points[1] <= 0.01 &&
                        points[2] >= 0.99 && points[3] <= 0.01 &&
                        points[4] >= 0.99 && points[5] >= 0.99 &&
                        points[6] <= 0.01 && points[7] >= 0.99
                if (!isFullFrame) {
                    val warped = warpQuad(currentBitmap, points)
                    if (warped !== currentBitmap) {
                        bitmapsToRecycle.add(warped)
                        currentBitmap = warped
                    }
                }
            }

            // 4. User Rotation
            if (degrees % 360 != 0) {
                val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
                val rotated = Bitmap.createBitmap(
                    currentBitmap, 0, 0, currentBitmap.width, currentBitmap.height, matrix, true
                )
                if (rotated !== currentBitmap) {
                    bitmapsToRecycle.add(rotated)
                    currentBitmap = rotated
                }
            }

            // 5. Filter Preset using the OpenCV shared preprocessing pipeline
            val normalizedFilter = normalizeFilterName(filterType)
            if (normalizedFilter != "Original") {
                val cacheKey = "$path:${points?.joinToString(",")}:$degrees:$maxDimension:${currentBitmap.width}x${currentBitmap.height}"
                val filtered = applyFilterInternal(currentBitmap, normalizedFilter, cacheKey)
                if (filtered !== currentBitmap) {
                    bitmapsToRecycle.add(filtered)
                    currentBitmap = filtered
                }
            }

            // 6. Manual Adjustments (Brightness, Contrast, Sharpness)
            if (brightness != 0f || contrast != 0f || sharpness != 0f) {
                val adjusted = adjustInternal(currentBitmap, brightness, contrast, sharpness)
                if (adjusted !== currentBitmap) {
                    bitmapsToRecycle.add(adjusted)
                    currentBitmap = adjusted
                }
            }

            // 7. Save output
            return saveBitmapWithQuality(cacheDir, currentBitmap, "doc_proc", quality)
        } finally {
            for (b in bitmapsToRecycle) {
                if (!b.isRecycled) {
                    b.recycle()
                }
            }
        }
    }

    fun cropImage(cacheDir: File, uriString: String, points: List<Double>): String {
        if (points.size < 8) return uriString
        val path = uriString.replace("file://", "")
        val srcBitmap = BitmapFactory.decodeFile(path) ?: throw Exception("Cannot load image from $uriString")
        return try {
            val warped = warpQuad(srcBitmap, points)
            try {
                saveBitmap(cacheDir, warped, "crop")
            } finally {
                if (warped !== srcBitmap && !warped.isRecycled) warped.recycle()
            }
        } finally {
            if (!srcBitmap.isRecycled) srcBitmap.recycle()
        }
    }

    fun rotateImage(cacheDir: File, uriString: String, degrees: Int): String {
        if (degrees % 360 == 0) return uriString
        val path = uriString.replace("file://", "")
        val srcBitmap = BitmapFactory.decodeFile(path) ?: throw Exception("Cannot load image from $uriString")
        return try {
            val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
            val rotated = Bitmap.createBitmap(srcBitmap, 0, 0, srcBitmap.width, srcBitmap.height, matrix, true)
            try {
                saveBitmap(cacheDir, rotated, "rotate")
            } finally {
                if (rotated !== srcBitmap && !rotated.isRecycled) rotated.recycle()
            }
        } finally {
            if (!srcBitmap.isRecycled) srcBitmap.recycle()
        }
    }

    fun applyFilter(cacheDir: File, uriString: String, filterType: String): String {
        val normalizedFilter = normalizeFilterName(filterType)
        if (normalizedFilter == "Original") return uriString
        val path = uriString.replace("file://", "")
        val srcBitmap = BitmapFactory.decodeFile(path) ?: throw Exception("Cannot load image from $uriString")
        return try {
            val filtered = applyFilterInternal(srcBitmap, normalizedFilter, "$path:standalone")
            try {
                saveBitmap(cacheDir, filtered, "filter")
            } finally {
                if (filtered !== srcBitmap && !filtered.isRecycled) filtered.recycle()
            }
        } finally {
            if (!srcBitmap.isRecycled) srcBitmap.recycle()
        }
    }

    fun adjustImage(
        cacheDir: File,
        uriString: String,
        brightness: Float,
        contrast: Float,
        exposure: Float,
        sharpness: Float
    ): String {
        if (brightness == 0f && contrast == 0f && exposure == 0f && sharpness == 0f) return uriString
        val path = uriString.replace("file://", "")
        val srcBitmap = BitmapFactory.decodeFile(path) ?: throw Exception("Cannot load image from $uriString")
        return try {
            val adjusted = adjustInternal(srcBitmap, brightness, contrast, sharpness)
            try {
                saveBitmap(cacheDir, adjusted, "adjust")
            } finally {
                if (adjusted !== srcBitmap && !adjusted.isRecycled) adjusted.recycle()
            }
        } finally {
            if (!srcBitmap.isRecycled) srcBitmap.recycle()
        }
    }

    private fun normalizeFilterName(name: String): String {
        return when (name.lowercase().trim().replace("_", " ").replace("-", " ")) {
            "auto", "auto color", "color", "magic color" -> "Auto-Color"
            "light text", "lighttext" -> "Light Text"
            "grayscale", "gray" -> "Grayscale"
            "whiteboard" -> "Whiteboard"
            "b&w", "bw", "black and white" -> "B&W"
            else -> "Original"
        }
    }

    private fun warpQuad(srcBitmap: Bitmap, points: List<Double>): Bitmap {
        val w = srcBitmap.width.toFloat()
        val h = srcBitmap.height.toFloat()

        val srcCoords = floatArrayOf(
            (points[0] * w).toFloat().coerceIn(0f, w),
            (points[1] * h).toFloat().coerceIn(0f, h),
            (points[2] * w).toFloat().coerceIn(0f, w),
            (points[3] * h).toFloat().coerceIn(0f, h),
            (points[4] * w).toFloat().coerceIn(0f, w),
            (points[5] * h).toFloat().coerceIn(0f, h),
            (points[6] * w).toFloat().coerceIn(0f, w),
            (points[7] * h).toFloat().coerceIn(0f, h)
        )

        val widthTop = hypot((srcCoords[2] - srcCoords[0]).toDouble(), (srcCoords[3] - srcCoords[1]).toDouble())
        val widthBottom = hypot((srcCoords[4] - srcCoords[6]).toDouble(), (srcCoords[5] - srcCoords[7]).toDouble())
        val newWidth = max(widthTop, widthBottom).toInt().coerceIn(64, 4096)

        val heightLeft = hypot((srcCoords[6] - srcCoords[0]).toDouble(), (srcCoords[7] - srcCoords[1]).toDouble())
        val heightRight = hypot((srcCoords[4] - srcCoords[2]).toDouble(), (srcCoords[5] - srcCoords[3]).toDouble())
        val newHeight = max(heightLeft, heightRight).toInt().coerceIn(64, 4096)

        val destCoords = floatArrayOf(
            0f, 0f,
            newWidth.toFloat(), 0f,
            newWidth.toFloat(), newHeight.toFloat(),
            0f, newHeight.toFloat()
        )

        val matrix = Matrix()
        val success = matrix.setPolyToPoly(srcCoords, 0, destCoords, 0, 4)
        if (!success) {
            return Bitmap.createBitmap(srcBitmap)
        }

        val warped = Bitmap.createBitmap(newWidth, newHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(warped)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        canvas.drawBitmap(srcBitmap, matrix, paint)
        return warped
    }

    private fun getExifRotation(path: String): Int {
        return try {
            val exif = ExifInterface(path)
            when (exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90
                ExifInterface.ORIENTATION_ROTATE_180 -> 180
                ExifInterface.ORIENTATION_ROTATE_270 -> 270
                else -> 0
            }
        } catch (_: Exception) {
            0
        }
    }

    // =========================================================================
    // OpenCV Python Reference Implementation
    // =========================================================================

    /**
     * Two-stage Morphological Illumination Estimator:
     * 1. Protects large solid dark banners via morphological closing + Telea inpainting.
     * 2. Uses 17x17 closing filter to bridge over handwriting and pencil lines while
     *    closely hugging sharp paper creases and notebook spine shadows.
     */
    fun getCreaseFreeIllumination(lChannel: Mat): Mat {
        val h = lChannel.rows()
        val w = lChannel.cols()
        val scale = 800.0 / max(h, w)
        val sh = max(100, (h * scale).toInt())
        val sw = max(100, (w * scale).toInt())

        val small = Mat()
        Imgproc.resize(lChannel, small, Size(sw.toDouble(), sh.toDouble()), 0.0, 0.0, Imgproc.INTER_AREA)

        // Stage 1: Protect only large dark solid banners
        val kCoarse = max(35, (min(sh, sw) * 0.22).toInt() or 1)
        val kernCoarse = Imgproc.getStructuringElement(Imgproc.MORPH_ELLIPSE, Size(kCoarse.toDouble(), kCoarse.toDouble()))
        val coarseBg = Mat()
        Imgproc.morphologyEx(small, coarseBg, Imgproc.MORPH_CLOSE, kernCoarse)
        kernCoarse.release()

        val nSmall = sh * sw
        val smallBytes = ByteArray(nSmall)
        val coarseBytes = ByteArray(nSmall)
        val maskBytes = ByteArray(nSmall)
        small.get(0, 0, smallBytes)
        coarseBg.get(0, 0, coarseBytes)
        coarseBg.release()

        var hasBanner = false
        for (i in 0 until nSmall) {
            val s = smallBytes[i].toInt() and 0xFF
            val c = coarseBytes[i].toInt() and 0xFF
            if ((c - s > 55) && (s < 115)) {
                maskBytes[i] = 255.toByte()
                hasBanner = true
            } else {
                maskBytes[i] = 0
            }
        }

        val bannerMask = Mat(sh, sw, CvType.CV_8U)
        bannerMask.put(0, 0, maskBytes)
        val kernDilate = Imgproc.getStructuringElement(Imgproc.MORPH_ELLIPSE, Size(9.0, 9.0))
        Imgproc.dilate(bannerMask, bannerMask, kernDilate)
        kernDilate.release()

        val paperNoBanners = Mat()
        if (hasBanner) {
            Photo.inpaint(small, bannerMask, paperNoBanners, 7.0, Photo.INPAINT_TELEA)
        } else {
            small.copyTo(paperNoBanners)
        }
        small.release()
        bannerMask.release()

        // Stage 2: Follow paper folds and spine shadows while bridging over text/pencil
        val kernFine = Imgproc.getStructuringElement(Imgproc.MORPH_ELLIPSE, Size(17.0, 17.0))
        val fineBg = Mat()
        Imgproc.morphologyEx(paperNoBanners, fineBg, Imgproc.MORPH_CLOSE, kernFine)
        kernFine.release()
        paperNoBanners.release()

        Imgproc.GaussianBlur(fineBg, fineBg, Size(21.0, 21.0), 0.0)

        val illumFull = Mat()
        Imgproc.resize(fineBg, illumFull, Size(w.toDouble(), h.toDouble()), 0.0, 0.0, Imgproc.INTER_CUBIC)
        fineBg.release()

        Core.max(illumFull, Scalar(20.0), illumFull)
        return illumFull
    }

    /**
     * Shared preprocessing pipeline:
     * 1. Primary illumination normalization
     * 2. Micro-crease flattener for sharp paper folds
     * 3. Sharpness-gated fine stroke detector (amplifies sharp pencil/signatures, rejects blurry bleed-through)
     * 4. Paper color cast neutralization on A & B channels
     */
    fun preprocessDocument(imgBgr: Mat): PreprocessedData {
        val h = imgBgr.rows()
        val w = imgBgr.cols()
        val n = h * w

        val lab = Mat()
        Imgproc.cvtColor(imgBgr, lab, Imgproc.COLOR_BGR2Lab)
        val channels = ArrayList<Mat>(3)
        Core.split(lab, channels)
        val l = channels[0]
        val a = channels[1]
        val b = channels[2]
        lab.release()

        // 1. Primary illumination normalization
        val illumL = getCreaseFreeIllumination(l)
        val normL = Mat()
        Core.divide(l, illumL, normL, 255.0, CvType.CV_8U)
        l.release()
        illumL.release()

        // 2. Micro-crease flattener for sharp paper folds
        val scale = 800.0 / max(h, w)
        val sh = (h * scale).toInt()
        val sw = (w * scale).toInt()
        val nSmall = sh * sw

        val normSmall = Mat()
        Imgproc.resize(normL, normSmall, Size(sw.toDouble(), sh.toDouble()), 0.0, 0.0, Imgproc.INTER_AREA)

        val normSmallBytes = ByteArray(nSmall)
        val paperBytes = ByteArray(nSmall)
        normSmall.get(0, 0, normSmallBytes)
        normSmall.release()

        for (i in 0 until nSmall) {
            val v = normSmallBytes[i].toInt() and 0xFF
            paperBytes[i] = if (v < 165) 255.toByte() else v.toByte()
        }
        val paperEst = Mat(sh, sw, CvType.CV_8U)
        paperEst.put(0, 0, paperBytes)

        val kernRes = Imgproc.getStructuringElement(Imgproc.MORPH_ELLIPSE, Size(13.0, 13.0))
        val resBg = Mat()
        Imgproc.morphologyEx(paperEst, resBg, Imgproc.MORPH_CLOSE, kernRes)
        paperEst.release()
        kernRes.release()

        Imgproc.GaussianBlur(resBg, resBg, Size(15.0, 15.0), 0.0)

        val resBgFull = Mat()
        Imgproc.resize(resBg, resBgFull, Size(w.toDouble(), h.toDouble()), 0.0, 0.0, Imgproc.INTER_CUBIC)
        resBg.release()

        Core.max(resBgFull, Scalar(180.0), resBgFull)
        Core.divide(normL, resBgFull, normL, 255.0, CvType.CV_8U)
        resBgFull.release()

        // 3. Sharpness-Gated Fine Stroke Detector
        val lFloat = Mat()
        normL.convertTo(lFloat, CvType.CV_32F)

        val gFine = Mat()
        Imgproc.GaussianBlur(lFloat, gFine, Size(0.0, 0.0), 0.7)

        val gSurround = Mat()
        Imgproc.GaussianBlur(lFloat, gSurround, Size(0.0, 0.0), 3.6)
        lFloat.release()

        val gFineArr = FloatArray(n)
        gFine.get(0, 0, gFineArr)
        val gSurroundArr = FloatArray(n)
        gSurround.get(0, 0, gSurroundArr)
        gSurround.release()

        val rawDogArr = FloatArray(n)
        for (i in 0 until n) {
            val diff = gSurroundArr[i] - gFineArr[i] - 2.4f
            rawDogArr[i] = if (diff > 0f) diff else 0f
        }

        val gx = Mat()
        val gy = Mat()
        Imgproc.Sobel(gFine, gx, CvType.CV_32F, 1, 0, 3, 1.0, 0.0)
        Imgproc.Sobel(gFine, gy, CvType.CV_32F, 0, 1, 3, 1.0, 0.0)
        gFine.release()

        val mag = Mat()
        Core.magnitude(gx, gy, mag)
        gx.release()
        gy.release()

        val gradMag = Mat()
        Imgproc.GaussianBlur(mag, gradMag, Size(5.0, 5.0), 0.0)
        mag.release()

        val gradMagArr = FloatArray(n)
        gradMag.get(0, 0, gradMagArr)
        gradMag.release()

        val fineStrokeArr = FloatArray(n)
        for (i in 0 until n) {
            val gate = ((gradMagArr[i] - 6.0f) / 14.0f).coerceIn(0.0f, 1.0f)
            fineStrokeArr[i] = rawDogArr[i] * gate
        }
        val fineStrokeSignal = Mat(h, w, CvType.CV_32F)
        fineStrokeSignal.put(0, 0, fineStrokeArr)

        // 4. Neutralize warm/yellow paper color cast in A & B channels
        val aFloat = Mat()
        val bFloat = Mat()
        a.convertTo(aFloat, CvType.CV_32F)
        b.convertTo(bFloat, CvType.CV_32F)
        a.release()
        b.release()

        Core.subtract(aFloat, Scalar(128.0), aFloat)
        Core.subtract(bFloat, Scalar(128.0), bFloat)

        val aBg = Mat()
        val bBg = Mat()
        Imgproc.GaussianBlur(aFloat, aBg, Size(61.0, 61.0), 0.0)
        Imgproc.GaussianBlur(bFloat, bBg, Size(61.0, 61.0), 0.0)

        val aClean = Mat()
        val bClean = Mat()
        Core.addWeighted(aFloat, 1.0, aBg, -0.92, 0.0, aClean)
        Core.addWeighted(bFloat, 1.0, bBg, -0.92, 0.0, bClean)
        aFloat.release()
        bFloat.release()
        aBg.release()
        bBg.release()

        return PreprocessedData(
            key = "",
            width = w,
            height = h,
            normL = normL,
            fineStrokeSignal = fineStrokeSignal,
            aClean = aClean,
            bClean = bClean
        )
    }

    /**
     * Maps normalized lightness and sharpness-gated pencil/ink signal to target tonal range.
     */
    fun renderTonedLightness(
        normL: Mat,
        fineStrokeSignal: Mat,
        blackPt: Double,
        whitePt: Double,
        gamma: Double,
        strokeGain: Double,
        minL: Double = 0.0,
        maxL: Double = 255.0
    ): Mat {
        val h = normL.rows()
        val w = normL.cols()
        val n = h * w

        val normArr = ByteArray(n)
        normL.get(0, 0, normArr)
        val strokeArr = FloatArray(n)
        fineStrokeSignal.get(0, 0, strokeArr)

        val outArr = ByteArray(n)
        val range = max(1.0, whitePt - blackPt)
        val invGamma = if (gamma != 1.0) 1.0 / gamma else 1.0
        val lRange = maxL - minL

        for (i in 0 until n) {
            val nl = (normArr[i].toInt() and 0xFF).toDouble()
            val sig = strokeArr[i].toDouble()
            val enhancedL = (nl - sig * strokeGain).coerceIn(0.0, 255.0)
            var scaled = ((enhancedL - blackPt) / range).coerceIn(0.0, 1.0)
            if (gamma != 1.0) {
                val ink = (1.0 - scaled).pow(invGamma)
                scaled = 1.0 - ink
            }
            val outVal = (minL + scaled * lRange).roundToInt().coerceIn(0, 255)
            outArr[i] = outVal.toByte()
        }
        val outMat = Mat(h, w, CvType.CV_8U)
        outMat.put(0, 0, outArr)
        return outMat
    }

    /**
     * Restores and amplifies ink colors (blue pen, stamps, signatures) while keeping
     * the white paper background completely neutral.
     */
    fun combineColorChannels(
        cleanL: Mat,
        aClean: Mat,
        bClean: Mat,
        chromaBoost: Double = 2.0,
        liftDarkInk: Boolean = false
    ): Mat {
        val h = cleanL.rows()
        val w = cleanL.cols()
        val n = h * w

        val lArr = ByteArray(n)
        cleanL.get(0, 0, lArr)
        val aArr = FloatArray(n)
        aClean.get(0, 0, aArr)
        val bArr = FloatArray(n)
        bClean.get(0, 0, bArr)

        val outL = ByteArray(n)
        val outA = ByteArray(n)
        val outB = ByteArray(n)

        for (i in 0 until n) {
            val lVal = lArr[i].toInt() and 0xFF
            val af = aArr[i].toDouble()
            val bf = bArr[i].toDouble()
            val chromaMag = sqrt(af * af + bf * bf)

            val darknessMask = ((244.0 - lVal) / 26.0).coerceIn(0.0, 1.0)
            val colorMask = ((chromaMag - 2.5) / 8.0).coerceIn(0.0, 1.0)
            val inkWeight = max(darknessMask, colorMask)

            var finalL = lVal
            if (liftDarkInk) {
                val colorInkZone = ((chromaMag - 3.0) / 8.0).coerceIn(0.0, 1.0) * (if (lVal < 90) 1.0 else 0.0)
                finalL = (lVal + colorInkZone * 22.0).roundToInt().coerceIn(0, 255)
            }

            val aVal = (128.0 + af * inkWeight * chromaBoost).roundToInt().coerceIn(0, 255)
            val bVal = (128.0 + bf * inkWeight * chromaBoost).roundToInt().coerceIn(0, 255)

            outL[i] = finalL.toByte()
            outA[i] = aVal.toByte()
            outB[i] = bVal.toByte()
        }

        val matL = Mat(h, w, CvType.CV_8U).apply { put(0, 0, outL) }
        val matA = Mat(h, w, CvType.CV_8U).apply { put(0, 0, outA) }
        val matB = Mat(h, w, CvType.CV_8U).apply { put(0, 0, outB) }

        val mergedLab = Mat()
        Core.merge(listOf(matL, matA, matB), mergedLab)
        matL.release()
        matA.release()
        matB.release()

        val bgr = Mat()
        Imgproc.cvtColor(mergedLab, bgr, Imgproc.COLOR_Lab2BGR)
        mergedLab.release()

        return bgr
    }

    fun unsharpMask(image: Mat, sigma: Double = 0.9, strength: Double = 0.6): Mat {
        val blurred = Mat()
        Imgproc.GaussianBlur(image, blurred, Size(0.0, 0.0), sigma)
        val sharpened = Mat()
        Core.addWeighted(image, 1.0 + strength, blurred, -strength, 0.0, sharpened)
        blurred.release()
        return sharpened
    }

    // -------------------------------------------------------------------------
    // 5 Adobe Scan Filter Presets
    // -------------------------------------------------------------------------

    fun filterAutoColor(preproc: PreprocessedData): Mat {
        val cleanL = renderTonedLightness(
            preproc.normL, preproc.fineStrokeSignal,
            blackPt = 20.0, whitePt = 236.0, gamma = 1.30, strokeGain = 1.5
        )
        val bgr = combineColorChannels(cleanL, preproc.aClean, preproc.bClean, chromaBoost = 2.1, liftDarkInk = true)
        cleanL.release()
        val out = unsharpMask(bgr, sigma = 0.9, strength = 0.55)
        bgr.release()
        return out
    }

    fun filterLightText(preproc: PreprocessedData): Mat {
        val cleanL = renderTonedLightness(
            preproc.normL, preproc.fineStrokeSignal,
            blackPt = 32.0, whitePt = 233.0, gamma = 1.90, strokeGain = 2.8
        )
        val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_ELLIPSE, Size(2.0, 2.0))
        val erodedL = Mat()
        Imgproc.erode(cleanL, erodedL, kernel, Point(-1.0, -1.0), 1)
        kernel.release()

        val boldL = Mat()
        Core.addWeighted(cleanL, 0.30, erodedL, 0.70, 0.0, boldL)
        cleanL.release()
        erodedL.release()

        val bgr = combineColorChannels(boldL, preproc.aClean, preproc.bClean, chromaBoost = 2.4, liftDarkInk = true)
        boldL.release()
        val out = unsharpMask(bgr, sigma = 0.8, strength = 0.80)
        bgr.release()
        return out
    }

    fun filterGrayscale(preproc: PreprocessedData): Mat {
        val grayL = renderTonedLightness(
            preproc.normL, preproc.fineStrokeSignal,
            blackPt = 10.0, whitePt = 244.0, gamma = 1.12, strokeGain = 1.2,
            minL = 38.0, maxL = 245.0
        )
        val out = unsharpMask(grayL, sigma = 1.0, strength = 0.40)
        grayL.release()
        return out
    }

    fun filterWhiteboard(preproc: PreprocessedData): Mat {
        val wbL = renderTonedLightness(
            preproc.normL, preproc.fineStrokeSignal,
            blackPt = 38.0, whitePt = 230.0, gamma = 1.60, strokeGain = 2.0
        )
        val bgr = combineColorChannels(wbL, preproc.aClean, preproc.bClean, chromaBoost = 3.2, liftDarkInk = true)
        wbL.release()
        val out = unsharpMask(bgr, sigma = 0.9, strength = 0.85)
        bgr.release()
        return out
    }

    fun filterBlackAndWhite(preproc: PreprocessedData): Mat {
        val h = preproc.normL.rows()
        val w = preproc.normL.cols()
        val n = h * w

        val normArr = ByteArray(n)
        preproc.normL.get(0, 0, normArr)
        val strokeArr = FloatArray(n)
        preproc.fineStrokeSignal.get(0, 0, strokeArr)

        val enhArr = ByteArray(n)
        for (i in 0 until n) {
            val nl = normArr[i].toInt() and 0xFF
            val enh = (nl - strokeArr[i] * 2.8f).coerceIn(0f, 255f)
            enhArr[i] = enh.roundToInt().toByte()
        }
        val enhMat = Mat(h, w, CvType.CV_8U).apply { put(0, 0, enhArr) }

        val smooth = Mat()
        Imgproc.bilateralFilter(enhMat, smooth, 5, 15.0, 15.0)
        enhMat.release()

        val smoothArr = ByteArray(n)
        smooth.get(0, 0, smoothArr)
        smooth.release()

        val midpoint = 202.0
        val steepness = 0.30
        val lut = ByteArray(256) { v ->
            (255.0 / (1.0 + exp(-steepness * (v - midpoint)))).roundToInt().coerceIn(0, 255).toByte()
        }

        val bwArr = ByteArray(n)
        for (i in 0 until n) {
            val sv = smoothArr[i].toInt() and 0xFF
            bwArr[i] = lut[sv]
        }

        val bwMat = Mat(h, w, CvType.CV_8U).apply { put(0, 0, bwArr) }
        return bwMat
    }

    @Synchronized
    private fun getOrComputePreproc(bgrMat: Mat, cacheKey: String): PreprocessedData {
        if (cacheKey.isNotEmpty() && cachedPreproc != null) {
            val cp = cachedPreproc!!
            if (cp.key == cacheKey && cp.width == bgrMat.cols() && cp.height == bgrMat.rows()) {
                return cp
            }
        }
        clearPreprocCache()
        val newPreproc = preprocessDocument(bgrMat)
        newPreproc.key = cacheKey
        cachedPreproc = newPreproc
        return newPreproc
    }

    private fun applyFilterInternal(src: Bitmap, filterName: String, cacheKey: String = ""): Bitmap {
        if (!isOpenCVAvailable()) {
            throw IllegalStateException("OPENCV_UNAVAILABLE: ${initError ?: "OpenCV native library failed to load"}")
        }
        val rgbaMat = Mat()
        Utils.bitmapToMat(src, rgbaMat)
        val bgrMat = Mat()
        Imgproc.cvtColor(rgbaMat, bgrMat, Imgproc.COLOR_RGBA2BGR)
        rgbaMat.release()

        val preproc = getOrComputePreproc(bgrMat, cacheKey)

        val filteredMat = when (filterName) {
            "Auto-Color" -> filterAutoColor(preproc)
            "Light Text" -> filterLightText(preproc)
            "Grayscale" -> filterGrayscale(preproc)
            "Whiteboard" -> filterWhiteboard(preproc)
            "B&W" -> filterBlackAndWhite(preproc)
            else -> bgrMat.clone()
        }
        bgrMat.release()

        val outBitmap = Bitmap.createBitmap(filteredMat.cols(), filteredMat.rows(), Bitmap.Config.ARGB_8888)
        val outRgba = Mat()
        if (filteredMat.channels() == 1) {
            Imgproc.cvtColor(filteredMat, outRgba, Imgproc.COLOR_GRAY2RGBA)
        } else {
            Imgproc.cvtColor(filteredMat, outRgba, Imgproc.COLOR_BGR2RGBA)
        }
        filteredMat.release()

        Utils.matToBitmap(outRgba, outBitmap)
        outRgba.release()

        return outBitmap
    }

    // -------------------------------------------------------------------------
    // Manual Adjustments (Brightness, Contrast, Denoising & Sharpening)
    // -------------------------------------------------------------------------

    private fun adjustInternal(
        src: Bitmap,
        brightness: Float,
        contrast: Float,
        sharpness: Float
    ): Bitmap {
        val w = src.width
        val h = src.height
        val pixels = IntArray(w * h)
        src.getPixels(pixels, 0, w, 0, 0, w, h)

        val cFactor = max(0f, (contrast + 100f) / 100f)
        val bOffset = (brightness / 100f) * 255f

        val outPixels = IntArray(w * h)
        for (i in pixels.indices) {
            val p = pixels[i]
            var r = ((p shr 16) and 0xFF).toFloat()
            var g = ((p shr 8) and 0xFF).toFloat()
            var b = (p and 0xFF).toFloat()

            if (brightness != 0f) {
                r += bOffset; g += bOffset; b += bOffset
            }
            if (contrast != 0f) {
                r = (r - 128f) * cFactor + 128f
                g = (g - 128f) * cFactor + 128f
                b = (b - 128f) * cFactor + 128f
            }

            outPixels[i] = Color.rgb(
                r.roundToInt().coerceIn(0, 255),
                g.roundToInt().coerceIn(0, 255),
                b.roundToInt().coerceIn(0, 255)
            )
        }

        if (sharpness > 0.05f) {
            val amount = sharpness.coerceIn(0f, 1.0f) * 1.5f
            applyHaloFreeSharpening(outPixels, w, h, amount)
        }

        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        out.setPixels(outPixels, 0, w, 0, 0, w, h)
        return out
    }

    private fun applyHaloFreeSharpening(pixels: IntArray, w: Int, h: Int, amount: Float) {
        val copy = pixels.clone()
        for (y in 1 until h - 1) {
            val row = y * w
            for (x in 1 until w - 1) {
                val idx = row + x

                val p = copy[idx]
                val pU = copy[idx - w]
                val pD = copy[idx + w]
                val pL = copy[idx - 1]
                val pR = copy[idx + 1]

                val rBlur = (Color.red(p) * 2 + Color.red(pU) + Color.red(pD) + Color.red(pL) + Color.red(pR)) / 6f
                val gBlur = (Color.green(p) * 2 + Color.green(pU) + Color.green(pD) + Color.green(pL) + Color.green(pR)) / 6f
                val bBlur = (Color.blue(p) * 2 + Color.blue(pU) + Color.blue(pD) + Color.blue(pL) + Color.blue(pR)) / 6f

                val rDiff = Color.red(p) - rBlur
                val gDiff = Color.green(p) - gBlur
                val bDiff = Color.blue(p) - bBlur

                val rBoost = if (abs(rDiff) > 3f) (rDiff * amount).coerceIn(-28f, 28f) else 0f
                val gBoost = if (abs(gDiff) > 3f) (gDiff * amount).coerceIn(-28f, 28f) else 0f
                val bBoost = if (abs(bDiff) > 3f) (bDiff * amount).coerceIn(-28f, 28f) else 0f

                pixels[idx] = Color.rgb(
                    (Color.red(p) + rBoost).roundToInt().coerceIn(0, 255),
                    (Color.green(p) + gBoost).roundToInt().coerceIn(0, 255),
                    (Color.blue(p) + bBoost).roundToInt().coerceIn(0, 255)
                )
            }
        }
    }

    fun saveBitmap(cacheDir: File, bitmap: Bitmap, prefix: String): String {
        return saveBitmapWithQuality(cacheDir, bitmap, prefix, 92)
    }

    fun saveBitmapWithQuality(cacheDir: File, bitmap: Bitmap, prefix: String, quality: Int): String {
        val outFile = File(cacheDir, "${prefix}_${System.currentTimeMillis()}.jpg")
        FileOutputStream(outFile).use { stream ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(50, 100), stream)
            stream.flush()
        }
        return outFile.absolutePath
    }
}
