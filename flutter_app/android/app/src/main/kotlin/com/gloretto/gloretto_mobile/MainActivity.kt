package com.gloretto.gloretto_mobile

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Device-SIM SMS for front-desk guest welcome messages.
 * Sends silently via SmsManager (uses this phone's load / default SMS SIM).
 * Never opens the Messages app.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "gloretto/device_sms"
    private val smsPermissionRequest = 9911
    private var pendingSmsResult: MethodChannel.Result? = null
    private var pendingPhone: String? = null
    private var pendingBody: String? = null
    private var pendingPermissionOnly: Boolean = false

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
                        sendSmsWithPermission(phone, body, result)
                    }
                    "hasSmsPermission" -> {
                        result.success(hasSmsPermission())
                    }
                    "ensureSmsPermission" -> {
                        if (hasSmsPermission()) {
                            result.success(mapOf("granted" to true))
                            return@setMethodCallHandler
                        }
                        pendingPermissionOnly = true
                        pendingSmsResult = result
                        pendingPhone = null
                        pendingBody = null
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.SEND_SMS),
                            smsPermissionRequest,
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasSmsPermission(): Boolean {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun sendSmsWithPermission(phone: String, body: String, result: MethodChannel.Result) {
        if (hasSmsPermission()) {
            try {
                sendSmsNow(phone, body)
                result.success(mapOf("sent" to true, "mode" to "direct"))
            } catch (e: Exception) {
                result.success(
                    mapOf(
                        "sent" to false,
                        "mode" to "send_failed",
                        "error" to (e.message ?: "SMS send failed"),
                    ),
                )
            }
            return
        }

        pendingPermissionOnly = false
        pendingSmsResult = result
        pendingPhone = phone
        pendingBody = body
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.SEND_SMS),
            smsPermissionRequest,
        )
    }

    private fun resolveSmsManager(): SmsManager {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val mgr = getSystemService(SmsManager::class.java)
                if (mgr != null) return mgr
            }
            val subId = SmsManager.getDefaultSmsSubscriptionId()
            if (subId != SubscriptionManager.INVALID_SUBSCRIPTION_ID &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1
            ) {
                SmsManager.getSmsManagerForSubscriptionId(subId)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
        } catch (_: Exception) {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }
    }

    private fun sendSmsNow(phone: String, body: String) {
        val smsManager = resolveSmsManager()
        val parts = smsManager.divideMessage(body)
        if (parts != null && parts.size > 1) {
            smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
        } else {
            smsManager.sendTextMessage(phone, null, body, null, null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != smsPermissionRequest) return

        val result = pendingSmsResult
        val phone = pendingPhone
        val body = pendingBody
        val permissionOnly = pendingPermissionOnly
        pendingSmsResult = null
        pendingPhone = null
        pendingBody = null
        pendingPermissionOnly = false

        if (result == null) return

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED

        if (permissionOnly) {
            result.success(mapOf("granted" to granted))
            return
        }

        if (!granted) {
            result.success(mapOf("sent" to false, "mode" to "permission_denied"))
            return
        }

        if (phone == null || body == null) {
            result.success(mapOf("sent" to false, "mode" to "send_failed", "error" to "Missing SMS payload"))
            return
        }

        try {
            sendSmsNow(phone, body)
            result.success(mapOf("sent" to true, "mode" to "direct"))
        } catch (e: Exception) {
            result.success(
                mapOf(
                    "sent" to false,
                    "mode" to "send_failed",
                    "error" to (e.message ?: "SMS send failed"),
                ),
            )
        }
    }
}
