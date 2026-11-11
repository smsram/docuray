package com.docuray.docuray.scanner

import kotlin.math.hypot
import kotlin.math.max

/**
 * Multi-frame temporal prediction tracker for document corners.
 * 
 * Features:
 * 1. 5-frame rolling detection history.
 * 2. Outlier / jump rejection (suppresses transient false spikes).
 * 3. Confidence-aware adaptive exponential smoothing (alpha adapts between stationary and moving states).
 * 4. Stale corner timeout (clears overlay after 350ms of lost detection).
 * 5. Multi-frame stability verification for automatic capture (requires 4+ consecutive stable frames).
 */
class TemporalTracker {
    companion object {
        private const val HISTORY_CAPACITY = 5
        private const val MAX_JUMP_DISPLACEMENT = 0.22f // Max normalized corner displacement before outlier check
        private const val STABLE_DISPLACEMENT_TOLERANCE = 0.030f
        private const val STABLE_FRAMES_REQUIRED = 4
        private const val STALE_TIMEOUT_MS = 350L
    }

    data class DetectionRecord(
        val corners: FloatArray,
        val confidence: Float,
        val areaRatio: Float,
        val timestamp: Long
    )

    private val history = ArrayList<DetectionRecord>()
    private val smoothedCorners = FloatArray(8)
    private var hasSmoothed = false
    private var lastValidTime = 0L

    var consecutiveStableFrames = 0
        private set
    var isStableForCapture = false
        private set

    /**
     * Processes a new frame detection.
     * Returns smoothed corners if valid / stable, or null if detection lost or stale.
     */
    fun processDetection(
        rawCorners: FloatArray,
        confidence: Float,
        areaRatio: Float,
        isValid: Boolean
    ): FloatArray? {
        val now = System.currentTimeMillis()

        if (!isValid) {
            if (now - lastValidTime > STALE_TIMEOUT_MS) {
                reset()
                return null
            }
            // Keep recent smoothed corners during momentary single-frame miss to avoid flickering
            consecutiveStableFrames = 0
            isStableForCapture = false
            return if (hasSmoothed) smoothedCorners.clone() else null
        }

        lastValidTime = now

        // Outlier jump rejection
        if (hasSmoothed && history.size >= 2) {
            var maxDisplacement = 0f
            for (i in 0 until 4) {
                val dx = rawCorners[i * 2] - smoothedCorners[i * 2]
                val dy = rawCorners[i * 2 + 1] - smoothedCorners[i * 2 + 1]
                val dist = hypot(dx, dy)
                if (dist > maxDisplacement) maxDisplacement = dist
            }

            val avgHistoryConf = history.map { it.confidence }.average().toFloat()
            if (maxDisplacement > MAX_JUMP_DISPLACEMENT && confidence < avgHistoryConf) {
                // Reject transient outlier spike
                consecutiveStableFrames = 0
                isStableForCapture = false
                return smoothedCorners.clone()
            }
        }

        // Add to history
        if (history.size >= HISTORY_CAPACITY) {
            history.removeAt(0)
        }
        history.add(DetectionRecord(rawCorners.clone(), confidence, areaRatio, now))

        // Adaptive confidence-weighted temporal smoothing
        if (!hasSmoothed) {
            System.arraycopy(rawCorners, 0, smoothedCorners, 0, 8)
            hasSmoothed = true
            consecutiveStableFrames = 1
        } else {
            var displacement = 0f
            for (i in 0 until 4) {
                val dx = rawCorners[i * 2] - smoothedCorners[i * 2]
                val dy = rawCorners[i * 2 + 1] - smoothedCorners[i * 2 + 1]
                displacement = max(displacement, hypot(dx, dy))
            }

            val alpha = when {
                displacement > 0.08f -> 0.65f // Responsive tracking for moving documents
                displacement < 0.015f -> 0.25f // Rock solid stationary stabilization
                else -> 0.45f + (confidence - 0.5f) * 0.2f
            }.coerceIn(0.20f, 0.75f)

            for (i in 0 until 8) {
                smoothedCorners[i] = alpha * rawCorners[i] + (1f - alpha) * smoothedCorners[i]
            }

            // Stability check for automatic capture
            if (displacement < STABLE_DISPLACEMENT_TOLERANCE && confidence >= 0.70f) {
                consecutiveStableFrames++
                if (consecutiveStableFrames >= STABLE_FRAMES_REQUIRED) {
                    isStableForCapture = true
                }
            } else {
                consecutiveStableFrames = 0
                isStableForCapture = false
            }
        }

        return smoothedCorners.clone()
    }

    fun reset() {
        history.clear()
        hasSmoothed = false
        smoothedCorners.fill(0f)
        consecutiveStableFrames = 0
        isStableForCapture = false
        lastValidTime = 0L
    }
}

