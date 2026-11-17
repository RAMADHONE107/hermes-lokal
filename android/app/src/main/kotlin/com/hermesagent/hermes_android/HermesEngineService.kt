package com.hermesagent.hermes_android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder

/** Foreground wrapper that keeps the embedded gateway alive while it runs. */
class HermesEngineService : Service() {
    companion object {
        private const val CHANNEL_ID = "hermes_engine"
        private const val NOTIFICATION_ID = 8642
        const val ACTION_STOP = "com.hermesagent.hermes_android.hermes_engine.STOP"
    }

    private val controller by lazy { HermesEngineController.instance() }
    private val listener: (HermesEngineController.Status) -> Unit = { status ->
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(status))
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startForeground(NOTIFICATION_ID, buildNotification(controller.currentStatus()))
        controller.addListener(listener)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            controller.stopForNotification()
            stopSelf()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        controller.removeListener(listener)
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Hermes Lokal",
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.description = "Mesin Hermes yang berjalan di perangkat"
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(status: HermesEngineController.Status): Notification {
        val stopIntent = Intent(this, HermesEngineService::class.java).apply { action = ACTION_STOP }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val stop = PendingIntent.getService(this, 1, stopIntent, flags)
        val title = "Hermes Lokal"
        val text = when (status.state) {
            HermesEngineController.State.RUNNING -> "Mesin berjalan · 127.0.0.1:8642"
            HermesEngineController.State.ERROR -> status.message.ifBlank { "Mesin error" }
            else -> status.message.ifBlank { "Menyiapkan mesin" }
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.drawable.ic_stat_mobile_push)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(status.state == HermesEngineController.State.RUNNING)
            .setOnlyAlertOnce(true)
            .addAction(android.R.drawable.ic_media_pause, "Setop", stop)
            .setContentIntent(stop)
            .build()
    }
}
