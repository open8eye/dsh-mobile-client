package com.dshmobile.dsh_mobile_client

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Draws the companion over whatever the user is doing.
 *
 * A companion that floats over the launcher cannot live in the Flutter view
 * hierarchy: it needs its own window of type `TYPE_APPLICATION_OVERLAY`, which
 * only a service holding `SYSTEM_ALERT_WINDOW` may add. The service therefore
 * owns the window and Flutter only tells it when to appear.
 */
class PetOverlayService : Service() {

    private var windowManager: WindowManager? = null
    private var companionView: CompanionView? = null
    private var layoutParams: WindowManager.LayoutParams? = null

    /** Window sizes are expressed in dp; the window manager wants pixels. */
    private val density: Float get() = resources.displayMetrics.density

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_HIDE) {
            removeCompanion()
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }

        // A foreground service is mandatory for a persistent overlay on modern
        // Android; without it the window is torn down as soon as the app leaves
        // the foreground.
        startForegroundCompat()
        showCompanion(
            scale = intent?.getFloatExtra(EXTRA_SCALE, 1f) ?: 1f,
            opacity = intent?.getFloatExtra(EXTRA_OPACITY, 1f) ?: 1f,
            imagePath = intent?.getStringExtra(EXTRA_IMAGE_PATH),
        )
        return START_STICKY
    }

    override fun onDestroy() {
        removeCompanion()
        super.onDestroy()
    }

    private fun showCompanion(scale: Float, opacity: Float, imagePath: String?) {
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }
        val manager = windowManager ?: return
        val size = (BASE_SIZE_DP * density * scale).roundToInt().coerceAtLeast(1)

        val view = companionView ?: CompanionView(this).also { created ->
            created.setOnTouchListener(DragListener())
            created.setOnClickListener { openApp() }
            companionView = created
        }
        view.setCharacter(imagePath)
        view.alpha = opacity.coerceIn(0.1f, 1f)

        val params = layoutParams ?: WindowManager.LayoutParams(
            size,
            size,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).also { created ->
            created.gravity = Gravity.TOP or Gravity.START
            created.x = (24 * density).roundToInt()
            created.y = (160 * density).roundToInt()
            layoutParams = created
        }
        params.width = size
        params.height = size

        if (view.parent == null) {
            runCatching { manager.addView(view, params) }.onFailure { stopSelf() }
        } else {
            runCatching { manager.updateViewLayout(view, params) }
        }
        isRunning = true
    }

    private fun removeCompanion() {
        val view = companionView
        val manager = windowManager
        if (view != null && manager != null) {
            runCatching { manager.removeView(view) }
        }
        companionView = null
        layoutParams = null
        isRunning = false
    }

    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(intent)
    }

    private fun startForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.pet_channel_name),
                NotificationManager.IMPORTANCE_MIN,
            ).apply { description = getString(R.string.pet_channel_description) }
            manager?.createNotificationChannel(channel)
        }

        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // The channel constructor only exists from API 26; minSdk is 24.
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_MIN)
        }
        return builder
            .setContentTitle(getString(R.string.pet_notification_title))
            .setContentText(getString(R.string.pet_notification_text))
            .setSmallIcon(R.drawable.ic_stat_companion)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .build()
    }

    private fun stopForegroundCompat() {
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    /** Drag the companion around, and treat a near-still gesture as a tap. */
    private inner class DragListener : View.OnTouchListener {
        private var initialX = 0
        private var initialY = 0
        private var touchX = 0f
        private var touchY = 0f
        private var moved = false

        override fun onTouch(view: View, event: MotionEvent): Boolean {
            val params = layoutParams ?: return false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    moved = false
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - touchX
                    val dy = event.rawY - touchY
                    if (abs(dx) > TAP_SLOP || abs(dy) > TAP_SLOP) moved = true
                    params.x = initialX + dx.roundToInt()
                    params.y = initialY + dy.roundToInt()
                    windowManager?.let { manager ->
                        runCatching { manager.updateViewLayout(view, params) }
                    }
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) view.performClick()
                    return true
                }
            }
            return false
        }
    }

    companion object {
        const val ACTION_SHOW = "com.dshmobile.dsh_mobile_client.action.SHOW_PET"
        const val ACTION_HIDE = "com.dshmobile.dsh_mobile_client.action.HIDE_PET"
        const val EXTRA_SCALE = "scale"
        const val EXTRA_OPACITY = "opacity"
        const val EXTRA_IMAGE_PATH = "imagePath"

        private const val CHANNEL_ID = "dsh_companion"
        private const val NOTIFICATION_ID = 4711
        private const val BASE_SIZE_DP = 120f
        private const val TAP_SLOP = 12f

        /** Whether a companion window is currently attached. */
        @Volatile
        var isRunning: Boolean = false
            private set
    }
}
