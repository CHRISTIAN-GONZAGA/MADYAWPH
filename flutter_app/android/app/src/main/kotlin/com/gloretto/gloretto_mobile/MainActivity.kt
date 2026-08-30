package com.gloretto.gloretto_mobile

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Front-desk guest welcome SMS uses the system Messages composer (ACTION_SENDTO).
 * Play Store rejects SEND_SMS on consumer listings that are not the default SMS app.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "gloretto/device_sms"
    private val appsChannelName = "gloretto/installed_apps"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendSms" -> {
                        val phone = call.argument<String>("phone")?.trim().orEmpty()
                        val body = call.argument<String>("body")?.trim().orEmpty()
                        if (phone.isEmpty() || body.isEmpty()) {
                            result.error("invalid_args", "phone and body are required", null)
                            return@setMethodCallHandler
                        }
                        result.success(openSmsComposer(phone, body))
                    }
                    "hasSmsPermission", "ensureSmsPermission" -> {
                        result.success(mapOf("granted" to true))
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appsChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAppInstalled" -> {
                        val packageName = call.argument<String>("package")?.trim().orEmpty()
                        if (packageName.isEmpty()) {
                            result.error("invalid_args", "package is required", null)
                            return@setMethodCallHandler
                        }
                        result.success(isPackageInstalled(packageName))
                    }
                    "launchApp" -> {
                        val packageName = call.argument<String>("package")?.trim().orEmpty()
                        if (packageName.isEmpty()) {
                            result.error("invalid_args", "package is required", null)
                            return@setMethodCallHandler
                        }
                        result.success(launchInstalledApp(packageName))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openSmsComposer(phone: String, body: String): Map<String, Any> {
        return try {
            val uri = Uri.parse("smsto:${Uri.encode(phone)}")
            val intent = Intent(Intent.ACTION_SENDTO, uri)
            intent.putExtra("sms_body", body)
            intent.putExtra(Intent.EXTRA_TEXT, body)
            startActivity(intent)
            mapOf("sent" to true, "mode" to "composer")
        } catch (e: Exception) {
            mapOf(
                "sent" to false,
                "mode" to "send_failed",
                "error" to (e.message ?: "Could not open Messages"),
            )
        }
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun launchInstalledApp(packageName: String): Boolean {
        return try {
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(launchIntent)
                return true
            }

            val scheme = when (packageName) {
                "com.globe.gcash.android" -> "gcash://"
                "com.paymaya", "com.maya.maya" -> "maya://"
                else -> null
            }
            if (scheme != null) {
                val view = Intent(Intent.ACTION_VIEW, Uri.parse(scheme))
                view.setPackage(packageName)
                view.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (view.resolveActivity(packageManager) != null) {
                    startActivity(view)
                    return true
                }
            }
            false
        } catch (_: Exception) {
            false
        }
    }
}
