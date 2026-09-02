package com.drnem.ccdk.his_mobile

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.util.Log
import android.widget.Toast

/// v3.0.123: BroadcastReceiver nhận kết quả install từ PackageInstaller API
/// - STATUS_SUCCESS: cài thành công → toast thông báo + mở lại app (hoặc để user tự mở)
/// - STATUS_PENDING_USER_ACTION: user cần confirm (một số thiết bị)
/// - STATUS_FAILURE: cài lỗi → toast error message
class InstallResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -1)
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        val packageName = intent.getStringExtra(PackageInstaller.EXTRA_PACKAGE_NAME)
        Log.i("HISMobile", "InstallResultReceiver: status=$status, msg=$message, pkg=$packageName")
        when (status) {
            PackageInstaller.STATUS_SUCCESS -> {
                // Install thành công - hiển thị toast ngắn, user sẽ mở lại app thủ công
                Toast.makeText(context, "✅ Cập nhật thành công! Mở lại HIS MOBILE.", Toast.LENGTH_LONG).show()
            }
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                // Có một số thiết bị (Samsung) cần user confirm thêm
                @Suppress("DEPRECATION")
                val confirmation = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                if (confirmation != null) {
                    confirmation.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    try {
                        context.startActivity(confirmation)
                    } catch (e: Exception) {
                        Log.e("HISMobile", "Cannot start pending user action: $e")
                    }
                }
            }
            PackageInstaller.STATUS_FAILURE_ABORTED -> {
                Toast.makeText(context, "⚠️ Cài đặt bị huỷ.", Toast.LENGTH_SHORT).show()
            }
            PackageInstaller.STATUS_FAILURE_BLOCKED -> {
                Toast.makeText(context, "❌ Cài đặt bị chặn: $message", Toast.LENGTH_LONG).show()
            }
            PackageInstaller.STATUS_FAILURE_INVALID -> {
                Toast.makeText(context, "❌ APK không hợp lệ: $message", Toast.LENGTH_LONG).show()
            }
            PackageInstaller.STATUS_FAILURE_CONFLICT -> {
                Toast.makeText(context, "❌ Trùng package với app khác: $message", Toast.LENGTH_LONG).show()
            }
            PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> {
                Toast.makeText(context, "❌ Không tương thích: $message", Toast.LENGTH_LONG).show()
            }
            PackageInstaller.STATUS_FAILURE_STORAGE -> {
                Toast.makeText(context, "❌ Bộ nhớ đầy: $message", Toast.LENGTH_LONG).show()
            }
            else -> {
                if (status == PackageInstaller.STATUS_FAILURE) {
                    Toast.makeText(context, "❌ Cập nhật thất bại: $message", Toast.LENGTH_LONG).show()
                } else {
                    Log.w("HISMobile", "Install result: status=$status, msg=$message")
                }
            }
        }
    }
}
