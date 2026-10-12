package com.example.redrive

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat
import id.flutter.flutter_background_service.BackgroundService

/**
 * BroadcastReceiver designed for automotive Android Headunits (FYT, MTCD/E, Topway, Allwinner).
 * Catches cold boot, fast boot (ACC wake-up), and screen wake events to guarantee
 * ReDrive starts collecting telemetry immediately without requiring manual app launch.
 */
class HeadunitBootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "HeadunitBootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        Log.i(TAG, "Vehicle intent received: $action")

        val isSleepEvent = action.endsWith("ACC_OFF", ignoreCase = true) ||
                action == Intent.ACTION_POWER_DISCONNECTED

        if (isSleepEvent) {
            Log.i(TAG, "Ignition / power OFF detected on headunit. Preparing for sleep.")
            // On sleep, background service and connections can finalize gracefully
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

        // 1. Start foreground service
        try {
            val serviceIntent = Intent(context, BackgroundService::class.java)
            ContextCompat.startForegroundService(context, serviceIntent)
            Log.i(TAG, "ReDrive BackgroundService started from headunit wake event")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting background service on headunit wake", e)
        }

        // 2. Launch ReDrive UI Activity so headunit displays the dashboard
        try {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            if (launchIntent != null) {
                context.startActivity(launchIntent)
                Log.i(TAG, "ReDrive MainActivity successfully launched from headunit wake event")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error launching MainActivity on headunit wake", e)
        }
    }
}
