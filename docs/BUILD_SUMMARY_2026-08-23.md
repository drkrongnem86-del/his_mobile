# HIS MOBILE - TỔNG KẾT NGÀY 23/08/2026

## Phiên bản: v3.0.164 → v3.0.168

5 bản build liên tiếp, tổng cộng 10+ bug fix + 5 tính năng mới.

---

## v3.0.164 - GỘP PHÒNG TỦ THUẬT + METHODS KẾT QUẢ CĐHA

### Tính năng mới
- **GỘP 2 tile phòng thành 1**: "Phòng tủ thuật HSCC (ECG + DSBN)" - room 36 (bỏ ID 9999)
- Thêm 5 methods API mới trong `HisApiService`:
  - `getSarReportResult()` - SAR port 1409 (Siêu âm/Xquang)
  - `getLisResult()` - LIS port 1419 (XN) với multi-endpoint fallback
  - `getSubclinicalResult()` - SubclinicalResult
  - `getServiceResultByType()` - auto-detect type → gọi API phù hợp
  - `getAllClsByTreatment()` - group kết quả theo loại CLS
- **Treatment History**: hiển thị kết quả Siêu âm, XN, ECG với format riêng
  - Xquang/Siêu âm: KẾT LUẬN + MÔ TẢ + GHI CHÚ + máy + KTV/BS đọc
  - XN (LIS): bảng chuyên nghiệp - Mã/Tên chỉ số/KQ/Đơn vị/Bình thường + flag H (high) / L (low)
- **ECG screen**: thêm nút 🔑 dán token HIS Pro trên AppBar

### Files thay đổi
- `lib/presentation/screens/tien_ich_screen.dart` - rename tile
- `lib/data/api/his_api_service.dart` - thêm 5 methods
- `lib/presentation/screens/treatment_history_screen.dart` - UI kết quả CLS
- `lib/presentation/screens/ecg_execute_screen.dart` - paste token

---

## v3.0.165 - TOKEN SYNC HUB (trung tâm quản lý token)

### Tính năng mới
- **Tạo `TokenSyncService`** (`lib/data/services/token_sync_service.dart`) - service trung tâm
  - Singleton, áp dụng cho TẤT CẢ services: `HisApiService` + `HisProApiService` (cả 2 class) + `ThongkeAuthService`
  - `BroadcastStream<TokenEvent>` - mọi screen subscribe được
  - Methods: `loadFromStorage()`, `setToken()`, `setManualToken()`, `autoFetchToken()`, `clearToken()`

- **Settings - TOKEN HIS PRO redesign**:
  - Hiển thị: `805953ca…8b724c575` (masked) + badge `hardcoded` + `2 phút trước` + 🕐 "cũ" nếu >1h
  - **🔄 Nút TỰ CẬP NHẬT** (xanh lá) - auto-fetch từ multi-source
  - **✏️ Nút Dán thủ công** - paste token từ log
  - **❓ Nút Help** - hướng dẫn lấy token

- **Procedure Room + ECG** - thêm nút 🔄 "Tự lấy token tự động" cạnh 🔑 Dán
- **main.dart bootstrap** - dùng TokenSyncService.loadFromStorage() + autoFetchToken()
- **Treatment History** - refactor dùng TokenSyncService

### Workflow: 5 nơi cần token → 1 source of truth
- Phòng tủ thuật (ECG + DSBN): 🔄 Auto + 🔑 Paste
- ECG: 🔄 Auto + 🔑 Paste
- Lịch sử điều trị: auto-fetch on init
- Cài đặt: 🔄 Auto + 🔑 Paste + trạng thái
- main.dart: loadFromStorage → autoFetch → fallback

---

## v3.0.166 - FIX CĐHA + TÊN BN CÓ DẤU

### Bug fix
- **Lỗi "Chưa hỗ trợ loại DV này" + HTTP 404**: Refactor `getServiceResultByType`:
  - LUÔN thử `getServiceReqResult` (HisSereServExt) TRƯỚC - work cho ECG/Xquang từ v3.0.162
  - SAR/LIS chỉ làm supplementary (thường 404 trên server này)
  - Auto-detect service type từ `SERVICE_NAME` khi type=0
  - Empty results → "Chưa có kết quả" thay vì lỗi đỏ

- **Tên BN không hiển thị đúng dấu** (Phòng tủ thuật):
  - **CRITICAL bug trong MojibakeFixer**: char `€` (U+20AC) > 255 bị skip khiến CP1252 roundtrip fail
  - Fix: thêm `_cp1252Byte()` helper map Unicode → CP1252 byte (€=0x80, Š=0x8A, ©=0xA9, etc.)
  - Test Python: 12/12 cases pass:
    - `Sáº¦M THá»Š THUYá»€N` → `SẦM THỊ THUYỀN` ✓
    - `NghÄ©a` → `Nghĩa` ✓
    - `Ä‘á»“` → `đồ` ✓
- `PatientNameHelper` mở rộng: thêm field từ Data 3000 (camelCase), Public 8080 (Laravel)

---

## v3.0.167 - PHÒNG TỦ THUẬT ĐÚNG 3 BN

### Bug fix
- **Procedure Room ưu tiên HIS Pro** trong fallback chain (trước đây user chọn gì thì API đó chạy trước, dẫn đến Data 3000 thắng khi HIS Pro chậm)
- **Default status filter** đổi từ `{1, 2, 3}` → `{1, 2}` (Chưa kết thúc) - match HIS Desktop
- Debug log chi tiết: `API chain: HIS Pro → Data 3000 → Public`

### Verify với data thật
- HIS Pro `GetLView` room 36 status [1, 2] + date 23/08/2026: **3 BN đúng như HIS Desktop**:
  1. BÁO KIỀU BẢO AN (mã 0000615737, DOB 2010) - type 4 (CĐHA)
  2. BÁO KIỀU BẢO AN (mã 0000615737) - type 11 (Khám ngoại trú)
  3. PHAN PHƯỚC KHÁNH (mã 0000395678, DOB 1993) - type 4 (CĐHA)

---

## v3.0.168 - DROPDOWN PTV/TTV CHÍNH TÊN ĐẦY ĐỦ TỪ SERVER

### Tính năng mới
- **Thêm `HisApiService.getAcsUsers()`** gọi ACS 1401 `/api/AcsUser/Get` (200 users active)
  - Fields: `LOGINNAME` (vd `dungntm`), `USERNAME` (vd `Nguyễn Thị Mỹ Dung`)
- **ECG execute screen - convert Bác sĩ chính + Điều dưỡng**:
  - Từ TextFormField → **DropdownButtonFormField** hiển thị tên đầy đủ
  - Sắp xếp A-Z theo USERNAME
  - Map LOGINNAME → USERNAME qua `_getFullName()` helper
  - Default: BS đang đăng nhập (từ `hispro_user`)
  - Validate: bắt buộc chọn trước khi save
- **Lưu kíp thực hiện vào HIS Pro** qua `updateServiceReq`:
  - EXECUTE_LOGINNAME: dungdv (LOGINNAME cho backend)
  - EXECUTE_USERNAME: ĐỖ Văn Dũng (Tên đầy đủ)
  - NURSE_LOGINNAME: diepnv
  - NURSE_USERNAME: Nguyễn Thị Diệp

### Workflow ECG hoàn chỉnh giống HIS Desktop
| Bước | HIS Desktop | v3.0.168 (mobile) |
|---|---|---|
| Chọn BN | "Gõ BN nhỏ" | Click BN trong Phòng tủ thuật HSCC |
| Mở ECG | "Xử lý" | Click BN → ECG screen |
| Chọn máy | Auto | Dropdown - Máy tạo Oxy di động (ID=29) auto |
| PTV chính | ComboBox "ĐỖ Văn Dũng" | **Dropdown mới** tên đầy đủ |
| Điều dưỡng | ComboBox | **Dropdown mới** (optional) |
| Save | "Lưu (Ctrl+S)" → EMR | "Hoàn thành & Kết thúc" → updateServiceReq + finishServiceReqWithTime |

---

## File quan trọng tạo/sửa

| File | Vai trò |
|---|---|
| `lib/data/services/token_sync_service.dart` | NEW - Token hub |
| `lib/data/api/his_api_service.dart` | +5 methods CLS, +getAcsUsers |
| `lib/core/utils/patient_name_helper.dart` | +field Data 3000, Public 8080 |
| `lib/core/utils/mojibake_fixer.dart` | +CP1252 mapping fix |
| `lib/presentation/screens/tien_ich_screen.dart` | Gộp 2 tile → 1 |
| `lib/presentation/screens/treatment_history_screen.dart` | UI kết quả CLS, auto-token |
| `lib/presentation/screens/procedure_room_screen.dart` | Ưu tiên HIS Pro, nút 🔄 |
| `lib/presentation/screens/ecg_execute_screen.dart` | Dropdown PTV/TTV |
| `lib/presentation/screens/settings_screen.dart` | Redesign token section |
| `lib/main.dart` | Bootstrap qua TokenSyncService |

## Test scripts (Python)
- `test_mojibake.py` - verify 12 mojibake cases
- `test_procedure_room.py` - verify 77 patients room 36
- `find_bao_kieu3.py` - verify 3 BN exact match HIS Desktop
- `test_users.py` - verify 200 users từ AcsUser

## Build artifacts
- `his_mobile_v3.0.164_arm64.apk` (27.18 MB)
- `his_mobile_v3.0.165_arm64.apk` (27.18 MB)
- `his_mobile_v3.0.166_arm64.apk` (27.18 MB)
- `his_mobile_v3.0.167_arm64.apk` (27.18 MB)
- `his_mobile_v3.0.168_arm64.apk` (27.19 MB) - LATEST

## Network summary
- Token hiện tại (từ RAM dump HIS.exe 23/08/2026 07:50): `e365259dd4997a1a7235ccb48511044f413b1b63cbd46e26222fa4c6a9ffe8a4`
- IP: `172.16.200.101` (BS PC)
- HIS Pro ports verified: 1401 ACS, 1408 MOS, 1409 SAR, 1410 SDA, 1417 EMR, 1419 LIS, 1425 OCR/MCH
- HIS Pro GetLView confirmed: room 36 = 77 BN, room 22 dept = 500 BN
- AcsUser/Get = 200 users, sắp xếp theo USERNAME
