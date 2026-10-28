package com.eatwise.eatwise

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

// Health Connect requires a ComponentActivity.
class MainActivity : FlutterFragmentActivity() {
    private var timezoneChannel: MethodChannel? = null
    private var timezoneReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        timezoneChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "eatwise/system_timezone").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "getIdentifier") result.success(TimeZone.getDefault().id)
                else result.notImplemented()
            }
        }
        timezoneReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_TIMEZONE_CHANGED) {
                    timezoneChannel?.invokeMethod("timezoneChanged", null)
                }
            }
        }.also { receiver ->
            val filter = IntentFilter(Intent.ACTION_TIMEZONE_CHANGED)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(receiver, filter)
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        timezoneReceiver?.let { unregisterReceiver(it) }
        timezoneReceiver = null
        timezoneChannel?.setMethodCallHandler(null)
        timezoneChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
