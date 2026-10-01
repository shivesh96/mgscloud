package com.cybolite.msgserver.msg_to_server

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import androidx.annotation.Keep
import io.flutter.app.FlutterApplication

@Keep
class MsgToServerApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "msg_to_server_channel",
                "Message Cloud Background Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps message monitoring active in background"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }
}
