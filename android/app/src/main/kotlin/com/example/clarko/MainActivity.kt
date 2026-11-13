package com.example.clarko

import android.app.NotificationManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Lets the app clear a reminder that's showing once its dose is ticked
        // off in-app. The notifications plugin can only cancel a notification
        // together with its daily schedule, which is not what we want here.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "clarko/reminders")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "dismiss" -> {
                        val id = call.argument<Int>("id")
                        if (id != null) {
                            val notifications =
                                getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                            notifications?.cancel(id)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
