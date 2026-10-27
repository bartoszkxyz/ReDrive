package com.example.obdrive

import android.app.ActivityManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.util.DisplayMetrics
import android.util.Log
import android.view.InputDevice
import android.view.WindowManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val STORAGE_CHANNEL = "com.example.obdrive/storage"
        private const val GPS_CHANNEL = "com.example.obdrive/gps_stream"
    }

    private var isDvrStarted: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, GPS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                private var locationListener: LocationListener? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (events == null) return
                    val locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                    if (locationManager == null) {
                        Log.w(TAG, "LocationManager not available")
                        return
                    }

                    val hasFine = checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                    val hasCoarse = checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

                    if (!hasFine && !hasCoarse) {
                        Log.w(TAG, "Location permissions not granted for gps_stream")
                        return
                    }

                    val listener = object : LocationListener {
                        override fun onLocationChanged(loc: Location) {
                            val map = HashMap<String, Any>()
                            map["latitude"] = loc.latitude
                            map["longitude"] = loc.longitude
                            map["speedKmh"] = loc.speed * 3.6
                            map["headingDeg"] = loc.bearing.toDouble()
                            map["altitudeMeters"] = loc.altitude
                            map["accuracyMeters"] = loc.accuracy.toDouble()
                            map["timestampMs"] = loc.time
                            runOnUiThread {
                                try {
                                    events.success(map)
                                } catch (_: Exception) {}
                            }
                        }

                        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                        override fun onProviderEnabled(provider: String) {}
                        override fun onProviderDisabled(provider: String) {}
                    }
                    locationListener = listener

                    try {
                        if (hasFine && locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                            locationManager.requestLocationUpdates(
                                LocationManager.GPS_PROVIDER,
                                1000L,
                                0f,
                                listener
                            )
                        } else if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                            locationManager.requestLocationUpdates(
                                LocationManager.NETWORK_PROVIDER,
                                1000L,
                                0f,
                                listener
                            )
                        }
                    } catch (e: SecurityException) {
                        Log.w(TAG, "SecurityException requesting location updates", e)
                    } catch (e: Exception) {
                        Log.w(TAG, "Exception requesting location updates", e)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    locationListener?.let { listener ->
                        val locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                        try {
                            locationManager?.removeUpdates(listener)
                        } catch (_: Exception) {}
                    }
                    locationListener = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveExportFile" -> {
                        val fileName = call.argument<String>("fileName")
                        val content = call.argument<String>("content")
                        val mimeType = call.argument<String>("mimeType") ?: "text/plain"
                        if (fileName.isNullOrBlank() || content == null) {
                            result.error("INVALID_ARGS", "fileName and content are required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val savedPath = saveToExternalStorage(fileName, content, mimeType)
                            result.success(savedPath)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to save export file $fileName", e)
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }

                    "dumpHeadunitProfile" -> {
                        val flutterMetrics = call.argument<Map<String, Any?>>("flutterMetrics") ?: emptyMap()
                        Thread {
                            try {
                                val dumpResult = buildAndSaveHeadunitDump(flutterMetrics)
                                runOnUiThread {
                                    result.success(dumpResult)
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Failed to dump headunit profile", e)
                                runOnUiThread {
                                    result.error("DUMP_FAILED", e.message, null)
                                }
                            }
                        }.start()
                    }

                    "launchApp" -> {
                        val packageName = call.argument<String>("packageName")
                        val activityName = call.argument<String>("activityName")
                        if (packageName.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "packageName is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val success = launchApplication(packageName, activityName)
                            result.success(success)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to launch $packageName", e)
                            result.error("LAUNCH_FAILED", e.message, null)
                        }
                    }

                    "getInstalledApps" -> {
                        Thread {
                            try {
                                val apps = queryLaunchableApplications()
                                runOnUiThread {
                                    result.success(apps)
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Failed to query launchable apps", e)
                                runOnUiThread {
                                    result.error("QUERY_FAILED", e.message, null)
                                }
                            }
                        }.start()
                    }

                    "startDvrService" -> {
                        try {
                            val success = startDvrBackgroundService()
                            result.success(success)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to start DVR background service", e)
                            result.error("DVR_START_FAILED", e.message, null)
                        }
                    }

                    "isDvrRunning" -> {
                        try {
                            val running = isDvrServiceRunning()
                            result.success(running)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }

                    "setPipWindow" -> {
                        val packageName = call.argument<String>("packageName")
                        val activityName = call.argument<String>("activityName")
                        if (packageName.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "packageName is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            // Launch target application safely without blocking the UI thread or setting hazardous properties
                            val launched = launchApplication(packageName, activityName)
                            result.success(launched)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to launch app $packageName", e)
                            result.error("PIP_FAILED", e.message, null)
                        }
                    }

                    "releasePipWindow" -> {
                        result.success(true)
                    }

                    "getAudioState" -> {
                        try {
                            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            val current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                            val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            val isMuted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                audioManager.isStreamMute(AudioManager.STREAM_MUSIC)
                            } else {
                                current == 0
                            }
                            result.success(
                                mapOf(
                                    "volume" to current,
                                    "maxVolume" to max,
                                    "isMuted" to isMuted,
                                    "isMusicActive" to audioManager.isMusicActive
                                )
                            )
                        } catch (e: Exception) {
                            result.error("AUDIO_ERROR", e.message, null)
                        }
                    }

                    "setVolume" -> {
                        val volume = call.argument<Int>("volume")
                        if (volume != null) {
                            try {
                                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                                val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                                val clamped = volume.coerceIn(0, max)
                                audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, clamped, 0)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("AUDIO_ERROR", e.message, null)
                            }
                        } else {
                            result.error("INVALID_ARGS", "volume is required", null)
                        }
                    }

                    "adjustVolume" -> {
                        val direction = call.argument<Int>("direction") ?: 0 // 1 = up, -1 = down
                        try {
                            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            val adj = if (direction > 0) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER
                            audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, adj, 0)
                            val current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                            val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            result.success(mapOf("volume" to current, "maxVolume" to max))
                        } catch (e: Exception) {
                            result.error("AUDIO_ERROR", e.message, null)
                        }
                    }

                    "sendMediaKey" -> {
                        val keyCode = call.argument<Int>("keyCode")
                        if (keyCode != null) {
                            try {
                                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                                val down = android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, keyCode)
                                val up = android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, keyCode)
                                audioManager.dispatchMediaKeyEvent(down)
                                audioManager.dispatchMediaKeyEvent(up)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("MEDIA_KEY_ERROR", e.message, null)
                            }
                        } else {
                            result.error("INVALID_ARGS", "keyCode is required", null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun launchApplication(packageName: String, activityName: String?): Boolean {
        val pm = packageManager
        val intent = if (!activityName.isNullOrBlank()) {
            Intent(Intent.ACTION_MAIN).apply {
                setClassName(packageName, activityName)
                addCategory(Intent.CATEGORY_LAUNCHER)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            }
        } else {
            pm.getLaunchIntentForPackage(packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            }
        }

        if (intent != null) {
            startActivity(intent)
            if (packageName == "com.ankai.cardvr") {
                isDvrStarted = true
            }
            return true
        }
        return false
    }

    private fun queryLaunchableApplications(): List<Map<String, Any?>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolveInfos = pm.queryIntentActivities(intent, 0)
        val result = mutableListOf<Map<String, Any?>>()
        val currentPkg = packageName

        for (info in resolveInfos) {
            val pkg = info.activityInfo.packageName
            if (pkg == currentPkg) continue
            val label = info.loadLabel(pm)?.toString() ?: pkg
            val act = info.activityInfo.name
            result.add(
                mapOf(
                    "packageName" to pkg,
                    "activityName" to act,
                    "label" to label
                )
            )
        }
        result.sortBy { it["label"] as? String ?: "" }
        return result
    }

    private fun startDvrBackgroundService(): Boolean {
        val candidates = listOf(
            Pair("com.ankai.cardvr", "com.ankai.cardvr.MainService"),
            Pair("com.ankai.cardvr", "git.my.camera.core.MobileCameraService"),
            Pair("com.ankai.cardvr", "git.my.adas.service.AdasService")
        )

        var started = false
        for ((pkg, srvName) in candidates) {
            try {
                val intent = Intent().apply {
                    setClassName(pkg, srvName)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    try {
                        startForegroundService(intent)
                        started = true
                        Log.i(TAG, "Started DVR foreground service $srvName")
                    } catch (e: Exception) {
                        val comp = startService(intent)
                        if (comp != null) {
                            started = true
                        }
                        Log.i(TAG, "Started DVR service $srvName (standard)")
                    }
                } else {
                    val comp = startService(intent)
                    if (comp != null) {
                        started = true
                    }
                    Log.i(TAG, "Started DVR service $srvName")
                }
            } catch (e: Exception) {
                Log.w(TAG, "Could not start service $srvName: ${e.message}")
            }
        }
        if (started) {
            isDvrStarted = true
        }
        return started
    }

    private fun isDvrServiceRunning(): Boolean {
        if (isDvrStarted) {
            return true
        }
        val am = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return false
        val running = am.getRunningServices(Int.MAX_VALUE)
        for (info in running) {
            val pkg = info.service.packageName
            if (pkg == "com.ankai.cardvr") {
                return true
            }
        }
        return false
    }

    private fun buildAndSaveHeadunitDump(flutterMetrics: Map<String, Any?>): Map<String, Any?> {
        val root = JSONObject()
        val now = Date()
        val isoFmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US)
        val fileFmt = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US)
        root.put("timestamp", isoFmt.format(now))
        root.put("flutterMetrics", JSONObject(flutterMetrics))

        // 1. Native Android Display & Window Metrics
        val displayJson = JSONObject()
        try {
            val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            @Suppress("DEPRECATION")
            val display = wm.defaultDisplay
            val dm = DisplayMetrics()
            val realDm = DisplayMetrics()
            @Suppress("DEPRECATION")
            display.getMetrics(dm)
            @Suppress("DEPRECATION")
            display.getRealMetrics(realDm)
            displayJson.put("widthPixels", dm.widthPixels)
            displayJson.put("heightPixels", dm.heightPixels)
            displayJson.put("realWidthPixels", realDm.widthPixels)
            displayJson.put("realHeightPixels", realDm.heightPixels)
            displayJson.put("density", dm.density.toDouble())
            displayJson.put("densityDpi", dm.densityDpi)
            displayJson.put("xdpi", dm.xdpi.toDouble())
            displayJson.put("ydpi", dm.ydpi.toDouble())
            displayJson.put("logicalWidthDp", (realDm.widthPixels / dm.density).toDouble())
            displayJson.put("logicalHeightDp", (realDm.heightPixels / dm.density).toDouble())
            @Suppress("DEPRECATION")
            displayJson.put("refreshRate", display.refreshRate.toDouble())
            @Suppress("DEPRECATION")
            displayJson.put("rotation", display.rotation)
        } catch (e: Exception) {
            displayJson.put("error", e.message)
        }
        root.put("androidDisplayMetrics", displayJson)

        // 2. Build, SoC, CPU & Memory Info (detects spoofed Android versions on TS18 knockoffs)
        val buildJson = JSONObject()
        buildJson.put("sdkInt", Build.VERSION.SDK_INT)
        buildJson.put("release", Build.VERSION.RELEASE)
        buildJson.put("codename", Build.VERSION.CODENAME)
        buildJson.put("incremental", Build.VERSION.INCREMENTAL)
        buildJson.put("securityPatch", if (Build.VERSION.SDK_INT >= 23) Build.VERSION.SECURITY_PATCH else "")
        buildJson.put("manufacturer", Build.MANUFACTURER)
        buildJson.put("brand", Build.BRAND)
        buildJson.put("model", Build.MODEL)
        buildJson.put("device", Build.DEVICE)
        buildJson.put("product", Build.PRODUCT)
        buildJson.put("hardware", Build.HARDWARE)
        buildJson.put("board", Build.BOARD)
        buildJson.put("display", Build.DISPLAY)
        buildJson.put("fingerprint", Build.FINGERPRINT)
        buildJson.put("bootloader", Build.BOOTLOADER)
        buildJson.put("supportedAbis", JSONArray(Build.SUPPORTED_ABIS.toList()))
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memInfo = ActivityManager.MemoryInfo()
            am.getMemoryInfo(memInfo)
            buildJson.put("totalRamMb", memInfo.totalMem / (1024 * 1024))
            buildJson.put("availRamMb", memInfo.availMem / (1024 * 1024))
            buildJson.put("lowMemory", memInfo.lowMemory)
        } catch (_: Exception) {}
        try {
            val cpuFile = File("/proc/cpuinfo")
            if (cpuFile.exists() && cpuFile.canRead()) {
                val lines = cpuFile.readLines().take(60)
                buildJson.put("cpuInfoHead", JSONArray(lines))
            }
        } catch (_: Exception) {}
        root.put("buildAndHardware", buildJson)

        val pm = packageManager

        // 3. Home Launchers & Default Home Resolution
        val homeJson = JSONObject()
        try {
            val homeIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            val defaultHome = pm.resolveActivity(homeIntent, PackageManager.MATCH_DEFAULT_ONLY)
            if (defaultHome?.activityInfo != null) {
                homeJson.put("currentDefaultHomePackage", defaultHome.activityInfo.packageName)
                homeJson.put("currentDefaultHomeActivity", defaultHome.activityInfo.name)
            }
            val allHomes = pm.queryIntentActivities(homeIntent, PackageManager.MATCH_ALL)
            val homeList = JSONArray()
            for (ri in allHomes) {
                val ai = ri.activityInfo ?: continue
                val obj = JSONObject()
                obj.put("packageName", ai.packageName)
                obj.put("activityName", ai.name)
                obj.put("label", try { ri.loadLabel(pm).toString() } catch (_: Exception) { ai.name })
                homeList.put(obj)
            }
            homeJson.put("installedHomeLaunchers", homeList)

            val homeSettingsIntent = Intent(Settings.ACTION_HOME_SETTINGS)
            val homeSettingsResolved = pm.resolveActivity(homeSettingsIntent, PackageManager.MATCH_DEFAULT_ONLY)
            homeJson.put("supportsActionHomeSettings", homeSettingsResolved != null)
            homeJson.put("supportsAppWidgets", packageManager.hasSystemFeature(PackageManager.FEATURE_APP_WIDGETS))
        } catch (e: Exception) {
            homeJson.put("error", e.message)
        }
        root.put("homeLauncherInfo", homeJson)

        // 4. All Standard Launchable Apps (App Drawer icons: ACTION_MAIN + CATEGORY_LAUNCHER)
        val launchableArray = JSONArray()
        try {
            val mainIntent = Intent(Intent.ACTION_MAIN, null).addCategory(Intent.CATEGORY_LAUNCHER)
            val resolvedList = pm.queryIntentActivities(mainIntent, 0)
            for (ri in resolvedList) {
                val ai = ri.activityInfo ?: continue
                val isSystem = (ai.applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                val isUpdatedSystem = (ai.applicationInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
                val obj = JSONObject()
                obj.put("packageName", ai.packageName)
                obj.put("activityName", ai.name)
                obj.put("label", try { ri.loadLabel(pm).toString() } catch (_: Exception) { ai.packageName })
                obj.put("isSystemApp", isSystem || isUpdatedSystem)
                obj.put("sourceDir", ai.applicationInfo.sourceDir ?: "")
                launchableArray.put(obj)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error querying launchable apps", e)
        }
        root.put("launchableApps", launchableArray)

        // 5. All Installed Packages + Deep Inspection of Vendor / Headunit / Monolithic Packages (e.g. com.ts.MainUI)
        val allPackagesSummary = JSONArray()
        val deepVendorPackages = JSONArray()
        val vendorKeywords = listOf(
            "ts", "topway", "mainui", "syu", "fyt", "xy", "autochips", "atc",
            "microntek", "mtc", "hct", "forfan", "junsun", "ankai", "allwinner",
            "rockchip", "sprd", "unisoc", "mcu", "can", "canbus", "radio", "fm",
            "bt", "bluetooth", "dsp", "eq", "equalizer", "aux", "avin", "camera",
            "avm", "dvr", "tpms", "car", "vehicle", "launcher", "swc", "key",
            "music", "video", "navi", "settings", "zlink", "carplay", "tlx", "qf"
        )

        var vendorPackageCount = 0
        try {
            @Suppress("DEPRECATION")
            val installed = pm.getInstalledPackages(0)
            for (pkg in installed) {
                val pkgName = pkg.packageName ?: continue
                val appInfo = pkg.applicationInfo
                val sourceDir = appInfo?.sourceDir ?: ""
                val isSystem = appInfo != null && (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                val label = try {
                    if (appInfo != null) pm.getApplicationLabel(appInfo).toString() else pkgName
                } catch (_: Exception) {
                    pkgName
                }

                val summaryObj = JSONObject()
                summaryObj.put("packageName", pkgName)
                summaryObj.put("label", label)
                summaryObj.put("versionName", pkg.versionName ?: "")
                summaryObj.put("isSystem", isSystem)
                summaryObj.put("sourceDir", sourceDir)
                allPackagesSummary.put(summaryObj)

                val lowerPkg = pkgName.lowercase(Locale.ROOT)
                val lowerSrc = sourceDir.lowercase(Locale.ROOT)
                val isGoogleOrStock = lowerPkg.startsWith("com.google.") ||
                    lowerPkg.startsWith("com.android.cts.") ||
                    lowerPkg.startsWith("com.android.providers.") ||
                    lowerPkg.startsWith("com.android.theme.") ||
                    lowerPkg.startsWith("android.auto_generated")

                val matchesVendorKeyword = vendorKeywords.any { kw ->
                    lowerPkg.contains(kw) || lowerSrc.contains("/oem/") || lowerSrc.contains("/custom/")
                }

                if (!isGoogleOrStock && (matchesVendorKeyword || !isSystem)) {
                    try {
                        @Suppress("DEPRECATION")
                        val flags = PackageManager.GET_ACTIVITIES or
                            PackageManager.GET_RECEIVERS or
                            PackageManager.GET_SERVICES
                        @Suppress("DEPRECATION")
                        val detailed: PackageInfo = pm.getPackageInfo(pkgName, flags)
                        val detailObj = JSONObject()
                        detailObj.put("packageName", pkgName)
                        detailObj.put("label", label)
                        detailObj.put("sourceDir", sourceDir)
                        detailObj.put("sharedUserId", detailed.sharedUserId ?: "")

                        val actArr = JSONArray()
                        detailed.activities?.forEach { act ->
                            val aObj = JSONObject()
                            aObj.put("name", act.name)
                            aObj.put("exported", act.exported)
                            aObj.put("permission", act.permission ?: "")
                            aObj.put("targetActivity", act.targetActivity ?: "")
                            aObj.put(
                                "label",
                                try { act.loadLabel(pm).toString() } catch (_: Exception) { "" }
                            )
                            actArr.put(aObj)
                        }
                        detailObj.put("activities", actArr)

                        val rcvArr = JSONArray()
                        detailed.receivers?.forEach { rcv ->
                            val rObj = JSONObject()
                            rObj.put("name", rcv.name)
                            rObj.put("exported", rcv.exported)
                            rObj.put("permission", rcv.permission ?: "")
                            rcvArr.put(rObj)
                        }
                        detailObj.put("receivers", rcvArr)

                        val srvArr = JSONArray()
                        detailed.services?.forEach { srv ->
                            val sObj = JSONObject()
                            sObj.put("name", srv.name)
                            sObj.put("exported", srv.exported)
                            sObj.put("permission", srv.permission ?: "")
                            srvArr.put(sObj)
                        }
                        detailObj.put("services", srvArr)

                        deepVendorPackages.put(detailObj)
                        vendorPackageCount++
                    } catch (_: Exception) {}
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error inspecting installed packages", e)
        }
        root.put("allInstalledPackages", allPackagesSummary)
        root.put("deepVendorPackages", deepVendorPackages)

        // 6. Running Background Services (identifies active MCU / CAN / Radio / BT services)
        val runningServicesArr = JSONArray()
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            @Suppress("DEPRECATION")
            val services = am.getRunningServices(250)
            services?.forEach { srv ->
                val sObj = JSONObject()
                sObj.put("packageName", srv.service.packageName)
                sObj.put("className", srv.service.className)
                sObj.put("process", srv.process ?: "")
                sObj.put("foreground", srv.foreground)
                sObj.put("started", srv.started)
                runningServicesArr.put(sObj)
            }
        } catch (_: Exception) {}
        root.put("runningServices", runningServicesArr)

        // 7. Broadcast Receiver Probe for Common Headunit / Media / Ignition Actions
        val probedActions = listOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MEDIA_BUTTON,
            "com.android.music.metachanged",
            "com.android.music.playstatechanged",
            "com.ts.action.ACC_ON",
            "com.ts.action.ACC_OFF",
            "com.topway.action.ACC_ON",
            "com.topway.action.ACC_OFF",
            "com.syu.action.ACC_ON",
            "com.fyt.action.ACC_ON",
            "com.microntek.acc.on",
            "com.microntek.bootcheck",
            "com.xy.android.acc.on",
            "autochips.intent.action.QB_POWERON",
            "com.forfan.operator.ACC_ON"
        )
        val broadcastProbeObj = JSONObject()
        for (action in probedActions) {
            try {
                @Suppress("DEPRECATION")
                val receivers = pm.queryBroadcastReceivers(Intent(action), PackageManager.MATCH_ALL)
                if (!receivers.isNullOrEmpty()) {
                    val arr = JSONArray()
                    for (ri in receivers) {
                        val ai = ri.activityInfo ?: continue
                        arr.put("${ai.packageName}/${ai.name}")
                    }
                    broadcastProbeObj.put(action, arr)
                }
            } catch (_: Exception) {}
        }
        root.put("broadcastReceiversByAction", broadcastProbeObj)

        // 8. Input Devices (Steering Wheel Controls / Bezel Hardware Keys) & Audio State
        val inputArr = JSONArray()
        try {
            for (id in InputDevice.getDeviceIds()) {
                val dev = InputDevice.getDevice(id) ?: continue
                val dObj = JSONObject()
                dObj.put("id", dev.id)
                dObj.put("name", dev.name)
                dObj.put("descriptor", dev.descriptor)
                dObj.put("vendorId", dev.vendorId)
                dObj.put("productId", dev.productId)
                dObj.put("isVirtual", dev.isVirtual)
                dObj.put("sources", dev.sources)
                inputArr.put(dObj)
            }
        } catch (_: Exception) {}
        root.put("inputDevices", inputArr)

        val audioObj = JSONObject()
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioObj.put("musicVolume", audioManager.getStreamVolume(AudioManager.STREAM_MUSIC))
            audioObj.put("musicMaxVolume", audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC))
            audioObj.put("isMusicActive", audioManager.isMusicActive)
            audioObj.put("mode", audioManager.mode)
        } catch (_: Exception) {}
        root.put("audioState", audioObj)

        // 9. Complete System Properties (`getprop`)
        val propsObj = JSONObject()
        try {
            val proc = ProcessBuilder("getprop").redirectErrorStream(true).start()
            BufferedReader(InputStreamReader(proc.inputStream)).use { reader ->
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    val trimmed = line!!.trim()
                    if (trimmed.startsWith("[") && trimmed.contains("]: [")) {
                        val splitIdx = trimmed.indexOf("]: [")
                        val key = trimmed.substring(1, splitIdx)
                        val value = trimmed.substring(splitIdx + 4).removeSuffix("]")
                        propsObj.put(key, value)
                    }
                }
            }
            proc.waitFor()
        } catch (e: Exception) {
            propsObj.put("_error", e.message)
        }
        root.put("systemProperties", propsObj)

        // Save formatted JSON to /storage/emulated/0/OBDrive or /storage/emulated/0/Download/OBDrive
        val fileName = "obdrive_headunit_dump_${fileFmt.format(now)}.json"
        val jsonContent = root.toString(2)
        val savedPath = saveToExternalStorage(fileName, jsonContent, "application/json")

        return mapOf(
            "savedPath" to savedPath,
            "sdkInt" to Build.VERSION.SDK_INT,
            "release" to Build.VERSION.RELEASE,
            "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "launchableAppsCount" to launchableArray.length(),
            "vendorPackagesCount" to vendorPackageCount,
            "systemPropsCount" to propsObj.length()
        )
    }

    private fun saveToExternalStorage(fileName: String, content: String, mimeType: String): String {
        val bytes = content.toByteArray(Charsets.UTF_8)

        // 1. Try direct write to /storage/emulated/0/OBDrive or /storage/emulated/0/Download/OBDrive
        val directCandidates = listOf(
            File("/storage/emulated/0/OBDrive"),
            File("/storage/emulated/0/Download/OBDrive"),
            File(Environment.getExternalStorageDirectory(), "OBDrive"),
            File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "OBDrive")
        )
        for (dir in directCandidates) {
            try {
                if (!dir.exists()) {
                    dir.mkdirs()
                }
                if (dir.exists() && dir.canWrite()) {
                    val outFile = File(dir, fileName)
                    outFile.writeBytes(bytes)
                    return outFile.absolutePath
                }
            } catch (_: Exception) {
                // Fall through to MediaStore
            }
        }

        // 2. Android 10+ (API 29+): Use MediaStore.Downloads so no special storage permission is required
        // to write directly into /storage/emulated/0/Download/OBDrive/<fileName>
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/OBDrive")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            if (uri != null) {
                resolver.openOutputStream(uri)?.use { os ->
                    os.write(bytes)
                    os.flush()
                }
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                return "/storage/emulated/0/Download/OBDrive/$fileName"
            }
        }

        // 3. Final fallback on /storage/emulated/0/Android/data/<pkg>/files/OBDrive_Exports
        val extDir = getExternalFilesDir(null)
        if (extDir != null) {
            val exportDir = File(extDir, "OBDrive_Exports")
            if (!exportDir.exists()) exportDir.mkdirs()
            val outFile = File(exportDir, fileName)
            outFile.writeBytes(bytes)
            return outFile.absolutePath
        }

        throw IllegalStateException("Unable to access /storage/emulated/0/")
    }

    private var isResumedState: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setupCrashHandler()
        handleSilentStart(intent)
    }

    override fun onResume() {
        super.onResume()
        isResumedState = true
    }

    override fun onPause() {
        super.onPause()
        isResumedState = false
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleSilentStart(intent)
    }

    private fun handleSilentStart(intent: Intent?) {
        if (intent?.getBooleanExtra("silent_start", false) == true) {
            if (isResumedState) {
                Log.i(TAG, "OBDrive is active in foreground; ignoring silent_start moveTaskToBack")
                return
            }
            Log.i(TAG, "OBDrive started silently from ignition wake; moving task to back")
            moveTaskToBack(true)
            try {
                @Suppress("DEPRECATION")
                overridePendingTransition(0, 0)
            } catch (_: Exception) {}
        }
    }

    private fun setupCrashHandler() {
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val sdf = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
                val time = sdf.format(Date())
                val stackTraceString = Log.getStackTraceString(throwable)
                val crashReport = "[$time] [FATAL NATIVE CRASH] Thread: ${thread.name} (ID: ${thread.id})\n$stackTraceString\n\n"

                // 1. Try writing to internal files directory
                try {
                    val crashFileInternal = File(filesDir, "obdrive_crash.log")
                    crashFileInternal.appendText(crashReport)
                } catch (_: Exception) {}

                // 2. Try writing to public Download/OBDrive directory
                try {
                    val extDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "OBDrive")
                    if (!extDir.exists()) extDir.mkdirs()
                    if (extDir.exists() && extDir.canWrite()) {
                        File(extDir, "obdrive_crash.log").appendText(crashReport)
                    }
                } catch (_: Exception) {}

                Log.e(TAG, "FATAL CRASH logged to obdrive_crash.log: ${throwable.message}", throwable)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to persist crash report", e)
            } finally {
                defaultHandler?.uncaughtException(thread, throwable)
            }
        }
    }
}
