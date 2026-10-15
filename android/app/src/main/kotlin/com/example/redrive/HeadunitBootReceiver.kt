package com.example.redrive

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat
import id.flutter.flutter_background_service.BackgroundService
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * BroadcastReceiver designed for automotive Android Headunits (FYT, MTCD/E, Topway, Allwinner).
 * Catches cold boot, fast boot (ACC wake-up), and screen wake events to guarantee
 * ReDrive starts collecting telemetry immediately and brings the dashboard onto the screen.
 */
class HeadunitBootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "HeadunitBootReceiver"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_AUTO_LAUNCH = "flutter.auto_launch_on_boot"
        private const val KEY_LAST_ACTION = "flutter.last_boot_action"
        private const val KEY_LAST_TIMESTAMP = "flutter.last_boot_timestamp"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        Log.i(TAG, "Vehicle intent received: $action")

        val sdf = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
        val now = sdf.format(Date())

        // 1. Record boot event info to SharedPreferences for in-app diagnostics
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .putString(KEY_LAST_ACTION, action)
                .putString(KEY_LAST_TIMESTAMP, now)
                .apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to persist boot event in preferences", e)
        }

        // 2. Append directly to redrive_debug.log so it appears in the in-app Log Viewer
        try {
            val dataDir = context.applicationInfo.dataDir
            val flutterDir = File(dataDir, "app_flutter")
            if (!flutterDir.exists()) flutterDir.mkdirs()
            val logFile = File(flutterDir, "redrive_debug.log")
            logFile.appendText("$now.000 [INFO] [HeadunitBootReceiver] Vehicle intent received: $action\n")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to append boot event to log file", e)
        }

        val isSleepEvent = action.endsWith("ACC_OFF", ignoreCase = true) ||
                action == Intent.ACTION_POWER_DISCONNECTED

        if (isSleepEvent) {
            Log.i(TAG, "Ignition / power OFF detected on headunit. Preparing for sleep.")
            return
        }

        // For Bluetooth state changes, only trigger when turning ON
        if (action == "android.bluetooth.adapter.action.STATE_CHANGED") {
            val state = intent.getIntExtra("android.bluetooth.adapter.extra.STATE", -1)
            // 12 is BluetoothAdapter.STATE_ON
            if (state != 12) {
                return
            }
        }

        // 3. Start foreground service (ensures persistence and wake lock in background)
        try {
            val serviceIntent = Intent(context, BackgroundService::class.java)
            ContextCompat.startForegroundService(context, serviceIntent)
            Log.i(TAG, "ReDrive BackgroundService started from headunit wake event ($action)")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting background service on headunit wake", e)
        }

        // 4. Direct Auto-Launch: Bring ReDrive UI onto the headunit screen upon ignition
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val shouldAutoLaunch = prefs.getBoolean(KEY_AUTO_LAUNCH, true)

            if (shouldAutoLaunch) {
                val activityIntent = Intent(context, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                }
                context.startActivity(activityIntent)
                Log.i(TAG, "ReDrive MainActivity launched on headunit display from wake event ($action)")
            } else {
                Log.i(TAG, "Auto-launch on ignition is disabled by user configuration")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error launching MainActivity on headunit wake", e)
        }
    }
}

