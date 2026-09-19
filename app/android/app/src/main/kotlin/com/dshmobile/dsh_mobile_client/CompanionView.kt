package com.dshmobile.dsh_mobile_client

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.View
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * The floating companion.
 *
 * Mirrors `CompanionPainter` in the Flutter app so the in-app preview matches
 * what floats over the launcher. A user-supplied image replaces the drawn
 * character, keeping the same bob and shadow so a still picture still feels
 * alive.
 *
 * Swapping this for a Live2D or sprite-sheet character later means replacing
 * [onDraw] only — the service, permissions and channel stay as they are.
 */
class CompanionView(context: Context) : View(context) {

    private val bodyPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val accentPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val eyePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val blushPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        color = Color.WHITE
    }

    private var character: Bitmap? = null

    init {
        bodyPaint.color = Color.parseColor("#4D6BFE")
        accentPaint.color = Color.parseColor("#C9D4FF")
        eyePaint.color = Color.WHITE
        blushPaint.color = Color.parseColor("#FFD9E2")
        shadowPaint.color = Color.parseColor("#1F000000")
    }

    /** Load a user-chosen character image; `null` restores the built-in one. */
    fun setCharacter(path: String?) {
        character = if (path.isNullOrEmpty()) {
            null
        } else {
            runCatching { BitmapFactory.decodeFile(path) }.getOrNull()
        }
        invalidate()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        // Drive the idle animation from the vsync signal rather than a Timer so
        // it stops automatically when the window is not visible.
        postInvalidateOnAnimation()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val width = width.toFloat()
        val height = height.toFloat()
        if (width <= 0f || height <= 0f) return

        val phase = (System.currentTimeMillis() % ANIMATION_PERIOD_MS) / ANIMATION_PERIOD_MS.toFloat()
        val bob = sin(phase * 2 * Math.PI).toFloat() * height * 0.035f

        val image = character
        if (image != null) {
            drawCharacterImage(canvas, image, width, height, bob)
        } else {
            drawBuiltInCharacter(canvas, width, height, bob, phase)
        }

        postInvalidateOnAnimation()
    }

    private fun drawCharacterImage(canvas: Canvas, image: Bitmap, width: Float, height: Float, bob: Float) {
        val box = min(width, height) * 0.86f
        val scale = min(box / image.width, box / image.height)
        val drawWidth = image.width * scale
        val drawHeight = image.height * scale
        val left = (width - drawWidth) / 2f
        val top = (height - drawHeight) / 2f + bob
        canvas.drawBitmap(image, null, RectF(left, top, left + drawWidth, top + drawHeight), null)
    }

    private fun drawBuiltInCharacter(canvas: Canvas, width: Float, height: Float, bob: Float, phase: Float) {
        val bodyWidth = width * 0.62f
        val bodyHeight = height * 0.56f
        val centerX = width / 2f
        val centerY = height * 0.52f + bob

        // Blink twice per animation cycle.
        val blinkPhase = (phase * 2f) % 1f
        val blink = if (blinkPhase > 0.86f) 0.12f else 1f

        val shadowWidth = bodyWidth * (0.92f - bob / height * 2f)
        canvas.drawOval(
            RectF(
                centerX - shadowWidth / 2f,
                height * 0.83f,
                centerX + shadowWidth / 2f,
                height * 0.89f,
            ),
            shadowPaint,
        )

        // Ears behind the body.
        for (sign in intArrayOf(-1, 1)) {
            val earCenterX = centerX + sign * bodyWidth * 0.30f
            val earCenterY = centerY - bodyHeight * 0.38f
            canvas.drawOval(
                RectF(
                    earCenterX - bodyWidth * 0.13f,
                    earCenterY - bodyHeight * 0.18f,
                    earCenterX + bodyWidth * 0.13f,
                    earCenterY + bodyHeight * 0.18f,
                ),
                accentPaint,
            )
        }

        val bodyRect = RectF(
            centerX - bodyWidth / 2f,
            centerY - bodyHeight / 2f,
            centerX + bodyWidth / 2f,
            centerY + bodyHeight / 2f,
        )
        canvas.drawRoundRect(bodyRect, bodyWidth * 0.45f, bodyWidth * 0.45f, bodyPaint)

        // Belly patch.
        canvas.drawOval(
            RectF(
                centerX - bodyWidth * 0.25f,
                centerY + bodyHeight * 0.16f - bodyHeight * 0.21f,
                centerX + bodyWidth * 0.25f,
                centerY + bodyHeight * 0.16f + bodyHeight * 0.21f,
            ),
            Paint(Paint.ANTI_ALIAS_FLAG).apply { color = accentPaint.color; alpha = 140 },
        )

        // Blush.
        for (sign in intArrayOf(-1, 1)) {
            val blushX = centerX + sign * bodyWidth * 0.28f
            val blushY = centerY + bodyHeight * 0.06f
            canvas.drawOval(
                RectF(
                    blushX - bodyWidth * 0.08f,
                    blushY - bodyHeight * 0.055f,
                    blushX + bodyWidth * 0.08f,
                    blushY + bodyHeight * 0.055f,
                ),
                blushPaint,
            )
        }

        // Eyes.
        for (sign in intArrayOf(-1, 1)) {
            val eyeX = centerX + sign * bodyWidth * 0.17f
            val eyeY = centerY - bodyHeight * 0.05f
            canvas.drawOval(
                RectF(
                    eyeX - bodyWidth * 0.05f,
                    eyeY - bodyHeight * 0.09f * blink,
                    eyeX + bodyWidth * 0.05f,
                    eyeY + bodyHeight * 0.09f * blink,
                ),
                eyePaint,
            )
        }

        // Smile, only while the eyes are open.
        if (blink > 0.5f) {
            strokePaint.strokeWidth = max(1.6f, width * 0.018f)
            val path = Path().apply {
                moveTo(centerX - bodyWidth * 0.07f, centerY + bodyHeight * 0.20f)
                quadTo(
                    centerX,
                    centerY + bodyHeight * 0.30f,
                    centerX + bodyWidth * 0.07f,
                    centerY + bodyHeight * 0.20f,
                )
            }
            canvas.drawPath(path, strokePaint)
        }
    }

    private companion object {
        const val ANIMATION_PERIOD_MS = 2600L
    }
}
