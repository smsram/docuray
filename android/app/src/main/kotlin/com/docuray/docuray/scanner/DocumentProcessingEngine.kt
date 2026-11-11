package com.docuray.docuray.scanner

import android.content.Context
import android.graphics.*
import android.media.ExifInterface
import java.io.File
import java.io.FileOutputStream
import kotlin.math.*

object DocumentProcessingEngine {

    /**
     * Unified single-pass processing pipeline:
     * EXIF correction -> Homography warp (if points) -> Rotation -> Filter -> Adjustments -> Save.
     * Prevents multi-step disk I/O and repeated JPEG re-compression.
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

            // 5. Filter Preset
            val normalizedFilter = normalizeFilterName(filterType)
            if (normalizedFilter != "Original") {
                val filtered = applyFilterInternal(currentBitmap, normalizedFilter)
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

    // Legacy individual methods for backwards compatibility with existing MethodChannel calls:

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
            val filtered = applyFilterInternal(srcBitmap, normalizedFilter)
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

    /**
     * Genuine 4-point perspective warp (Homography).
     * Order: Top-Left, Top-Right, Bottom-Right, Bottom-Left.
     * Computes exact target width and height from opposing edge lengths.
     * Zero unwanted padding/zoom.
     */
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

        // Output dimensions based on opposing edge lengths
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

    // -------------------------------------------------------------------------
    // Professional Document Filters
    // -------------------------------------------------------------------------

    private fun applyFilterInternal(src: Bitmap, filterName: String): Bitmap {
        return when (filterName) {
            "Auto-Color" -> autoColor(src)
            "Light Text" -> lightText(src)
            "Grayscale" -> grayscale(src)
            "Whiteboard" -> whiteboard(src)
            "B&W" -> blackAndWhiteSauvola(src)
            else -> src
        }
    }

    /**
     * AUTO-COLOR:
     * - Estimates uneven illumination and background paper color cast.
     * - Normalizes background without bleaching colored inks, highlighters, or diagrams.
     * - Preserves fine strokes and paper texture without harsh over-saturation.
     */
    private fun autoColor(src: Bitmap): Bitmap {
        val w = src.width
        val h = src.height
        val pixels = IntArray(w * h)
        src.getPixels(pixels, 0, w, 0, 0, w, h)

        // 1. Estimate illumination map using downsampled blur
        val illumMap = estimateIlluminationMap(pixels, w, h)

        val outPixels = IntArray(w * h)
        for (i in pixels.indices) {
            val p = pixels[i]
            val r = (p shr 16) and 0xFF
            val g = (p shr 8) and 0xFF
            val b = p and 0xFF

            val bg = illumMap[i].coerceAtLeast(20f)
            val scale = (248f / bg).coerceIn(0.7f, 1.8f)

            // Normalized paper colors
            val nr = (r * scale).coerceIn(0f, 255f)
            val ng = (g * scale).coerceIn(0f, 255f)
            val nb = (b * scale).coerceIn(0f, 255f)

            // Chroma / Saturation check to protect colored ink & highlighters
            val maxC = max(r, max(g, b)).toFloat()
            val minC = min(r, min(g, b)).toFloat()
            val chroma = maxC - minC

            val finalR: Int
            val finalG: Int
            val finalB: Int

            if (chroma > 22f) {
                // Colored stroke (pen, stamp, diagram, highlighter) -> blend gently with original
                val t = ((chroma - 22f) / 35f).coerceIn(0f, 0.85f)
                finalR = ((1f - t) * nr + t * r).roundToInt().coerceIn(0, 255)
                finalG = ((1f - t) * ng + t * g).roundToInt().coerceIn(0, 255)
                finalB = ((1f - t) * nb + t * b).roundToInt().coerceIn(0, 255)
            } else {
                // Neutral paper / dark text -> apply mild contrast curve for crisp dark strokes
                val lum = (0.299f * nr + 0.587f * ng + 0.114f * nb)
                if (lum > 230f) {
                    finalR = min(255, (nr * 1.02f).roundToInt())
                    finalG = min(255, (ng * 1.02f).roundToInt())
                    finalB = min(255, (nb * 1.02f).roundToInt())
                } else {
                    val cr = (255f * (nr / 255f).pow(1.08f)).roundToInt().coerceIn(0, 255)
                    val cg = (255f * (ng / 255f).pow(1.08f)).roundToInt().coerceIn(0, 255)
                    val cb = (255f * (nb / 255f).pow(1.08f)).roundToInt().coerceIn(0, 255)
                    finalR = cr; finalG = cg; finalB = cb
                }
            }

            outPixels[i] = Color.rgb(finalR, finalG, finalB)
        }

        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        out.setPixels(outPixels, 0, w, 0, 0, w, h)
        return out
    }

    /**
     * LIGHT TEXT:
     * - Normalizes background shadows.
     * - Uses non-linear tonal stretching to make faint pencil, ballpoint ink, and pale receipts readable.
     * - Preserves fine handwriting without erasing light strokes.
     */
    private fun lightText(src: Bitmap): Bitmap {
        val w = src.width
        val h = src.height
        val pixels = IntArray(w * h)
        src.getPixels(pixels, 0, w, 0, 0, w, h)

        val illumMap = estimateIlluminationMap(pixels, w, h)
        val outPixels = IntArray(w * h)

        for (i in pixels.indices) {
            val p = pixels[i]
            val r = (p shr 16) and 0xFF
            val g = (p shr 8) and 0xFF
            val b = p and 0xFF

            val bg = illumMap[i].coerceAtLeast(20f)
            val scale = (252f / bg).coerceIn(0.8f, 2.0f)

            var nr = (r * scale).coerceIn(0f, 255f)
            var ng = (g * scale).coerceIn(0f, 255f)
            var nb = (b * scale).coerceIn(0f, 255f)

            val lum = 0.299f * nr + 0.587f * ng + 0.114f * nb

            if (lum > 228f) {
                // Paper background smoothly whitened
                nr = 255f
                ng = 255f
                nb = 255f
            } else {
                // Faint text stretched downwards for dark, readable strokes
                val norm = (lum / 228f).coerceIn(0f, 1f)
                val stretch = norm.pow(1.6f) * 190f
                val ratio = (stretch / lum.coerceAtLeast(1f))
                nr = (nr * ratio).coerceIn(0f, 255f)
                ng = (ng * ratio).coerceIn(0f, 255f)
                nb = (nb * ratio).coerceIn(0f, 255f)
            }

            outPixels[i] = Color.rgb(nr.roundToInt(), ng.roundToInt(), nb.roundToInt())
        }

        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        out.setPixels(outPixels, 0, w, 0, 0, w, h)
        return out
    }

    /**
     * GRAYSCALE:
     * - Standard Rec.601 perceptual luminance: 0.299R + 0.587G + 0.114B.
     * - Dynamic range stretch for optimal contrast without clipping faint details.
     */
    private fun grayscale(src: Bitmap): Bitmap {
        val w = src.width
        val h = src.height
        val pixels = IntArray(w * h)
        src.getPixels(pixels, 0, w, 0, 0, w, h)

        var minLum = 255
        var maxLum = 0
        val lums = IntArray(w * h)

        for (i in pixels.indices) {
            val p = pixels[i]
            val r = (p shr 16) and 0xFF
            val g = (p shr 8) and 0xFF
            val b = p and 0xFF
            val lum = (0.299f * r + 0.587f * g + 0.114f * b).roundToInt().coerceIn(0, 255)
            lums[i] = lum
            if (lum < minLum) minLum = lum
            if (lum > maxLum) maxLum = lum
        }

        val range = (maxLum - minLum).coerceAtLeast(1)
        val outPixels = IntArray(w * h)

        for (i in lums.indices) {
            val lum = lums[i]
            // Contrast-stretched grayscale with gentle S-curve
            val norm = (lum - minLum).toFloat() / range
            val curved = (norm.pow(0.95f) * 255f).roundToInt().coerceIn(0, 255)
            outPixels[i] = Color.rgb(curved, curved, curved)
        }

        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        out.setPixels(outPixels, 0, w, 0, 0, w, h)
        return out
    }

    /**
     * WHITEBOARD:
     * - Reduces uneven illumination, glare, and room shadows across board surfaces.
     * - Amplifies dry-erase markers (Red, Blue, Green, Black).
     * - Whitens melamine/ceramic surface without erasing light marker annotations.
     */
    private fun whiteboard(src: Bitmap): Bitmap {
        val w = src.width
        val h = src.height
        val pixels = IntArray(w * h)
        src.getPixels(pixels, 0, w, 0, 0, w, h)

        val illumMap = estimateIlluminationMap(pixels, w, h)
        val outPixels = IntArray(w * h)

        for (i in pixels.indices) {
            val p = pixels[i]
            val r = (p shr 16) and 0xFF
            val g = (p shr 8) and 0xFF
            val b = p and 0xFF

            val bg = illumMap[i].coerceAtLeast(20f)
            val scale = (252f / bg).coerceIn(0.8f, 2.2f)

            var nr = (r * scale).coerceIn(0f, 255f)
            var ng = (g * scale).coerceIn(0f, 255f)
            var nb = (b * scale).coerceIn(0f, 255f)

            // Check for red, blue, green colored marker ink
            val isRedMarker = r > g + 16 && r > b + 16
            val isBlueMarker = b > r + 14 && b > g + 14
            val isGreenMarker = g > r + 14 && g > b + 14

            if (isRedMarker) {
                nr = min(255f, nr * 1.15f)
                ng = (ng * 0.75f).coerceAtLeast(0f)
                nb = (nb * 0.75f).coerceAtLeast(0f)
            } else if (isBlueMarker) {
                nb = min(255f, nb * 1.18f)
                nr = (nr * 0.70f).coerceAtLeast(0f)
                ng = (ng * 0.85f).coerceAtLeast(0f)
            } else if (isGreenMarker) {
                ng = min(255f, ng * 1.15f)
                nr = (nr * 0.70f).coerceAtLeast(0f)
                nb = (nb * 0.70f).coerceAtLeast(0f)
            } else {
                // Black marker or board background
                val lum = 0.299f * nr + 0.587f * ng + 0.114f * nb
                if (lum > 220f) {
                    nr = 255f; ng = 255f; nb = 255f
                } else {
                    val dark = (lum / 220f).pow(1.4f) * 220f
                    nr = dark; ng = dark; nb = dark
                }
            }

            outPixels[i] = Color.rgb(nr.roundToInt(), ng.roundToInt(), nb.roundToInt())
        }

        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        out.setPixels(outPixels, 0, w, 0, 0, w, h)
        return out
    }

    /**
     * BLACK & WHITE (Sauvola Adaptive Thresholding):
     * - Gold standard document binarization algorithm.
     * - Window size adapts to source resolution.
     * - Threshold formula: T = m * (1 + k * (s / 128 - 1)).
     * - Eliminates shadow patches in blank areas while preserving fine handwriting.
     */
    private fun blackAndWhiteSauvola(src: Bitmap): Bitmap {
        val w = src.width
        val h = src.height
        val pixels = IntArray(w * h)
        src.getPixels(pixels, 0, w, 0, 0, w, h)

        val gray = FloatArray(w * h)
        for (i in pixels.indices) {
            val p = pixels[i]
            val r = (p shr 16) and 0xFF
            val g = (p shr 8) and 0xFF
            val b = p and 0xFF
            gray[i] = 0.299f * r + 0.587f * g + 0.114f * b
        }

        // Adaptive window radius based on image resolution (e.g. ~15px for 600px, ~35px for 2000px)
        val radius = max(12, min(w, h) / 36)

        // Compute local mean and local standard deviation via separable box filter
        val mean = boxFilter(gray, w, h, radius)
        val graySq = FloatArray(w * h) { i -> gray[i] * gray[i] }
        val meanSq = boxFilter(graySq, w, h, radius)

        val outPixels = IntArray(w * h)
        val k = 0.20f
        val rDynamic = 128f

        for (i in gray.indices) {
            val m = mean[i]
            val variance = (meanSq[i] - m * m).coerceAtLeast(0f)
            val s = sqrt(variance)

            // Sauvola adaptive threshold
            val t = m * (1.0f + k * (s / rDynamic - 1.0f))
            val bw = if (gray[i] < t) 0 else 255
            outPixels[i] = Color.rgb(bw, bw, bw)
        }

        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        out.setPixels(outPixels, 0, w, 0, 0, w, h)
        return out
    }

    /**
     * Estimates background illumination map by downsampling to a low-res grid,
     * applying a large blur, and upsampling via bilinear interpolation.
     */
    private fun estimateIlluminationMap(pixels: IntArray, w: Int, h: Int): FloatArray {
        val gridW = 120
        val gridH = max(1, (120f * h / w).roundToInt())

        val smallLum = FloatArray(gridW * gridH)
        val xStep = w.toFloat() / gridW
        val yStep = h.toFloat() / gridH

        for (gy in 0 until gridH) {
            val sy = (gy * yStep).toInt().coerceIn(0, h - 1)
            for (gx in 0 until gridW) {
                val sx = (gx * xStep).toInt().coerceIn(0, w - 1)
                val p = pixels[sy * w + sx]
                val r = (p shr 16) and 0xFF
                val g = (p shr 8) and 0xFF
                val b = p and 0xFF
                smallLum[gy * gridW + gx] = 0.299f * r + 0.587f * g + 0.114f * b
            }
        }

        // Apply blur radius 14 on downsampled grid (~ equivalent to 250px on full image)
        val blurredSmall = boxFilter(smallLum, gridW, gridH, 14)

        // Bilinear interpolation back to full resolution
        val outMap = FloatArray(w * h)
        for (y in 0 until h) {
            val gy = (y.toFloat() / (h - 1).coerceAtLeast(1)) * (gridH - 1)
            val y0 = gy.toInt().coerceIn(0, gridH - 1)
            val y1 = min(y0 + 1, gridH - 1)
            val fy = gy - y0

            for (x in 0 until w) {
                val gx = (x.toFloat() / (w - 1).coerceAtLeast(1)) * (gridW - 1)
                val x0 = gx.toInt().coerceIn(0, gridW - 1)
                val x1 = min(x0 + 1, gridW - 1)
                val fx = gx - x0

                val v00 = blurredSmall[y0 * gridW + x0]
                val v10 = blurredSmall[y0 * gridW + x1]
                val v01 = blurredSmall[y1 * gridW + x0]
                val v11 = blurredSmall[y1 * gridW + x1]

                outMap[y * w + x] = v00 * (1f - fx) * (1f - fy) +
                        v10 * fx * (1f - fy) +
                        v01 * (1f - fx) * fy +
                        v11 * fx * fy
            }
        }

        return outMap
    }

    /**
     * Fast separable box filter O(1) per pixel using running sums.
     */
    private fun boxFilter(src: FloatArray, w: Int, h: Int, r: Int): FloatArray {
        val temp = FloatArray(w * h)
        val out = FloatArray(w * h)

        // Horizontal pass
        for (y in 0 until h) {
            val rowOffset = y * w
            var sum = 0f
            // Preload left edge
            for (k in -r..r) {
                sum += src[rowOffset + k.coerceIn(0, w - 1)]
            }
            temp[rowOffset] = sum / (2 * r + 1)

            for (x in 1 until w) {
                val addIdx = (x + r).coerceIn(0, w - 1)
                val subIdx = (x - r - 1).coerceIn(0, w - 1)
                sum += src[rowOffset + addIdx] - src[rowOffset + subIdx]
                temp[rowOffset + x] = sum / (2 * r + 1)
            }
        }

        // Vertical pass
        for (x in 0 until w) {
            var sum = 0f
            for (k in -r..r) {
                val yIdx = k.coerceIn(0, h - 1)
                sum += temp[yIdx * w + x]
            }
            out[x] = sum / (2 * r + 1)

            for (y in 1 until h) {
                val addIdx = (y + r).coerceIn(0, h - 1)
                val subIdx = (y - r - 1).coerceIn(0, h - 1)
                sum += temp[addIdx * w + x] - temp[subIdx * w + x]
                out[y * w + x] = sum / (2 * r + 1)
            }
        }

        return out
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

        // Apply halo-free unsharp mask if sharpness requested
        if (sharpness > 0.05f) {
            val amount = sharpness.coerceIn(0f, 1.0f) * 1.5f
            applyHaloFreeSharpening(outPixels, w, h, amount)
        }

        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        out.setPixels(outPixels, 0, w, 0, 0, w, h)
        return out
    }

    /**
     * Unsharp mask sharpening with threshold clamping to prevent halos,
     * edge ringing, or artificial stroke thickening.
     */
    private fun applyHaloFreeSharpening(pixels: IntArray, w: Int, h: Int, amount: Float) {
        val copy = pixels.clone()
        for (y in 1 until h - 1) {
            val row = y * w
            for (x in 1 until w - 1) {
                val idx = row + x

                // 3x3 box blur neighbor sample
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

                // Ignore micro noise (< 3.0), clamp maximum halo boost to +/- 28
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
