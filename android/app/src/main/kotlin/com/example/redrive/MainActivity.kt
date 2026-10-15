package com.example.redrive

import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleSilentStart(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleSilentStart(intent)
    }

    private fun handleSilentStart(intent: Intent?) {
        if (intent?.getBooleanExtra("silent_start", false) == true) {
            Log.i(TAG, "ReDrive started silently from ignition wake; moving task to back")
            moveTaskToBack(true)
            try {
                @Suppress("DEPRECATION")
                overridePendingTransition(0, 0)
            } catch (_: Exception) {}
        }
    }
}
