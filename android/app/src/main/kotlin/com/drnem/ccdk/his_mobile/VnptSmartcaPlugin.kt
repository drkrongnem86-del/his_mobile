package com.drnem.ccdk.his_mobile

import android.app.Activity
import android.content.Intent
import com.vnpt.egov.vnptsmartcaandroidsdk.ParameterNameTransaction
import com.vnpt.egov.vnptsmartcaandroidsdk.Transaction
import io.flutter.plugin.common.MethodChannel

/// v3.0.28: Wrapper cho VNPT SmartCA Android SDK (Deeplink)
/// Docs: https://smartca.vnpt.vn/help/docs/sdks/deeplink/steps/android/
/// SDK: com.github.VNPTSmartCA:android-sdk:1.0.4
class VnptSmartcaPlugin(private val activity: Activity) {

    private var clientId: String? = null
    private var environment: Transaction.ENVIRONMENT = Transaction.ENVIRONMENT.PRODUCTION

    /// Khởi tạo SDK VNPT SmartCA với clientId + environment
    fun init(clientId: String, env: String, result: MethodChannel.Result) {
        try {
            this.clientId = clientId
            this.environment = when (env.uppercase()) {
                "DEVELOPMENT", "DEV", "TEST" -> Transaction.ENVIRONMENT.DEVELOPMENT
                else -> Transaction.ENVIRONMENT.PRODUCTION
            }
            Transaction.getInstance().setEnvironment(this.environment)
            result.success(mapOf(
                "ok" to true,
                "clientId" to clientId,
                "env" to this.environment.name
            ))
        } catch (e: Exception) {
            result.error("INIT_FAILED", e.message, null)
        }
    }

    /// Mở app VNPT SmartCA để ký giao dịch
    /// Sử dụng activity đã lưu trong constructor
    fun requestSign(tranId: String) {
        val cid = clientId
        if (cid == null) {
            throw IllegalStateException("Call init() first before requestSign()")
        }
        val eventValue = HashMap<String, String>()
        eventValue[ParameterNameTransaction.CLIENT_ID] = cid
        eventValue[ParameterNameTransaction.TRAN_ID] = tranId
        // Mở VNPT SmartCA app → user xác nhận → quay lại app này
        Transaction.getInstance().requestVNPTSmartCACallback(activity, eventValue)
    }

    /// Xử lý result từ VNPT SmartCA (gọi từ MainActivity.onActivityResult)
    fun handleResult(requestCode: Int, resultCode: Int, data: Intent?, result: MethodChannel.Result) {
        try {
            val expected = Transaction.getInstance().REQUEST_CODE_VNPT_SMARTCA
            if (requestCode != expected) {
                result.error("WRONG_REQUEST_CODE", "Expected $expected, got $requestCode", null)
                return
            }
            if (resultCode != Activity.RESULT_OK) {
                // User hủy hoặc lỗi
                val errMsg = when (resultCode) {
                    Activity.RESULT_CANCELED -> "USER_CANCELLED"
                    Activity.RESULT_FIRST_USER -> "VNPT_ERROR"
                    else -> "RESULT_CODE_$resultCode"
                }
                result.success(mapOf(
                    "ok" to false,
                    "status" to resultCode,
                    "message" to (data?.extras?.getString("message") ?: "User cancelled"),
                ))
                return
            }
            if (data == null || data.extras == null) {
                result.error("NO_DATA", "No extras in result", null)
                return
            }
            val extras = data.extras!!
            val status = extras.getInt("status", -1)
            val message = extras.getString("message") ?: ""
            val signature = extras.getString("signature") ?: ""

            // status = 0: ký thành công
            if (status == 0) {
                result.success(mapOf(
                    "ok" to true,
                    "status" to status,
                    "message" to message,
                    "signature" to signature,
                    "tranId" to (extras.getString("tranId") ?: "")
                ))
            } else {
                result.success(mapOf(
                    "ok" to false,
                    "status" to status,
                    "message" to message,
                ))
            }
        } catch (e: Exception) {
            result.error("HANDLE_RESULT_FAILED", e.message, null)
        }
    }
}
