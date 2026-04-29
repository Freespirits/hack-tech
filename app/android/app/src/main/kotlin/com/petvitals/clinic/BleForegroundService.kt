package com.petvitals.clinic

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground service that holds the Android process alive while a BLE
 * monitoring session is active.
 *
 * This is the single biggest stability gain over the stock Berry Pet
 * Health app: when the screen sleeps, Android's Doze mode aggressively
 * suspends background BLE callbacks. Without a foreground service the
 * notify stream silently halts and reconnect logic on the Dart side
 * never fires. With a `connectedDevice` foreground service running,
 * the OS keeps our process scheduled and BLE callbacks continue.
 */
class BleForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "petvitals_monitoring"
        const val NOTIFICATION_ID = 1042

        fun start(context: Context, petName: String) {
            val intent = Intent(context, BleForegroundService::class.java)
            intent.putExtra("pet_name", petName)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, BleForegroundService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel()
        val petName = intent?.getStringExtra("pet_name") ?: "patient"
        val notification = buildNotification(petName)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Live monitoring",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Active veterinary monitoring sessions."
                    setShowBadge(false)
                }
                mgr.createNotificationChannel(channel)
            }
        }
    }

    private fun buildNotification(petName: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pi = launchIntent?.let {
            PendingIntent.getActivity(
                this, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Monitoring $petName")
            .setContentText("Streaming vitals from AM4100 device")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setOngoing(true)
            .setContentIntent(pi)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }
}
