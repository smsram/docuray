package com.docuray.docuray.scanner

import android.content.Context
import android.graphics.*
import android.view.View
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

class DocumentOverlayView(context: Context) : View(context) {
    init {
        setWillNotDraw(false)
    }

    private val currentPoints = FloatArray(8)
    private val targetPoints = FloatArray(8)
    private var isTracking = false
    private var isReady = false
    private var captureType = "Document"
    private var alphaLevel = 0f

    // Theme Colors
    private val themeColor = Color.parseColor("#2563EB")
    private val readyColor = Color.parseColor("#10B981")

    // Diagnostic overlay
    private var showDiagnostics = false
    private var diagnosticMetrics: ProfileMetrics? = null
    private val debugTextPaint = Paint().apply {
        color = Color.WHITE
        textSize = 28f
        isAntiAlias = true
        typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
        setShadowLayer(4f, 1f, 1f, Color.BLACK)
    }
    private val debugBgPaint = Paint().apply {
        color = Color.argb(160, 0, 0, 0)
        style = Paint.Style.FILL
    }

    // Corner dot paints
    private val outerGlowPaint = Paint().apply {
        style = Paint.Style.STROKE
        strokeWidth = 3f
        isAntiAlias = true
    }

    private val dotMainPaint = Paint().apply {
        style = Paint.Style.FILL
        isAntiAlias = true
    }

    private val dotCenterPaint = Paint().apply {
        color = Color.WHITE
        style = Paint.Style.FILL
        isAntiAlias = true
    }

    // ID Card guide paints
    private val cardGuidePaint = Paint().apply {
        color = Color.parseColor("#80FFFFFF")
        style = Paint.Style.STROKE
        strokeWidth = 2.5f
        pathEffect = DashPathEffect(floatArrayOf(20f, 15f), 0f)
        isAntiAlias = true
    }

    private val cardCornerPaint = Paint().apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 4f
        isAntiAlias = true
    }

    fun setCaptureType(type: String) {
        captureType = type
        postInvalidateOnAnimation()
    }

    fun setIsReady(ready: Boolean) {
        isReady = ready
        postInvalidateOnAnimation()
    }

    fun setDiagnosticsEnabled(enabled: Boolean) {
        showDiagnostics = enabled
        postInvalidateOnAnimation()
    }

    fun updateMetrics(metrics: ProfileMetrics?) {
        diagnosticMetrics = metrics
        if (showDiagnostics) {
            postInvalidateOnAnimation()
        }
    }

    fun updatePoints(newPoints: FloatArray?) {
        if (newPoints == null || newPoints.size < 8) {
            isTracking = false
            postInvalidateOnAnimation()
            return
        }

        System.arraycopy(newPoints, 0, targetPoints, 0, 8)

        if (!isTracking) {
            System.arraycopy(newPoints, 0, currentPoints, 0, 8)
            isTracking = true
            alphaLevel = 1.0f
        }

        postInvalidateOnAnimation()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        // Draw ID Card Guide if in ID Card mode
        if (captureType.equals("ID Card", ignoreCase = true)) {
            drawIdCardGuide(canvas)
        }

        var needsAnotherFrame = false

        // Smooth alpha fade in / fade out
        if (isTracking) {
            if (alphaLevel < 1f) {
                alphaLevel = min(1f, alphaLevel + 0.15f)
                needsAnotherFrame = true
            }
        } else {
            if (alphaLevel > 0f) {
                alphaLevel = max(0f, alphaLevel - 0.20f)
                needsAnotherFrame = true
            }
        }

        if (alphaLevel > 0.02f) {
            val smoothingFactor = 0.35f

            for (i in 0 until 8) {
                val diff = targetPoints[i] - currentPoints[i]
                if (abs(diff) > 0.5f) {
                    currentPoints[i] += diff * smoothingFactor
                    needsAnotherFrame = true
                } else {
                    currentPoints[i] = targetPoints[i]
                }
            }

            val p = currentPoints
            val activeColor = if (isReady) readyColor else themeColor
            val currentAlpha = (255 * alphaLevel).toInt().coerceIn(0, 255)

            dotMainPaint.color = Color.argb(
                currentAlpha,
                Color.red(activeColor),
                Color.green(activeColor),
                Color.blue(activeColor)
            )
            outerGlowPaint.color = Color.argb(
                (80 * alphaLevel).toInt().coerceIn(0, 255),
                Color.red(activeColor),
                Color.green(activeColor),
                Color.blue(activeColor)
            )
            dotCenterPaint.color = Color.argb(currentAlpha, 255, 255, 255)

            // Draw FOUR SMOOTH CORNER DOTS
            val outerRadius = 18f
            val mainRadius = 11f
            val centerRadius = 5f

            for (i in 0 until 8 step 2) {
                val cx = p[i]
                val cy = p[i + 1]

                // 1. Outer subtle halo ring
                canvas.drawCircle(cx, cy, outerRadius, outerGlowPaint)
                // 2. Main solid colored dot
                canvas.drawCircle(cx, cy, mainRadius, dotMainPaint)
                // 3. Crisp white center dot
                canvas.drawCircle(cx, cy, centerRadius, dotCenterPaint)
            }
        }

        // Draw developer diagnostics HUD if enabled
        if (showDiagnostics) {
            val m = diagnosticMetrics
            if (m != null) {
                val postMs = m.decodeMs + m.maskMs + m.contourMs
                val line1 = "FPS: ${"%.1f".format(m.fps)} | Total: ${"%.1f".format(m.totalMs)}ms"
                val line2 = "Inf: ${"%.1f".format(m.inferenceMs)}ms | Post: ${"%.1f".format(postMs)}ms"
                val line3 = "Backend: ${m.backend} | Conf: ${(m.confidence * 100).toInt()}%"
                val line4 = "Document: ${if (m.hasDocument) "Detected (Valid Quad)" else "Searching..."}"

                val boxLeft = 20f
                val boxTop = 20f
                val boxRight = width.toFloat() - 20f
                val boxBottom = 160f

                canvas.drawRoundRect(boxLeft, boxTop, boxRight, boxBottom, 12f, 12f, debugBgPaint)
                canvas.drawText(line1, boxLeft + 16f, boxTop + 32f, debugTextPaint)
                canvas.drawText(line2, boxLeft + 16f, boxTop + 64f, debugTextPaint)
                canvas.drawText(line3, boxLeft + 16f, boxTop + 96f, debugTextPaint)
                canvas.drawText(line4, boxLeft + 16f, boxTop + 128f, debugTextPaint)
            }
        }

        if (needsAnotherFrame) {
            postInvalidateOnAnimation()
        }
    }

    private fun drawIdCardGuide(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0 || h <= 0) return

        // ID-1 standard card aspect ratio: 85.6mm / 53.98mm = 1.5858
        val cardW = min(w * 0.88f, 580f)
        val cardH = cardW / 1.5858f

        val left = (w - cardW) / 2f
        val top = (h - cardH) / 2f
        val right = left + cardW
        val bottom = top + cardH

        val cardRect = RectF(left, top, right, bottom)
        val cornerRadius = 24f

        canvas.drawRoundRect(cardRect, cornerRadius, cornerRadius, cardGuidePaint)

        val bracketLen = 32f

        // Top-Left
        canvas.drawLine(left, top + cornerRadius + bracketLen, left, top + cornerRadius, cardCornerPaint)
        canvas.drawLine(left + cornerRadius, top, left + cornerRadius + bracketLen, top, cardCornerPaint)

        // Top-Right
        canvas.drawLine(right, top + cornerRadius + bracketLen, right, top + cornerRadius, cardCornerPaint)
        canvas.drawLine(right - cornerRadius, top, right - cornerRadius - bracketLen, top, cardCornerPaint)

        // Bottom-Right
        canvas.drawLine(right, bottom - cornerRadius - bracketLen, right, bottom - cornerRadius, cardCornerPaint)
        canvas.drawLine(right - cornerRadius, bottom, right - cornerRadius - bracketLen, bottom, cardCornerPaint)

        // Bottom-Left
        canvas.drawLine(left, bottom - cornerRadius - bracketLen, left, bottom - cornerRadius, cardCornerPaint)
        canvas.drawLine(left + cornerRadius, bottom, left + cornerRadius + bracketLen, bottom, cardCornerPaint)
    }
}
