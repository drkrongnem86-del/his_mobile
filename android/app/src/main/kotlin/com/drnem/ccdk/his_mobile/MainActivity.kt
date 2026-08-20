package com.drnem.ccdk.his_mobile

import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
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
/// v3.0.122: Thêm method 'saveApkToDownloads' - copy APK vào thư mục Download public
/// v3.0.123: Refactor 'installApk' - dùng PackageInstaller.Session API (officially supported
///            for in-app updates, KHÔNG cần kill process, hệ thống tự handle lifecycle)
/// v3.0.145: Thêm PdfRenderer channel - render PDF page to PNG using Android native PdfRenderer
class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.drnem.ccdk.his_mobile/vnpt_smartca"
    private val INSTALL_CHANNEL = "his_mobile/installer"
    private val PDF_RENDERER_CHANNEL = "his_mobile/pdf_renderer"
    private var pendingResult: MethodChannel.Result? = null
    private var vnptPlugin: VnptSmartcaPlugin? = null

    // v3.0.145: Render PDF bytes to PNG using Android native PdfRenderer
    // PdfRenderer available from API 21. No external packages needed.
    private fun renderPdfPageToPng(pdfBytes: ByteArray, dpi: Int, pageIndex: Int): ByteArray? {
        return try {
            // Write PDF bytes to a temp file (PdfRenderer requires a file path)
            val tempFile = File(cacheDir, "temp_render_${System.currentTimeMillis()}.pdf")
            tempFile.writeBytes(pdfBytes)

            // Open file descriptor - use ParcelFileDescriptor for API <30 compatibility
            val parcelFd = android.os.ParcelFileDescriptor.open(tempFile, android.os.ParcelFileDescriptor.MODE_READ_ONLY)
            val renderer = android.graphics.pdf.PdfRenderer(parcelFd)

            if (pageIndex >= renderer.pageCount) {
                renderer.close()
                parcelFd.close()
                tempFile.delete()
                return null
            }

            val page = renderer.openPage(pageIndex)
            // Calculate pixel dimensions: PDF uses 72 DPI internally, scale to target DPI
            val scale = dpi / 72.0f
            val width = (page.width * scale).toInt()
            val height = (page.height * scale).toInt()

            val bitmap = android.graphics.Bitmap.createBitmap(width, height, android.graphics.Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(android.graphics.Color.WHITE)
            page.render(bitmap, null, null, android.graphics.pdf.PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

            // Convert bitmap to PNG
            val outputStream = java.io.ByteArrayOutputStream()
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, outputStream)
            val pngBytes = outputStream.toByteArray()

            page.close()
            renderer.close()
            parcelFd.close()
            tempFile.delete()

            pngBytes
        } catch (e: Exception) {
            android.util.Log.e("PdfRenderer", "renderPdfPageToPng failed: $e")
            null
        }
    }

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
                            // v3.0.123: Dùng PackageInstaller.Session API thay vì Intent.ACTION_VIEW
                            // Đây là cách chính thống của Android cho in-app update.
                            // Ưu điểm:
                            // - Hệ thống tự xử lý self-update (không cần kill process)
                            // - Hoạt động đúng trên mọi thiết bị (Samsung, Pixel, Xiaomi...)
                            // - User thấy system install dialog chuẩn
                            // - Callback về BroadcastReceiver để xử lý success/failure
                            val packageInstaller = packageManager.packageInstaller
                            val sessionParams = PackageInstaller.SessionParams(
                                PackageInstaller.SessionParams.MODE_FULL_INSTALL
                            )
                            val sessionId = packageInstaller.createSession(sessionParams)
                            val session = packageInstaller.openSession(sessionId)
                            val totalSize = file.length()
                            session.openWrite("package", 0, totalSize).use { outputStream ->
                                file.inputStream().use { inputStream ->
                                    val buffer = ByteArray(65536)
                                    var read: Int
                                    while (inputStream.read(buffer).also { read = it } > 0) {
                                        outputStream.write(buffer, 0, read)
                                    }
                                }
                            }
                            // PendingIntent flags: cần FLAG_MUTABLE trên Android 12+ (API 31+)
                            val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                            } else {
                                PendingIntent.FLAG_UPDATE_CURRENT
                            }
                            val resultIntent = Intent(this, InstallResultReceiver::class.java)
                            val pendingIntent = PendingIntent.getBroadcast(
                                this, sessionId, resultIntent, piFlags
                            )
                            // Commit session - hệ thống sẽ show install dialog
                            session.commit(pendingIntent.intentSender)
                            session.close()
                            // v3.1.14: KHÔNG kill process/finish app nữa
                            // PackageInstaller.Session tự quản lý lifecycle - hệ thống sẽ
                            // tự close app khi user confirm install trong system dialog
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
                    "disconnectVpn" -> {
                        // v3.0.124: Stop OpenVPN service trước khi cài update
                        // Lý do: OpenVPN chạy foreground service → hệ thống coi app "in use"
                        //         → PackageInstaller từ chối cài đè với "App not installed"
                        //
                        // Thử 3 cách (best effort, không fail nếu cách nào không work):
                        // 1. Gọi openvpn_flutter method channel "disconnect" (Flutter side stops service)
                        // 2. am.killBackgroundProcesses(packageName) - kill background processes
                        // 3. sendBroadcast(de.blinkt.openvpn.DISCONNECT) - fallback broadcast
                        try {
                            // Cách 1: Gọi openvpn_flutter method channel
                            val openVpnChannel = MethodChannel(
                                flutterEngine.dartExecutor.binaryMessenger,
                                "id.laskarmedia.openvpn_flutter"
                            )
                            try {
                                openVpnChannel.invokeMethod("disconnect", null)
                            } catch (e: Exception) {
                                android.util.Log.w("HISMobile", "openvpn method channel disconnect failed: $e")
                            }
                            // Cách 2: Kill background processes
                            try {
                                val am = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                                am.killBackgroundProcesses(packageName)
                            } catch (e: Exception) {
                                android.util.Log.w("HISMobile", "killBackgroundProcesses failed: $e")
                            }
                            // Cách 3: Broadcast intent tới OpenVPN service
                            try {
                                sendBroadcast(Intent("de.blinkt.openvpn.DISCONNECT"))
                            } catch (e: Exception) {
                                android.util.Log.w("HISMobile", "broadcast disconnect failed: $e")
                            }
                            // v3.0.156: Use Handler.postDelayed instead of Thread.sleep to avoid blocking UI thread
                            Handler(Looper.getMainLooper()).postDelayed({
                                try { result.success(true) } catch (_: Exception) {}
                            }, 2000)
                        } catch (e: Exception) {
                            android.util.Log.e("HISMobile", "disconnectVpn fatal error: $e")
                            result.success(false)  // Best effort - không fail update
                        }
                    }
                    "saveApkToDownloads" -> {
                        // v3.0.122: Copy APK từ internal storage vào thư mục Download public
                        // Android 10+ (API 29+): MediaStore.Downloads (scoped storage, no permission)
                        // Android 9- (API <29): Direct file write to Environment.DIRECTORY_DOWNLOADS
                        //   cần WRITE_EXTERNAL_STORAGE permission
                        val srcPath = call.argument<String>("path")
                        val displayName = call.argument<String>("displayName")
                        if (srcPath == null || displayName == null) {
                            result.error("INVALID_ARGS", "path and displayName are required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val srcFile = File(srcPath)
                            if (!srcFile.exists()) {
                                result.error("FILE_NOT_FOUND", "APK not found: $srcPath", null)
                                return@setMethodCallHandler
                            }
                            val publicUri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                // Android 10+ - MediaStore.Downloads API
                                val contentValues = ContentValues().apply {
                                    put(MediaStore.Downloads.DISPLAY_NAME, displayName)
                                    put(MediaStore.Downloads.MIME_TYPE, "application/vnd.android.package-archive")
                                    put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/HisMobile")
                                    put(MediaStore.Downloads.IS_PENDING, 1)
                                }
                                val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                                val uri = contentResolver.insert(collection, contentValues)
                                if (uri == null) {
                                    result.error("MEDIASTORE_FAILED", "Insert returned null", null)
                                    return@setMethodCallHandler
                                }
                                contentResolver.openOutputStream(uri)?.use { outputStream ->
                                    srcFile.inputStream().use { input ->
                                        input.copyTo(outputStream)
                                    }
                                }
                                contentValues.clear()
                                contentValues.put(MediaStore.Downloads.IS_PENDING, 0)
                                contentResolver.update(uri, contentValues, null, null)
                                uri
                            } else {
                                // Android 9- (API <29) - direct file write
                                @Suppress("DEPRECATION")
                                val destDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                                val hisDir = File(destDir, "HisMobile")
                                if (!hisDir.exists()) hisDir.mkdirs()
                                val destFile = File(hisDir, displayName)
                                srcFile.copyTo(destFile, overwrite = true)
                                Uri.fromFile(destFile)
                            }
                            val sizeBytes = srcFile.length()
                            // Trả về: đường dẫn user-friendly để hiển thị
                            val displayPath = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                "Download/HisMobile/$displayName"
                            } else {
                                "Download/HisMobile/$displayName"
                            }
                            result.success(mapOf(
                                "uri" to publicUri.toString(),
                                "path" to displayPath,
                                "size" to sizeBytes
                            ))
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, e.stackTrace.toString())
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // v3.0.145: PdfRenderer channel - render PDF bytes to PNG using Android native PdfRenderer
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PDF_RENDERER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "renderPdfPageToPng" -> {
                        val pdfBytes = call.argument<ByteArray>("pdfBytes")
                        val dpi = call.argument<Int>("dpi") ?: 150
                        val pageIndex = call.argument<Int>("pageIndex") ?: 0
                        if (pdfBytes == null) {
                            result.error("INVALID_ARGS", "pdfBytes is required", null)
                            return@setMethodCallHandler
                        }
                        val pngBytes = renderPdfPageToPng(pdfBytes, dpi, pageIndex)
                        if (pngBytes != null) {
                            result.success(pngBytes)
                        } else {
                            result.error("RENDER_FAILED", "Failed to render PDF page", null)
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
