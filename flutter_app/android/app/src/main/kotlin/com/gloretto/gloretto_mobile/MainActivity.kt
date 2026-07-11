package com.gloretto.gloretto_mobile

import android.Manifest
import android.content.pm.PackageManager
import android.telephony.SmsManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Device-SIM SMS for front-desk check-in welcome messages.
 * Uses the phone's default SMS subscription (the SIM that owns this device).
 */
class MainActivity : FlutterActivity() {
    private val channelName = "gloretto/device_sms"
    private val smsPermissionRequest = 9911
    private var pendingSmsResult: MethodChannel.Result? = null
    private var pendingPhone: String? = null
    private var pendingBody: String? = null

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
                result.error("send_failed", e.message, null)
            }
            return
        }

        pendingSmsResult = result
        pendingPhone = phone
        pendingBody = body
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.SEND_SMS),
            smsPermissionRequest,
        )
    }

    private fun sendSmsNow(phone: String, body: String) {
        val smsManager = getSystemService(SmsManager::class.java)
            ?: SmsManager.getDefault()
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
        pendingSmsResult = null
        pendingPhone = null
        pendingBody = null

        if (result == null || phone == null || body == null) return

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            result.success(mapOf("sent" to false, "mode" to "permission_denied"))
            return
        }

        try {
            sendSmsNow(phone, body)
            result.success(mapOf("sent" to true, "mode" to "direct"))
        } catch (e: Exception) {
            result.error("send_failed", e.message, null)
        }
    }
}
