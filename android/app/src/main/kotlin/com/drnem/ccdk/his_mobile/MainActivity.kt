package com.drnem.ccdk.his_mobile

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import id.laskarmedia.openvpn_flutter.OpenVPNFlutterPlugin

/// v3.0.28: Tích hợp VNPT SmartCA Deeplink SDK
/// MethodChannel: com.drnem.ccdk.his_mobile/vnpt_smartca
/// v3.0.76: Thêm OpenVPNFlutterPlugin.connectWhileGranted để xử lý VpnService permission prompt
class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.drnem.ccdk.his_mobile/vnpt_smartca"
    private var pendingResult: MethodChannel.Result? = null
    private var vnptPlugin: VnptSmartcaPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        vnptPlugin = VnptSmartcaPlugin(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "init" -> {
                        val clientId = call.argument<String>("clientId")
                        val env = call.argument<String>("env") ?: "PRODUCTION"
                        if (clientId == null) {
                            result.error("INVALID_ARGS", "clientId is required", null)
                            return@setMethodCallHandler
                        }
                        vnptPlugin?.init(clientId, env, result)
                    }
                    "requestSign" -> {
                        val tranId = call.argument<String>("tranId")
                        if (tranId == null) {
                            result.error("INVALID_ARGS", "tranId is required", null)
                            return@setMethodCallHandler
                        }
                        // Lưu result để xử lý khi VNPT SmartCA trả về
                        pendingResult = result
                        vnptPlugin?.requestSign(tranId)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// v3.0.28: Xử lý result từ VNPT SmartCA + v3.0.76: VPN permission prompt
    /// onActivityResult được gọi khi:
    ///   - VNPT SmartCA finish và gọi setResult(RESULT_OK, data)
    ///   - User accept/reject VpnService permission (requestCode=24)
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // v3.0.76: Báo cho openvpn_flutter biết user đã trả lời VPN permission prompt
        OpenVPNFlutterPlugin.connectWhileGranted(requestCode == 24 && resultCode == RESULT_OK)
        super.onActivityResult(requestCode, resultCode, data)
        val r = pendingResult ?: return
        pendingResult = null
        vnptPlugin?.handleResult(requestCode, resultCode, data, r)
    }

    /// v3.0.28: Fallback nếu app được resume qua newIntent thay vì onActivityResult
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Nếu pendingResult còn và có deep link data → xử lý
        val r = pendingResult ?: return
        // Deep link thường qua scheme → check intent.data
        if (intent.data != null) {
            // TODO: parse deep link URL để lấy kết quả ký
            // Hiện tại: VNPT SmartCA dùng onActivityResult, không qua deep link
        }
    }
}
