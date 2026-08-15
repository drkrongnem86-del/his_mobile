package com.drnem.ccdk.his_mobile

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import id.laskarmedia.openvpn_flutter.OpenVPNFlutterPlugin
import java.io.File

/// v3.0.28: Tích hợp VNPT SmartCA Deeplink SDK
/// MethodChannel: com.drnem.ccdk.his_mobile/vnpt_smartca
/// v3.0.76: Thêm OpenVPNFlutterPlugin.connectWhileGranted để xử lý VpnService permission prompt
/// v3.0.99: Thêm MethodChannel 'his_mobile/installer' cho auto-update
/// v3.0.111: Thêm method 'openInstallPermissionSettings' + 'canRequestPackageInstalls'
class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.drnem.ccdk.his_mobile/vnpt_smartca"
    private val INSTALL_CHANNEL = "his_mobile/installer"
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

        // v3.0.99: Installer channel - dùng FileProvider để mở APK
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("INVALID_ARGS", "path is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = File(path)
                            if (!file.exists()) {
                                result.error("FILE_NOT_FOUND", "APK file not found: $path", null)
                                return@setMethodCallHandler
                            }
                            val apkUri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                // Android 7+ (API 24+): phải dùng FileProvider
                                FileProvider.getUriForFile(
                                    this,
                                    "$packageName.fileprovider",
                                    file
                                )
                            } else {
                                // Android < 7: file:// URI vẫn OK
                                Uri.fromFile(file)
                            }
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(apkUri, "application/vnd.android.package-archive")
                                // v3.0.121: Thêm FLAG_ACTIVITY_CLEAR_TASK để install dialog
                                // chạy trong task riêng, không bị conflict với app cũ
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_ACTIVITY_CLEAR_TASK
                            }
                            // v3.0.121: Fix lỗi "App not installed" khi tự cập nhật
                            // Android PackageInstaller yêu cầu app cũ phải TẮT HẲN (process killed)
                            // trước khi cho cài đè. Nếu app cũ vẫn còn foreground/background process,
                            // OS sẽ báo "App not installed" dù signature khớp.
                            //
                            // Flow:
                            // 1. finishAndRemoveTask() - đóng activity, xóa khỏi recents
                            // 2. startActivity(install intent) - mở install permission dialog
                            // 3. postDelayed kill process 800ms - đợi install dialog start xong rồi kill
                            //    → user grant permission + tap Cập nhật → process cũ đã chết → install OK
                            finishAndRemoveTask()
                            startActivity(intent)
                            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                                android.os.Process.killProcess(android.os.Process.myPid())
                            }, 800)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, e.stackTrace.toString())
                        }
                    }
                    "canRequestPackageInstalls" -> {
                        // v3.0.111: Check app có quyền install unknown apps không
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            result.success(packageManager.canRequestPackageInstalls())
                        } else {
                            // Android < 8 luôn có quyền
                            result.success(true)
                        }
                    }
                    "openInstallPermissionSettings" -> {
                        // v3.0.111: Mở Settings "Install unknown apps" cho app hiện tại
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                    data = Uri.parse("package:$packageName")
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                }
                                startActivity(intent)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            result.error("OPEN_SETTINGS_FAILED", e.message, e.stackTrace.toString())
                        }
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
