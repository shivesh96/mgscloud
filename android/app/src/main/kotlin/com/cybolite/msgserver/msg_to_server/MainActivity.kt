package com.cybolite.msgserver.msg_to_server

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.annotation.Keep

@Keep
class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.cybolite.msgserver/channel"
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
        rebindNotificationListenerServiceIfNeeded()
    }

    override fun onResume() {
        super.onResume()
        rebindNotificationListenerServiceIfNeeded()
    }

    private fun rebindNotificationListenerServiceIfNeeded() {
        try {
            if (isNotificationListenerPermissionGranted()) {
                val componentName = android.content.ComponentName(this, MsgNotificationListenerService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    android.service.notification.NotificationListenerService.requestRebind(componentName)
                }
                val pm = packageManager
                pm.setComponentEnabledSetting(
                    componentName,
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP
                )
                pm.setComponentEnabledSetting(
                    componentName,
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    PackageManager.DONT_KILL_APP
                )
            }
        } catch (_: Exception) {}
    }

    private fun createNotificationChannel() {
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {

                "getDeviceId" -> {
                    val deviceId = android.provider.Settings.Secure.getString(
                        contentResolver, android.provider.Settings.Secure.ANDROID_ID
                    )
                    result.success(deviceId ?: "unknown")
                }
                "getSimInfo" -> {
                    result.success(getSimInfo())
                }
                "getInstalledWhatsAppPackages" -> {
                    result.success(getInstalledWhatsAppPackages())
                }
                "isNotificationListenerPermissionGranted" -> {
                    val granted = isNotificationListenerPermissionGranted()
                    if (granted) {
                        rebindNotificationListenerServiceIfNeeded()
                    }
                    result.success(granted)
                }
                "rebindNotificationListener" -> {
                    rebindNotificationListenerServiceIfNeeded()
                    result.success(true)
                }
                "openNotificationListenerSettings" -> {
                    openNotificationListenerSettings()
                    result.success(true)
                }
                "isBatteryOptimizationIgnored" -> {
                    result.success(isBatteryOptimizationIgnored())
                }
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(true)
                }
                "getDeviceManufacturer" -> {
                    result.success(Build.MANUFACTURER?.lowercase() ?: "generic")
                }
                "openAutoStartSettings" -> {
                    openAutoStartSettings()
                    result.success(true)
                }
                "pollPendingEvents" -> {
                    val events = EventBridge.drainPersistedEvents(this)
                    result.success(events)
                }
                else -> result.notImplemented()
            }
        }

        // Set up real-time listener callback
        EventBridge.setEventListener { eventMap ->
            runOnUiThread {
                methodChannel?.invokeMethod("onEventCaptured", eventMap)
            }
        }
    }

    override fun onDestroy() {
        EventBridge.setEventListener(null)
        super.onDestroy()
    }

    @SuppressLint("HardwareIds")
    private fun getSimInfo(): List<Map<String, Any?>> {
        val simList = mutableListOf<Map<String, Any?>>()
        try {
            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
                return simList
            }

            val subscriptionManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            val activeList: List<SubscriptionInfo>? = subscriptionManager?.activeSubscriptionInfoList

            if (!activeList.isNullOrEmpty()) {
                for (info in activeList) {
                    var number: String? = null
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            number = subscriptionManager.getPhoneNumber(info.subscriptionId)
                        }
                        if (number.isNullOrEmpty()) {
                            number = info.number
                        }
                    } catch (_: Exception) {
                        number = info.number
                    }

                    val simMap = mapOf<String, Any?>(
                        "subscriptionId" to info.subscriptionId,
                        "slotIndex" to info.simSlotIndex,
                        "carrierName" to (info.carrierName?.toString() ?: "Unknown"),
                        "displayName" to (info.displayName?.toString() ?: "SIM ${info.simSlotIndex + 1}"),
                        "countryIso" to (info.countryIso ?: ""),
                        "iccId" to (info.iccId ?: ""),
                        "number" to (number ?: "")
                    )
                    simList.add(simMap)
                }
            }
        } catch (_: Exception) {
        }
        return simList
    }

    private fun getInstalledWhatsAppPackages(): List<Map<String, Any?>> {
        val result = mutableListOf<Map<String, Any?>>()
        val pm = packageManager

        // Known WhatsApp packages
        val targets = listOf(
            Pair("com.whatsapp", "WhatsApp"),
            Pair("com.whatsapp.w4b", "WhatsApp Business"),
            Pair("com.gbwhatsapp", "GBWhatsApp"),
            Pair("com.whatsapp.clone", "WhatsApp Clone")
        )

        val foundPackages = mutableSetOf<String>()

        for ((pkg, name) in targets) {
            try {
                val appInfo = pm.getApplicationInfo(pkg, 0)
                val label = pm.getApplicationLabel(appInfo).toString()
                val pkgInfo = pm.getPackageInfo(pkg, 0)
                foundPackages.add(pkg)
                result.add(
                    mapOf(
                        "packageName" to pkg,
                        "appName" to if (label.isNotEmpty()) label else name,
                        "isClone" to (pkg != "com.whatsapp" && pkg != "com.whatsapp.w4b"),
                        "versionName" to (pkgInfo.versionName ?: "")
                    )
                )
            } catch (_: PackageManager.NameNotFoundException) {
            }
        }

        // Search installed packages for any cloned or dual messenger instances
        try {
            val installedApps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
            for (app in installedApps) {
                val pkg = app.packageName
                if (foundPackages.contains(pkg)) continue

                val lower = pkg.lowercase()
                val label = pm.getApplicationLabel(app).toString().lowercase()

                if (lower.contains("whatsapp") ||
                    (label.contains("whatsapp") && (lower.contains("clone") || lower.contains("dual") || lower.contains("parallel")))) {
                    val appLabel = pm.getApplicationLabel(app).toString()
                    var version = ""
                    try {
                        version = pm.getPackageInfo(pkg, 0).versionName ?: ""
                    } catch (_: Exception) {}

                    foundPackages.add(pkg)
                    result.add(
                        mapOf(
                            "packageName" to pkg,
                            "appName" to appLabel,
                            "isClone" to true,
                            "versionName" to version
                        )
                    )
                }
            }
        } catch (_: Exception) {
        }

        return result
    }

    private fun isNotificationListenerPermissionGranted(): Boolean {
        val enabledPackages = NotificationManagerCompat.getEnabledListenerPackages(this)
        return enabledPackages.contains(packageName)
    }

    private fun openNotificationListenerSettings() {
        try {
            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent(Settings.ACTION_SETTINGS)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } catch (_: Exception) {}
        }
    }

    private fun isBatteryOptimizationIgnored(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
        return pm?.isIgnoringBatteryOptimizations(packageName) ?: false
    }

    private fun requestIgnoreBatteryOptimizations() {
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (_: Exception) {
            try {
                val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
            } catch (_: Exception) {}
        }
    }

    private fun openAutoStartSettings() {
        val manufacturer = Build.MANUFACTURER?.lowercase() ?: ""
        val intents = mutableListOf<Intent>()

        when {
            manufacturer.contains("xiaomi") || manufacturer.contains("redmi") || manufacturer.contains("poco") -> {
                intents.add(Intent().setComponent(android.content.ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")))
                intents.add(Intent("miui.intent.action.OP_AUTO_START").addCategory(Intent.CATEGORY_DEFAULT))
            }
            manufacturer.contains("samsung") -> {
                intents.add(Intent().setComponent(android.content.ComponentName("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity")))
                intents.add(Intent().setComponent(android.content.ComponentName("com.samsung.android.sm", "com.samsung.android.sm.ui.battery.BatteryActivity")))
                intents.add(Intent().setComponent(android.content.ComponentName("com.samsung.android.sm_cn", "com.samsung.android.sm.ui.battery.BatteryActivity")))
            }
            manufacturer.contains("huawei") || manufacturer.contains("honor") -> {
                intents.add(Intent().setComponent(android.content.ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity")))
                intents.add(Intent().setComponent(android.content.ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity")))
                intents.add(Intent().setComponent(android.content.ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity")))
            }
            manufacturer.contains("oppo") || manufacturer.contains("realme") -> {
                intents.add(Intent().setComponent(android.content.ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity")))
                intents.add(Intent().setComponent(android.content.ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity")))
                intents.add(Intent().setComponent(android.content.ComponentName("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity")))
            }
            manufacturer.contains("vivo") || manufacturer.contains("iqoo") -> {
                intents.add(Intent().setComponent(android.content.ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity")))
                intents.add(Intent().setComponent(android.content.ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")))
            }
            manufacturer.contains("oneplus") -> {
                intents.add(Intent().setComponent(android.content.ComponentName("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity")))
            }
        }

        // Generic fallback to Application Details Settings
        val appDetailsIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
        }
        intents.add(appDetailsIntent)

        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return
            } catch (_: Exception) {
                // Try next intent
            }
        }
    }
}
