# Changelog - HIS Mobile

## v3.0.99 (build 243) - 13/08/2026
**"Fix black screen auto-update v2: dùng FileProvider + app's documents dir"**

### 🐛 Bug fix: Black screen vẫn còn sau v3.0.97
**User báo (13/08/2026 07:20):** Bấm "ĐỒNG Ý" trong dialog update v3.0.97 → v3.0.98 → màn hình đen, app không phản hồi (vẫn lỗi y như v3.0.96).

**Root cause (v3.0.99):**
- Code cũ lưu APK vào `/storage/emulated/0/Download/HisMobile/` (hacky: `ext.parent.parent.parent`)
- Trên Android 11+ (API 30+) với scoped storage, app **KHÔNG CÓ quyền ghi** vào shared storage từ app context
- `Directory.create(recursive: true)` có thể fail, hoặc `Dio.download()` throw Permission denied
- Exception bị nuốt trong try-catch → nhưng `context.mounted` false (vì context bị dispose) → black screen
- `OpenFilex.open()` với file không tồn tại cũng không có fallback

**Fix v3.0.99:**
- ✅ **Đổi download path** về `getApplicationDocumentsDirectory()` (app's own storage `/data/data/<pkg>/app_flutter/`, always writable, không cần permission)
- ✅ **Add FileProvider** trong AndroidManifest với authority `${applicationId}.fileprovider`
- ✅ **Tạo `res/xml/file_paths.xml`** với paths: files-path, cache-path, external-files-path, external-cache-path
- ✅ **Native MethodChannel** `his_mobile/installer` trong `MainActivity.kt`:
  - Dùng `FileProvider.getUriForFile()` cho Android 7+ (API 24+) - tạo content:// URI
  - Start `Intent.ACTION_VIEW` với `FLAG_GRANT_READ_URI_PERMISSION` để cho phép installer đọc
  - File < API 24 dùng `Uri.fromFile()` (file://)
- ✅ **Bỏ dependency `open_filex`** (không cần nữa - dùng native)
- ✅ **Capture `Navigator` + `ScaffoldMessenger` sớm** trước await để tránh `context.mounted` issue
- ✅ **Error handling**: nếu MethodChannel fail → SnackBar với path + Copy button

### 📁 Files sửa v3.0.99
- `lib/core/services/update_service.dart` - rewrite: app docs dir + MethodChannel install
- `android/app/src/main/AndroidManifest.xml` - thêm `<provider>` FileProvider
- `android/app/src/main/kotlin/.../MainActivity.kt` - thêm INSTALL_CHANNEL MethodChannel
- `android/app/src/main/res/xml/file_paths.xml` (NEW) - FileProvider paths
- `pubspec.yaml` - bỏ `open_filex`

---

## v3.0.98 (build 242) - 13/08/2026
**"Thêm Điều trị tăng/hạ Kali máu vào Tiện ích"**

### 🆕 Tính năng mới v3.0.98
- **Điều trị tăng Kali máu (Hyperkalemia)** - màn hình tham khảo protocol:
  - Mức độ nặng theo K+ máu (5.0 → > 7.0 mEq/L)
  - Bước 1: Ổn định tim (Calcium gluconate 10% IV)
  - Bước 2: Đẩy K+ vào tế bào (Insulin + Glucose)
  - Bước 3: Thải K+ ra ngoài (Kayexalate, lợi tiểu, lọc máu)
  - Theo dõi: EKG, K+ máu, đường huyết
- **Điều trị hạ Kali máu (Hypokalemia)** - màn hình tham khảo protocol:
  - Mức độ nặng theo K+ máu (3.5 → < 2.5 mEq/L)
  - Bước 1: Bổ sung đường uống (KCl viên)
  - Bước 2: Truyền tĩnh mạch (KCl 20-40 mEq/L)
  - Bước 3: Mục tiêu bù K+ (công thức tính)
  - Tìm nguyên nhân gốc
  - Tương tác thuốc (Salbutamol, Insulin, Digoxin)
- **2 tile mới** trong Tiện ích: "Tăng K+ máu" (đỏ) + "Hạ K+ máu" (xanh)

### 📁 Files sửa v3.0.98
- `lib/presentation/screens/tien_ich_screen.dart` - thêm 2 screen widget + 2 tile

---

## v3.0.97 (build 241) - 13/08/2026
**"Fix auto-update: black screen sau khi bấm Đồng ý"**

### 🐛 Bug fix: Black screen khi cập nhật
**vấn đề user báo (13/08/2026 02:55):** Bấm "Đồng Ý" trong dialog update → màn hình đen, app không phản hồi.

**Nguyên nhân:**
1. Thiếu `REQUEST_INSTALL_PACKAGES` permission trong AndroidManifest
2. APK được tải về `/tmp` (app sandbox) - user không thấy, dễ mất
3. `OpenFilex.open()` thất bại thì không có fallback nào
4. Không có error message rõ ràng nếu install fail

**Fix v3.0.97:**
- ✅ Thêm `android.permission.REQUEST_INSTALL_PACKAGES` vào AndroidManifest
- ✅ Thêm `<queries>` cho `ACTION_INSTALL_PACKAGE` (Android 11+ package visibility)
- ✅ Save APK vào `Downloads/HisMobile/HIS_MOBILE_v{version}.apk` (external storage, user thấy được)
- ✅ Show progress dialog với file path + size để debug
- ✅ Fallback chain: OpenFilex → launchUrl → MethodChannel → manual instructions
- ✅ Nếu tất cả fail → show dialog "Mở thủ công" với path + hướng dẫn mở Files app
- ✅ Copy path vào clipboard nếu cần

### 📁 Files sửa v3.0.97
- `android/app/src/main/AndroidManifest.xml` - thêm permission + queries
- `lib/core/services/update_service.dart` - rewrite download + install flow

---

## v3.0.96 (build 240) - 13/08/2026
**"Mã hóa tất cả credentials - XÓA plaintext trong source"**

### 🔒 Bảo mật: Credentials XOR-encoded
**vấn đề:** Trước v3.0.96, code có nhiều chỗ hardcoded credentials (333, 333, admin/333) - ai grep code hay extract từ APK đều thấy.

**Fix v3.0.96:**
- Tạo `lib/core/security/credentials.dart` - XOR + Base64 encoded
- Xóa tất cả plaintext credentials khỏi code (5 files, 10+ chỗ)
- Helper `Credentials.encode()` để regenerate khi cần rotate key

**Đã sửa:**
- `vpn_benh_vien_service.dart` - VPN password (333)
- `y_te_so_service.dart` - Y Tế Số password
- `thongke_auth_service.dart` - 4 chỗ (fetchPatientsPublic + 3 catalog + login form)
- `api_debug_service.dart` - Debug Y Tế Số password
- `catalog_browser_screen.dart` - 2 chỗ public API credentials
- `his_webview_screen.dart` - Auto-fill Thongke login form
- `patient_list_by_room_screen.dart` - Fallback 'admin' → ''

**Verify:** `grep "333|'333'" lib/` → 0 hits trong code (chỉ còn encoded trong credentials.dart)

⚠️ **Lưu ý:** XOR với key cố định chỉ là obfuscation nhẹ, KHÔNG phải encryption. Để bảo mật thật sự → dùng Android Keystore hoặc fetch từ server.

---

## v3.0.94 (build 238) - 13/08/2026
**"Bỏ EmrScanApp + Auto-update từ GitHub + VPN auto-disconnect"**

### 🗑️ Bỏ EmrScanApp (rườm rà)
- Xóa `emr_scan_config_screen.dart` + `emr_scan_token_service.dart`
- Bỏ menu "EmrScanApp Token Service" trong Settings
- Bỏ nút 🛰️ 1-chạm ở Lịch sử điều trị patient header
- Bỏ dòng "Nguồn token" ở header
- Bỏ nút "Lấy từ EmrScanApp" trong dialog paste token
- Giữ HIS Proxy + paste tay (đơn giản, đủ dùng)

### 🆕 Tính năng mới v3.0.94
- **Auto-update từ GitHub** (`UpdateService`):
  - Settings → Kiểm tra cập nhật → gọi `https://raw.githubusercontent.com/drkrongnem86-del/his_mobile/main/version.json`
  - So sánh version → nếu mới hơn hiện dialog
  - Bấm Đồng ý → tải APK → mở installer Android
  - File `version.json` ở repo root
- **VPN bệnh viện - cải tiến**:
  - Ẩn password cho account mặc định `333` (không có con mắt, không edit)
  - Mục "Tài khoản khác" riêng để nhập user + pass
  - Bỏ dòng "Mặc định: 333 / 333" (lộ pass)
  - **Auto-disconnect VPN 5 phút** khi app ở background (thoát/thu gọn)
  - Banner countdown "Sẽ tự ngắt sau Xs" (mở lại app để hủy)
- **Y tế số - Xem bệnh án**: bỏ badge "Bộ Y tế • 50+ API" (rườm rà)
- **Y TẾ SỐ (BỘ Y TẾ)**: bỏ mục "Bệnh án" (đã có ở patient actions sheet - dư)
  - Cập nhật count + URL info trong home screen
- **Cấu hình HIS - dọn dẹp**:
  - Bỏ mục "Thongke public (7 endpoints)" collapsible (rườm rà)
  - Sửa link preset "Public VPN" BVBM = `http://113.163.187.3:3000` (public IP thay vì cũ)
  - Test kết nối bỏ check "Thongke" (chỉ còn BVBM/EMR/MOS)
- **Debug API Response** (Settings):
  - Test cả **Y Tế Số public** (POST /v1/auth/login + GET /v1/medical-record/document-types)
  - Test **HIS Pro 1408** (GET /api/HisTreatment/GetView)
  - Hiển thị field name thật từ response (copy gửi dev)

### 🔧 Workflow
1. **Update check**: Cài v3.0.94 → lần sau vào Settings → "Kiểm tra cập nhật" → tự động check GitHub
2. **VPN 5 phút**: Bấm Kết nối → dùng → thoát app → 5 phút sau tự ngắt (tránh tốn pin)
3. **Y tế số**: tab BN → "Y tế số - Xem bệnh án" (vào thẳng) HOẶC mở Drawer → "Y tế số" (grid 19 chức năng, bỏ Bệnh án)

### 📁 Files sửa v3.0.94
- **Mới**: `lib/core/services/update_service.dart`, `version.json`
- **Xóa**: `lib/data/services/emr_scan_token_service.dart`, `lib/presentation/screens/emr_scan_config_screen.dart`
- **Sửa**:
  - `lib/core/services/vpn_benh_vien_service.dart` - thêm `onAppPaused/Resumed` + `setAutoDisconnectMinutes`
  - `lib/core/services/his_config_service.dart` - sửa link preset Public VPN BVBM
  - `lib/core/services/api_debug_service.dart` - test cả Y Tế Số + HIS Pro
  - `lib/presentation/screens/settings_screen.dart` - dùng `UpdateService`
  - `lib/presentation/screens/vpn_benh_vien_screen.dart` - rewrite form + auto-disconnect
  - `lib/presentation/screens/his_config_screen.dart` - bỏ Thongke public section
  - `lib/presentation/screens/treatment_history_screen.dart` - bỏ EmrScanApp UI
  - `lib/presentation/screens/y_te_so_home_screen.dart` - count + URL info
  - `lib/presentation/widgets/patient_actions_sheet.dart` - bỏ badge 50+ API
  - `lib/data/api/thongke_auth_service.dart` - bỏ `_kSrcEmrScan`
  - `lib/data/models/y_te_so_feature.dart` - bỏ 'Bệnh án' item
  - `lib/data/models/y_te_so_router.dart` - bỏ route 'benh_an'
  - `lib/data/api/y_te_so_service.dart` - dùng YTeSoService (đã có)
  - `pubspec.yaml` - thêm `open_filex: ^4.5.0`

---

## v3.0.93 (build 237) - 12/08/2026
**"Tích hợp EmrScanApp auto-token service (port 18080) vào Lịch sử điều trị"**

### 🆕 Tính năng mới v3.0.93
- **Tích hợp EmrScanApp Windows service** (Python HTTP trên port 18080):
  - Service tự động login + refresh HIS Pro token mỗi 5 phút (gọi HISLoginTool.exe chuẩn HIS)
  - HIS Mobile gọi `GET /token` hoặc `GET /login?user=X&pass=Y` để lấy token về dùng
  - **Tốt hơn HIS Proxy** (đọc log file) vì auto-refresh, không bị miss khi HIS restart
- **Token source tracking** trong `ThongkeAuthService`:
  - Lưu source khi set token: `emrscan` / `hisproxy` / `manual` / `file` / `embedded`
  - 3 method mới: `getTokenSource()`, `getTokenSourceText()` ("EmrScanApp" / "HIS Proxy" / "Thủ công"), `getTokenSourceIcon()` ("🛰️" / "🖥️" / "✋" / "📁" / "🔒")
  - `setHisProToken(token, {source = 'manual'})` - thêm param optional
  - `loadHisProToken()` tự set source cho legacy data
- **Cấu hình EmrScanApp trong Settings** (màn hình mới `EmrScanConfigScreen`):
  - Sửa URL service (default: `http://172.16.200.109:18080`)
  - **Test kết nối** (ping `/health` - hiển thị có token sẵn không)
  - **Lấy token** (GET `/token` - lưu vào ThongkeAuthService)
  - **Force login** (GET `/login?user=X&pass=Y` - dùng khi service chưa có token)
  - Hiển thị trạng thái real-time: URL, user, tên, hết hạn, refresh lần cuối, còn lại
  - Hướng dẫn cài đặt service trên máy BV
- **Lịch sử điều trị - Patient header cải tiến**:
  - **Nút 1-chạm 🛰️** ở header: bấm → auto-fetch token từ EmrScanApp (không cần mở dialog)
  - **Hiển thị nguồn token**: "🛰️ Nguồn token: EmrScanApp" / "🖥️ HIS Proxy" / "✋ Thủ công"
  - Tự reload data nếu trước đó lỗi 401
- **Dialog paste token** (khi 401): thêm 2 nút "Lấy từ EmrScanApp" + "Lấy từ HIS Proxy" (v3.0.93)

### 📁 Files mới / sửa v3.0.93
- **Mới**: `lib/data/services/emr_scan_token_service.dart` (250 dòng)
  - `EmrScanTokenInfo` class (reachable, hasToken, token, user, userName, expireTime, lastRefresh, error, pcUrl)
  - `EmrScanTokenService` singleton với `ping()`, `fetchAndSaveToken()`, `forceLogin()`
  - Lưu `emrscan_service_url` + `emrscan_last_fetch` vào SharedPreferences
- **Mới**: `lib/presentation/screens/emr_scan_config_screen.dart` (~480 dòng)
- **Sửa**: `lib/data/api/thongke_auth_service.dart` - thêm source tracking
- **Sửa**: `lib/data/services/his_proxy_token_service.dart` - set source = 'hisproxy'
- **Sửa**: `lib/data/services/emr_scan_token_service.dart` - set source = 'emrscan'
- **Sửa**: `lib/presentation/screens/settings_screen.dart` - thêm menu "EmrScanApp Token Service"
- **Sửa**: `lib/presentation/screens/treatment_history_screen.dart` - nút 1-chạm + source display

### 🔧 Workflow đề xuất
1. **Trên PC BV (1 lần)**: Cài EmrScanApp Windows service → auto login + refresh mỗi 5 phút
2. **Trên phone**: Mở Settings → EmrScanApp Token Service → nhập URL → Test kết nối → Lấy token
3. **Hàng ngày**: Mở app → vào Lịch sử điều trị → bấm 🛰️ nếu cần refresh token

---

## v3.0.87 (build 231) - 11/08/2026
**"Y tế số UI match XemBenhAn + Performance + Time filter"**

### 🐛 Bug fix - Load nhanh hơn
**Vấn đề user feedback (11/08/2026 12:50):** Login lâu, "Xem bệnh án" load lâu, có thể stuck vòng loading vô tận. Nguyên nhân:
1. Login screen chạy HIS Pro auto-fetch + Y Tế Số login **tuần tự** → tổng thời gian = t1 + t2 + t3
2. YTeSoScreen **auto-select phiếu đầu** khi vào → trigger download ngay (1-2s/phiếu) trước khi user thấy list
3. YTeSoService **không cache JWT expiry** → mỗi request kèm `Authorization` hết hạn → 401 → retry → chậm gấp đôi
4. YTeSoService **không dedup login** → mở 2 screen cùng lúc → 2 login song song
5. YTeSoService **cache vô thời hạn** → nếu data đổi, user phải tự refresh

**Fix v3.0.87:**
- `login_screen.dart`: chạy HIS Pro + Y Tế Số **song song** với `Future.wait()` → tiết kiệm ~3-5s
- `YTeSoService`:
  - Parse **JWT expiry** từ `payload.exp` → tránh gọi API với token hết hạn
  - **Dedup login** - nếu 1 login đang chạy thì return future đó (nhiều screen có thể share)
  - **TTL cache** 5 phút cho `listDocuments` - không gọi lại nếu đã cache < 5 phút
  - **Giảm timeout**: 15s → 8s connect, 30s → 20s receive
  - **HTTP keep-alive** header
- `YTeSoScreen`:
  - **Lazy load**: KHÔNG auto-select phiếu đầu - user phải click → mới download
  - Show "Chọn 1 phiếu bên trái để xem" placeholder
  - Có nút **"Tải hết"** ở header list → fire-and-forget download all parallel

### 🆕 Tính năng mới v3.0.87
- **YTeSoScreen - UI match XemBenhAn** (theo feedback user ảnh 7):
  - Header xanh navy + patient name + treatmentCode
  - **List trái với folder-style sub-groups** (icon folder + count badge, indigo theme)
  - **Items có check xanh nếu signed** + spinner nếu đang load
  - **Background xanh nhạt** cho phiếu đang chọn (isSelected)
  - **PDF viewer phải với 4 nút tròn** (fullscreen, download, print, share) - thêm nút Print mới
  - **Note input + save dưới list** ("Ghi chú nhanh cho phiếu này...")
  - **"Phiếu (N) ← vuốt"** header
  - Bottom: "N nhóm • N phiếu • ⏳ M • ✓ K/N"
- **DepartmentPatientPage - Time filter** (giống Hồ sơ điều trị):
  - Thêm **chips Thời gian**: Hôm nay / 7 ngày / 30 ngày / 90 ngày
  - Tách riêng **Trạng thái** (Tất cả / Đang ĐT / Đã XV)
  - Bấm chips → tự động reload

### 🔧 Sửa đổi
- `pubspec.yaml`: version 3.0.87+231
- `lib/data/api/y_te_so_service.dart`:
  - Thêm `_loginInProgress` dedup
  - Thêm `_tokenExpiresAt` parse JWT
  - Thêm `_docCacheTime` TTL 5 phút
  - `_ensureInit` giảm timeout
- `lib/presentation/screens/y_te_so_screen.dart`: rewrite UI match XemBenhAn
- `lib/modules/auth/auth/presentation/screens/login_screen.dart`: parallel Future.wait
- `lib/presentation/screens/department_patients_screen.dart`: thêm time filter chips

## v3.0.86 (build 230) - 11/08/2026
**"Y tế số split-view 40/60 + DepartmentPatientPage status filter + YTeScreen 19 mục"**

**"Y tế số split-view + Fix body API + Đơn giản hóa filter"**

### 🐛 Bug fix - API Y tế số body chuẩn
Test với curl thực tế từ PC (qua public 113.163.187.3:3000), phát hiện server yêu cầu body khác log PLogger:
- `danh-sach-khoa-quan-ly` body `{USERNAME}` (KHÔNG phải `{DEPARTMENT_ID}`)
- `buong-benh` body `{USERNAME, DEPARTMENT_ID}` (cần cả 2)
- `benh-nhan-buong-benh` body thêm `USERNAME`
- `benh-nhan-buong-benh-is-show` cần `TREATMENT_IDs` không empty
- `patient-info` body `{MADT}` (KHÔNG phải `{USERNAME}`)

### 🆕 Tính năng mới v3.0.85
- **YTeSoScreen - Split view giống XemBenhAn**:
  - Layout responsive: width >= 600 → split 40/60 (list trái + viewer phải)
  - Auto-select phiếu đầu tiên, auto-load bytes
  - Header viewer: tên phiếu + code + nút fullscreen + prev/next + counter
  - Tap phiếu → load + hiển thị ngay
- **YTeScreen - Menu chức năng cho BN hiện tại**:
  - 7 chức năng (giảm từ 18), mỗi mục tap mở list screen riêng
  - Mỗi chức năng auto-dùng BN hiện tại (treatmentCode, treatmentId, deptCode)
  - Bỏ các API không liên quan đến BN (DS khoa, info user, ...)
  - List screen hiển thị card đẹp với field extractor + JSON view + copy
- **YTeSoListScreen mới - Generic list screen**:
  - Hiển thị list đẹp từ API Y tế số
  - Mỗi item là card với title, subtitle, các field
  - Tap card → xem JSON detail
  - Nút "JSON" trên header → xem raw response

### 🔧 Sửa đổi
- `pubspec.yaml`: version 3.0.85+229
- `lib/data/api/y_te_so_extended_service.dart`:
  - Fix body cho từng API method (theo test thực tế)
  - Auto-pass `treatment-id` header từ query/body
  - Auto-pass `room-id`/`room-code`/`department-id`/`department-code` (từ defaults)
- `lib/presentation/screens/y_te_screen.dart`: refactor thành menu 7 chức năng
- `lib/presentation/screens/y_te_so_screen.dart`: thêm split-view + auto-load
- `lib/presentation/widgets/patient_actions_sheet.dart`:
  - `_openYTe` truyền context BN (treatmentCode, treatmentId, ...)
  - Lấy treatmentId từ `_g('TDL_TREATMENT_ID', 'TDL_TREATMENT_ID', 'ID')`

### 🆕 Files mới
- `lib/presentation/screens/y_te_so_list_screen.dart` (11 KB) - Generic list screen
  - Hiển thị list API với card + JSON viewer + copy
  - Pull to refresh, empty state, error state

### 🔧 Đơn giản hóa - DepartmentPatientPage
- Bỏ 3 filter cũ: Treatment Type (Tất cả/Chưa khám/Đang khám), Treatment Type Name (Khám bệnh/Điều trị...), Room chips
- Chỉ giữ date filter (Hôm nay/7 ngày/30 ngày/90 ngày) + search
- Filter giống "Hồ sơ điều trị" (Treatment History) - đơn giản, chỉ theo ngày

## v3.0.84 (build 228) - 11/08/2026
**"Fix Xem bệnh án swipe + Login đồng bộ + Chức năng Y tế 18 API"**

### 🐛 Bug fix
- **Xem bệnh án fullscreen**: nút `< >` không đồng bộ với vuốt
  - Root cause: `_goToDoc()` chỉ `setState(_selected)` mà không animate `PageController`
  - Fix: thêm `_pageController` instance, `_goToDoc()` dùng `animateToPage()` để sync
  - Bonus: load docBytes cho phiếu mới khi navigate bằng nút (trước chỉ khi swipe)

### 🔧 Cải tiến v3.0.84
- **Y tế số - Xem bệnh án**: bỏ login dialog / menu đăng nhập-đăng xuất-thông tin server
  - Login đồng bộ với main login flow (silent)
  - Không còn mục "Đăng nhập Y Tế Số" lẻ tẻ
- **YTeSoPdfViewerScreen mới**: PDF viewer với toolbar đầy đủ
  - Back, Title, Counter, `< >` page nav, Fullscreen, Download, Share
  - Download: lưu vào `/storage/emulated/0/Download`
  - Share: qua `Printing.sharePdf` (tương tự XemBenhAn)
  - Ảnh: `InteractiveViewer` với zoom
  - Fullscreen toggle: dùng `SystemUiMode.immersiveSticky`
- **YTeScreen mới - Chức năng Y tế (Bộ Y tế)**: 18 API tổng hợp
  - 5 tabs: Bệnh nhân | Y lệnh | Điều dưỡng | Vấn đề | Khác
  - Mỗi tab là grid icon, tap → gọi API → hiển thị JSON response đẹp
  - Hỗ trợ copy JSON ra clipboard
  - Auto-login qua YTeSoService (silent)

### 🆕 Files mới
- `lib/data/api/y_te_so_extended_service.dart` (10.7 KB) - 18 API methods:
  - BN: `danhSachKhoaQuanLy`, `buongBenh`, `benhNhanBuongBenh`, `benhNhanBuongBenhIsShow`, `patientInfo`
  - Y lệnh: `yLenhCanLamSang`, `yLenhCanLamSangDetail`, `yLenhCheckDownload`, `yLenhNhomDichVuCls`
  - Điều dưỡng: `danhSachDieuDuong`
  - Vấn đề: `vanDeChuyenMon`, `vanDeLuuY`
  - Báo cáo: `phieuBanGiao`, `taiLieuBn`, `countThietBi`
  - User: `userProfile`, `serverTime`
  - Work: `workInfo`, `dichVuKetQua`, `medicalInstruction`
  - Auto-retry 401 + auto-login
- `lib/presentation/screens/y_te_screen.dart` (19.6 KB) - Main screen với 5 tabs
- `lib/presentation/screens/y_te_so_pdf_viewer_screen.dart` (9.3 KB) - PDF viewer với toolbar

### 🔧 Sửa đổi
- `pubspec.yaml`: version 3.0.84+228
- `lib/presentation/screens/xem_benh_an_screen.dart`:
  - Thêm `_pageController` instance
  - Sửa `_goToDoc()` để animate + load bytes
  - Fix sync giữa nút < > và PageView swipe
- `lib/presentation/screens/y_te_so_screen.dart`:
  - Bỏ `_showLoginDialog`, `_logout`, `_showServerInfo`
  - Bỏ menu AppBar (chỉ giữ refresh)
  - Dùng `YTeSoPdfViewerScreen` mới thay vì `_PdfViewerScreen` inline
  - `_load()`: tự động silent login nếu thiếu token
- `lib/modules/auth/presentation/screens/login_screen.dart`:
  - Sau khi login HIS Mobile thành công, tự động gọi `YTeSoService.instance.login(email, pass)` (silent)
  - Lưu JWT vào SharedPref để dùng cho cả app
- `lib/presentation/widgets/patient_actions_sheet.dart`:
  - Thêm tile "Chức năng Y tế" (màu #455A64, icon apps)
  - Import `y_te_screen.dart`

### 📊 Tổng số API Y Tế Số đã tích hợp
- v3.0.83: 3 (auth + list + download)
- v3.0.84: +18 (mở rộng qua YTeScreen)
- Tổng: **21 API** sẵn sàng (từ 50+ đã khám phá)

## v3.0.83 (build 227) - 11/08/2026
**"Y tế số - Xem bệnh án native (Bộ Y tế)"**

### 🆕 Phát hiện lớn từ log Y Tế Số
- **Bộ Y tế có public API mở** tại `http://113.163.187.3:3000` (qua internet, KHÔNG cần VPN)
- Phát hiện qua PLogger curl logs trong logcat của `com.snd.adbc` ngày 11/08/2026
- **Dùng CHUNG tài khoản với thongke**: `333 / 333`
- Tổng cộng **50+ endpoints** đã thấy trong log (auth, medical-record, patient, y-lenh, dieu-duong, notifications, ...)

### 🆕 Tính năng mới - v3.0.83
- **Y tế số - Xem bệnh án native** thay thế "Mở trên EMR web" cũ:
  - **Auto-login** với default credentials (333/333)
  - **List documents theo nhóm** (DOCUMENT_TYPE: Phiếu CĐ, Phiếu khác, Bảng kê, ...)
  - **Tap để download + xem** PDF/ảnh bằng `syncfusion_flutter_pdfviewer` (đã có sẵn trong pubspec)
  - Hiển thị thông tin BN + khoa/phòng + mã ĐT
  - Refresh, logout, login lại, xem thông tin server

### 🆕 Files mới
- `lib/data/api/y_te_so_service.dart` (~20 KB) - Service chính:
  - `login()` - POST `/v1/auth/login` → JWT, lưu SharedPref
  - `listDocuments(treatmentCode)` - GET `/v1/medical-record/document-types?treatmentCode=XXX`
  - `downloadDocument(documentId)` - GET `/v1/medical-record/document-type/download?documentId=XXX` → decode base64 → file
  - Auto-retry khi 401 (re-login rồi retry)
  - Cache documents + file paths
- `lib/presentation/screens/y_te_so_screen.dart` (~22 KB) - Main UI:
  - Header BN + khoa/phòng
  - List grouped với ExpansionTile (mặc định expanded)
  - Document tile với icon (PDF/JPG), code, time, creator
  - Tap → dialog loading → download → PDF viewer fullscreen
  - AppBar: refresh + menu (login/logout/info)
  - Footer: "X nhóm • Y tài liệu" + token preview

### 🔧 Sửa đổi
- `pubspec.yaml`: version 3.0.83+227
- `lib/presentation/widgets/patient_actions_sheet.dart`:
  - **Bỏ tile "Mở trên EMR web" cũ** (EmrWebViewScreen)
  - **Thêm tile "Y tế số - Xem bệnh án"** (màu teal #00838F)
  - Bỏ import `emr_web_view_screen.dart`
  - Thêm import `y_te_so_screen.dart`
  - Method `_openEmrWeb()` → `_openYTeSo()`
  - Method `_emrWebTile()` → `_yTeSoTile()`

### 📋 Endpoints Y Tế Số đã tích hợp (3/50+)
| Method | Path | Mục đích |
|--------|------|----------|
| POST | `/v1/auth/login` | Đăng nhập → JWT |
| GET | `/v1/medical-record/document-types?treatmentCode=XXX` | List documents grouped |
| GET | `/v1/medical-record/document-type/download?documentId=XXX` | Download file (JSON Base64) |

### 📋 Endpoints đã biết (chưa tích hợp, sẵn sàng mở rộng)
| Method | Path | Mục đích |
|--------|------|----------|
| GET | `/v1/medical-record/emr-document/{id}` | Chi tiết document |
| POST | `/v1/patient/danh-sach-khoa-quan-ly` | DS khoa quản lý |
| POST | `/v1/patient/buong-benh` | Buồng bệnh |
| POST | `/v1/patient/benh-nhan-buong-benh` | BN buồng bệnh |
| POST | `/v1/patient/info` | Thông tin BN |
| GET | `/v1/y-lenh-can-lam-sang?TREATMENT_ID=...` | Y lệnh Cận LS |
| GET | `/v1/y-lenh-can-lam-sang/{id}` | Chi tiết y lệnh |
| POST | `/v1/y-lenh-can-lam-sang/check-download` | Check download |
| POST | `/v1/dieu-duong/danh-sach-dieu-duong` | DS điều dưỡng |
| GET | `/v1/chi-dinh/common/workInfo/{roomId}` | WorkInfo phòng |
| GET | `/v1/dich-vu-ket-qua` | Dịch vụ kết quả |
| GET | `/v1/medical-instruction` | Y lệnh thuốc |
| GET | `/v1/van-de-chuyen-mon` | Vấn đề chuyên môn |
| GET | `/v1/van-de-luu-y` | Vấn đề lưu ý |
| GET | `/v1/phieu-ban-giao/danh-sach-phieu` | Phiếu bàn giao |
| GET | `/v1/tai-lieu-bn/danh-sach-tai-lieu` | Tài liệu BN |
| GET | `/v1/thiet-bi-y-te/count-thiet-bi-bn/{id}` | Đếm thiết bị Y tế |
| GET | `/v1/users/profile` | User profile |
| GET | `/v1/users/server-time` | Server time |
| GET | `/v1/config/benh-vien/bvdk.ninhthuan` | Config BV |
| GET | `/v1/open/get-config-app` | App config |
| GET | `/v1/health` | Health check |
| POST | `/v1/notifications/update-device-and-last-active-department-code` | Device push |
| GET | `/v1/notifications/notification-status` | Notification status |

### 🧪 Test đã verify
- ✓ POST /v1/auth/login → JWT 581 chars
- ✓ GET /v1/medical-record/document-types?treatmentCode=000002164424 (MẤU THỊ DI)
  → 50+ docs grouped theo type (21, 20, 28, ...)
- ✓ GET /v1/medical-record/document-type/download?documentId=34023044
  → JSON {Base64Data: 421840 chars} → decode → PDF 316 KB hợp lệ
- Test file: `tools/yte_so_log/test_decoded.pdf`

### 🔑 Credentials
- Y Tế Số public: `333` / `333` (giống thongke)
- Base URL: `http://113.163.187.3:3000` (qua internet) hoặc `http://172.16.1.12:3000` (qua VPN LAN)
- User-id mặc định: `958e768e-61c6-4fed-81f7-525a6ca38263` (có thể cần login lại nếu server rotate)

## v3.0.82 (build 226) - 10/08/2026
**"Auto-refresh HIS Pro token + WebView EMR công khai"**

### 🆕 New features
- **`his_proxy_server.py`** - Python server chạy trên PC (port 9999), stdlib only:
  - `GET /get-his-token` - Đọc `D:\Soft\HISPRO_THAT\Logs\LogSystem.txt`, extract Bearer token từ `___dti:"...|<TOKEN>|..."` mới nhất
  - `GET /get-his-token-status` - Trả về {token, length, age_seconds, source_file}
  - `GET /proxy/{port}/{api_path}` - Forward tới HIS Pro LAN + auto-inject Bearer token (vd `/proxy/1408/api/HisTreatment/GetLView`)
  - `GET /ping` - Health check
  - `GET /` - Status page HTML
- **`lib/data/services/his_proxy_token_service.dart`** - App gọi proxy:
  - `fetchAndSaveToken()` - GET /get-his-token → lưu vào `ThongkeAuthService`
  - `getStatus()` - GET /get-his-token-status → trả về thông tin token
  - `ping()` - check proxy reachable
  - `getProxyUrl()` / `setProxyUrl()` - cấu hình URL proxy (default `http://172.16.200.109:9999`)
  - `autoFetchEnabled` - bật/tắt auto-refresh
- **Auto-fetch token khi 401**: `TreatmentHistoryService._get` retry 1 lần sau khi auto-fetch token từ proxy
- **Nút "Lấy tự động" trong dialog token**: gọi proxy, 1-click lấy token mới
- **Hiển thị token status trong header**: "🔑 Có token" / "🔒 No token"
- **`EmrWebViewScreen`** - Hiển thị EMR công khai inline (thay vì external browser):
  - URL bar, back/forward/reload buttons
  - Progress indicator
  - Mở trong Chrome button
  - Hiển thị tên BN + mã ĐT trên AppBar
- **"Mở trên EMR web" mở webview inline** thay vì Chrome ngoài (VPN OFF)

### Setup (1 lần trên PC)
1. Mở PowerShell trên PC
2. `cd C:\Users\Nem\Desktop\his_mobile-fresh\tools`
3. `python his_proxy_server.py`
4. PC IP hiện ra (vd 172.16.200.109) → phone tự động detect
5. Phone cùng WiFi → tự động lấy token mới mỗi khi 401

### Files
- **NEW** `tools/his_proxy_server.py` (15.9 KB) - Python stdlib only
- **NEW** `lib/data/services/his_proxy_token_service.dart` (6.7 KB)
- **NEW** `lib/presentation/screens/emr_web_view_screen.dart` (6.7 KB)
- **MOD** `lib/data/api/treatment_history_service.dart` - auto-fetch on 401
- **MOD** `lib/presentation/screens/treatment_history_screen.dart` - "Lấy tự động" button + token indicator
- **MOD** `lib/presentation/widgets/patient_actions_sheet.dart` - "Mở trên EMR web" dùng webview
- **MOD** `pubspec.yaml` (3.0.81+225 → 3.0.82+226)

### Test verify (10/08/2026 12:59)
- Proxy: `GET /get-his-token` → 200, token `d856353f...edb6` (64 hex, source=`D:\Soft\HISPRO_THAT\Logs\LogSystem.txt`)
- Proxy forward: `GET /proxy/1408/api/HisTreatment/GetLView` (no auth) → 200, auto-inject token, 1 lần khám PHẠM THẾ DŨNG K59.0

---

## v3.0.81 (build 225) - 10/08/2026
**"Đính kèm tài liệu - thêm Lưu ký"**

### 🆕 New features
- **Nút "Lưu ký" trong Đính kèm tài liệu** (cạnh nút "Lưu"):
  - User vẽ chữ ký tay trên dialog (giống Scan phiếu)
  - Chữ ký overlay góc dưới phải PDF + tên user
  - Push qua `EmrPushService.pushSignedPdfToEmr` (IsFinishSign=true, IsSignElectronic=true, SignedImageData=base64PDF)
  - Workflow giống HIS desktop "Đính kèm → Ký" (theo note2)
  - Có thể "Ký lại" nếu chưa ưng
- **Helper `SmartCaService.convertImageToPdf` mở rộng**: nhận `signaturePath` optional → embed chữ ký + text "Đã ký: <tên user>" vào PDF
- **API từ 2 → 1 method duy nhất** `AttachDocumentService.attachFile(signaturePath: ...)`:
  - `signaturePath=null` → IsFinishSign=false (đẩy unsigned)
  - `signaturePath=path` → IsFinishSign=true (đẩy signed, đã embed chữ ký vào PDF)

### Files
- **MOD** `lib/data/services/smart_ca_service.dart` - `convertImageToPdf` thêm `signaturePath` param, embed chữ ký vào PDF
- **MOD** `lib/data/api/attach_document_service.dart` - `attachFile(signaturePath:)` route đến `pushSignedPdfToEmr` nếu có signature
- **MOD** `lib/presentation/screens/attach_document_screen.dart` - thêm `SignatureController`, dialog capture chữ ký, nút "Lưu ký" + "Ký lại"
- **MOD** `pubspec.yaml` (3.0.80+224 → 3.0.81+225)

### Test
- Cùng BN 000002164424 MẤU THỊ DI:
  - "Lưu" → đẩy unsigned (giống v3.0.80, đã verify work)
  - "Lưu ký" → vẽ chữ ký → embed vào PDF → đẩy signed (IsFinishSign=true)
- Note2 user yêu cầu: "hãy tạo nút lưu là lưu chỉ đẩy lên EMR chưa ký và Lưu ký là lưu có ký" → ✅ DONE

---

## v3.0.80 (build 224) - 10/08/2026
**"Fix Đính kèm tài liệu - dùng CreateByTdo SDO đầy đủ"**

### 🔧 Fixes (quan trọng)
- **Fix "Đính kèm tài liệu" trả 500**: `api/EmrDocument/CreateWithFile` không tồn tại trên EMR server này (trả 500). Refactor sang dùng `api/EmrDocument/CreateByTdo` với SDO đầy đủ (giống `EmrPushService.pushPdfToEmrUnsigned` đã work).
  - SDO body phải có đủ ~30 trường: `DocumentName`, `DocumentTypeId`, `TreatmentCode`, `WorkingDepartmentName`, `DepartmentCode`, `RoomCode`, `RoomTypeCode`, `MediOrgCode="58001"`, `DocumentTime`, `OriginalVersion.Base64Data`, `Signs=[]`, `imageFile`, ...
  - **Test verify ngay 10/08/2026 11:30**: POST CreateByTdo với SDO đầy đủ → 200, DocumentCode `000034050535`, lưu vào `\\Upload\EMR\20260809\000002164424\25807441-0518-4581-9731-3747e157af5a.pdf` ✅
- **Flow mới**: `AttachDocumentService.attachFile()`
  1. Đọc file local (camera/gallery/PDF)
  2. Convert ảnh → PDF qua `SmartCaService.convertImageToPdf` (giữ nguyên nếu đã là PDF)
  3. Push qua `EmrPushService.pushPdfToEmrUnsigned(useFss=false)` → `CreateByTdo` với base64
- **Cải thiện error banner**: truncate lỗi dài (Dio verbose "validateStatus was configured to throw..."), thêm gợi ý kiểm tra VPN/token/HSCC.

### Files
- **REWRITE** `lib/data/api/attach_document_service.dart` (5.3 KB) - dùng `EmrPushService.pushPdfToEmrUnsigned` thay vì `CreateWithFile`
- **MOD** `lib/presentation/screens/attach_document_screen.dart` - bỏ `documentTypeCode` param, error banner thân thiện hơn
- **MOD** `pubspec.yaml` (3.0.79+223 → 3.0.80+224)

### Test
- **Patient 000002164424 MẤU THỊ DI** (Khoa Cấp Cứu)
  - Up 1 PDF test → DocumentCode 000034050535 → vào EMR BN ngon lành

---

## v3.0.79 (build 223) - 10/08/2026
**"Fix Lịch sử điều trị + Đính kèm tài liệu"**

### 🔧 Fixes (quan trọng)
- **Fix port HIS Pro: 1429 → 1408**: API `HisTreatment/GetLView`, `Get`, `HisDepartmentTran/GetView`, `HisServiceReq/Get`, `HisSereServ/GetDHisSereServ2` đều ở port **1408** (không phải 1429). Verify bằng test trực tiếp:
  - `http://172.16.9.6:1429/api/HisTreatment/GetLView` → **404** (sai)
  - `http://172.16.9.6:1408/api/HisTreatment/GetLView` → **200** (đúng)
  - Áp dụng cho cả `TreatmentHistoryService` và `ThongkeAuthService.hisProBaseUrl` (cũng dùng port 1408 thay vì mosUrl 1429). `fetchHisProIcd` trước đó cũng bị ảnh hưởng (gọi 1429 trả 404).
- **Pad mã BN thành 10 chữ số**: HIS Pro filter `PATIENT_CODE__EXACT` yêu cầu string với leading zeros (vd: `"0000475806"`, không phải `"475806"`). Helper `_normalizePatientCode()`.
- **Token mặc định đã hết hạn**: HIS Pro embedded token (VquHGS...) đã rotate. Thêm nút **"Cập nhật token"** trong error banner 401 → mở dialog paste token mới. Có sẵn nút **"Copy d856..."** để copy token mới từ log HIS.exe (line `___dti:"...|TOKEN|..."`).

### 🆕 New features
- **Tile "Đính kèm tài liệu"** trong thao tác BN (sau Lịch sử điều trị, màu teal):
  - Upload ảnh (chụp từ camera hoặc chọn từ thư viện) + PDF/doc lên EMR BN.
  - Gọi `POST /api/EmrDocument/CreateWithFile` (port 1417) với multipart FormData (file blob + sdo base64).
  - Form: chọn loại văn bản (20 loại phổ biến, default "20 - Phiếu khác"), tên VB, nhóm VB (optional).
  - Workflow giống HIS desktop "Chi tiết BA → Đính kèm" (theo note2.docx).
- **Dialog paste HIS Pro token** (treatment_history_screen.dart): paste 64-char hex token, app tự lưu và retry.

### Files
- **NEW** `lib/data/api/attach_document_service.dart` (5.9 KB) - `attachFile()` + `fetchDocumentTypes()`
- **NEW** `lib/presentation/screens/attach_document_screen.dart` (20 KB) - form + camera/gallery
- **MOD** `lib/data/api/treatment_history_service.dart` - port 1408 + `_normalizePatientCode` + better error messages
- **MOD** `lib/data/api/thongke_auth_service.dart` - `hisProBaseUrl` ép port 1408
- **MOD** `lib/presentation/screens/treatment_history_screen.dart` - "Cập nhật token" button + dialog paste
- **MOD** `lib/presentation/widgets/patient_actions_sheet.dart` - tile "Đính kèm tài liệu"
- **MOD** `pubspec.yaml` (3.0.78+222 → 3.0.79+223)

### Token workflow (sau khi BV rotate token)
1. Mở HIS desktop (hoặc PC) → check `D:\Soft\HISPRO_THAT\Logs\LogSystem.txt`
2. Ctrl+F `___dti:` → tìm dòng mới nhất, copy phần giữa dấu `|` thứ 3 và thứ 4 (vd: `d856353fbe6aa6a21d25083243558387e7487c0f4b8285fe1a92b3b99c6eedb6`)
3. Trong app: mở "Lịch sử điều trị" → banner đỏ "Token hết hạn" → ấn "Cập nhật token" → paste → Lưu

### Test data (đã verify 10/08/2026 10:52)
- **Patient 0000475806 PHẠM THỆ DŨNG** (1966, Nam)
  - 1 lần khám: 2026-08-10 09:46, ICD K59.0 (Táo bón), TreatmentCode 000002166010
  - Trước fix: API trả 404 (port 1429) → "BN chưa có lần khám" (sai)
  - Sau fix: API trả 200 + 1 record (đúng)

---

## v3.0.78 (build 222) - 10/08/2026
**"Lịch sử điều trị — giống HIS desktop"**

### Major changes
- **🆕 Tile "Lịch sử điều trị"** trong thao tác BN (cùng section "Xem bệnh án"):
  - Lấy tất cả các lần khám của BN từ HIS Pro (giống HIS desktop plugin `TreatmentHistory.dll`).
  - **3-pane layout**: trên = list lần khám, dưới trái = khoa điều trị, dưới phải = dịch vụ + thuốc.
  - Auto-load khi mở, click 1 lần khám → load khoa → click 1 khoa → load DV.
  - Nhóm DV theo `TDL_SERVICE_TYPE_NAME` (Thuốc, CLS, XN, CĐHA, Khám...).
  - Error banner thân thiện: "Token hết hạn — vào Cài đặt → EMR Sync", "Không kết nối được HIS Pro", "BN chưa có lần khám".

### API mới (HIS Pro, port 1408 — đã fix ở v3.0.79)
- `api/HisTreatment/GetLView` — list lần khám (filter `PATIENT_CODE__EXACT`, sort `MODIFY_TIME DESC`)
- `api/HisDepartmentTran/GetView` — khoa đã điều trị (filter `TREATMENT_ID`, sort `DEPARTMENT_IN_TIME ASC`)
- `api/HisServiceReq/Get` — y lệnh theo treatment (filter `TREATMENT_ID`)
- `api/HisSereServ/GetDHisSereServ2` — DV + thuốc theo khoa (filter `TREATMENT_ID`, `INTRUCTION_DATE`)
- `api/HisServiceReq/GetDynamic` — lấy SAMPLE_TIME/RECEIVE_SAMPLE_TIME (filter `IDs`, `ColumnParams`)

API flow đã verify qua log HIS.exe ngày 10/08 08:32-08:35 (`D:\Soft\HISPRO_THAT\Logs\LogSystem.txt`).


### Files
- **NEW** `lib/data/api/treatment_history_service.dart` (5 API methods + 1 helper)
- **NEW** `lib/presentation/screens/treatment_history_screen.dart` (3-pane UI)
- **MOD** `lib/presentation/widgets/patient_actions_sheet.dart` (+ tile "Lịch sử điều trị" + import + method)
- **MOD** `pubspec.yaml` (3.0.77+221 → 3.0.78+222)

### Requirements
- HIS Pro token còn hạn (`Settings → EMR Sync` nếu lỗi 401).
- VPN BV nội bộ (`VpnBenhVienService`) hoặc WiFi BV để tới 172.16.9.6:1429.

---

## v3.0.77 (build 221) - 10/08/2026
**"Giải lao - clean-up"**

### Major changes
- **Bỏ "Đăng nhập HIS Pro" dialog** (xóa 323 dòng code thủ công). App tự động dùng bearer token hardcode từ main.dart.
- **VPN Bệnh viện auto-disconnect** khi user thoát app (lifecycle observer trong main.dart).
- **Xem bệnh án swipe** đã fix — load docBytes khi swipe tới phiếu mới (trước đây chỉ loading spinner mãi).
- **Tiện ích "No response"** cải thiện — thử nhiều pattern CSRF, error message thân thiện hơn.
- **Default API = Public** khi mở app (trước đây mặc định HIS Pro).
- **Version sync** tất cả UI displays (settings, about, splash, drawer, marquee).

### Removed
- `_showHisProLoginDialog` method (322 lines)
- `_syncFromHisPro` method
- `_buildHisProSyncButton` widget
- `onSyncFromHisPro` prop on DepartmentPatientPage
- `PatientDataSource.appCode` + `seed` references (giờ empty state)
- PatientSeed fallback (4 paths)
- `HisProService.instance.isLoggedIn` checks in HomeScreen

### Files changed
- `pubspec.yaml` - bump 3.0.76+220 → 3.0.77+221
- `lib/main.dart` - WidgetsBindingObserver for VPN auto-disconnect
- `lib/presentation/screens/home_screen.dart` - removed 323 lines HIS Pro, default API=Public, empty state UI with VPN button
- `lib/presentation/screens/xem_benh_an_screen.dart` - fix PageView onPageChanged to load docBytes
- `lib/presentation/screens/catalog_browser_screen.dart` - friendlier error message
- `lib/data/api/thongke_auth_service.dart` - try 4 CSRF patterns + fallback no-CSRF

---

## v3.0.76 (build 220) - 10/08/2026
**"Native OpenVPN integration"**

- Added `openvpn_flutter: ^1.3.4` (wraps ics-openvpn - de.blinkt.openvpn)
- Native VPN client integrated into app (no more external OpenVPN Connect app needed)
- Bundled `libopenvpn.so` (3.7 MB) + `libgojni.so` (5 MB) for arm64-v8a
- AndroidManifest: BIND_VPN_SERVICE, FOREGROUND_SERVICE_*, POST_NOTIFICATIONS, extractNativeLibs=true
- `VpnBenhVienService` rewritten with real OpenVPN engine
- Default credentials: 333 / 333 (password masked as `*****` on UI)
- Splash screen fix: don't hang on "Kết nối HIS Pro..." when no VPN
- Removed PatientSeed fallback (4 paths → empty state)

---

## v3.0.75 (build 219) - 09/08/2026
**"Time filter + swipe"**

- Added `TrDateFilter` enum (today/week/month/year/custom) - HIS Pro desktop style
- Replaced "Loại ĐT" filter with time filter chips on HomeScreen
- Date range propagates to DepartmentPatientPage via `setDateRange()`
- Xem bệnh án fullscreen PageView with swipe + prev/next buttons
- 4 nav items (removed Báo cáo)
- Cleared `_selectedPatient` after patient action (bỏ always-on-top)

---

## v3.0.74 (build 218) - 09/08/2026
**"Hồ sơ + VPN Bệnh viện"**

- Added Hồ sơ điều trị menu (5th nav item)
- New `treatment_records_screen.dart` (38.7 KB) - copied from v3.0.64 source
- New `vpn_benh_vien_service.dart` (placeholder, real impl in v3.0.76)
- New `vpn_benh_vien_screen.dart` with credentials form
- VPN status indicator in AppBar (login + home)
- Default credentials: admin/333 → 333/333
- HomeScreen API simplified to 2 sources: HIS Pro + Public

---

## v3.0.63 (build 217) - 08/08/2026
Last v3.0.63 release with original PatientSeed fallback, all 4 nav items, full HIS Pro login flow.
