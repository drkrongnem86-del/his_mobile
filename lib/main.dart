import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:his_mobile/core/services/app_version_service.dart';
import 'package:his_mobile/core/services/connection_service.dart';
import 'package:his_mobile/core/services/department_service.dart';
import 'package:his_mobile/core/services/his_config_service.dart';
import 'package:his_mobile/core/services/update_service.dart';
import 'package:his_mobile/core/theme/app_theme.dart';
import 'package:his_mobile/core/theme/theme_manager.dart';
import 'package:his_mobile/data/api/his_api_service.dart';
import 'package:his_mobile/data/api/his_catalog_service.dart';
import 'package:his_mobile/data/api/his_pro_api_service.dart' as his_pro_api;  // v3.0.144: class CHÍNH (EMR push)
import 'package:his_mobile/data/api/his_service_req_service.dart';
import 'package:his_mobile/data/api/his_tracking_service.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';
import 'package:his_mobile/modules/auth/presentation/blocs/auth_bloc.dart';
import 'package:his_mobile/presentation/navigation/app_router.dart';
import 'package:his_mobile/core/services/vpn_benh_vien_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:his_mobile/data/services/his_pro_api_service.dart';
import 'package:his_mobile/data/services/auto_token_service.dart';  // v3.0.159: Auto-token multi-source
import 'package:his_mobile/data/services/token_sync_service.dart';  // v3.0.165: Token hub

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // v2.37.1: Load theme đã lưu
  await ThemeManager.instance.init();

  // v2.66.0: Load app version (đọc từ package_info_plus - hiển thị ở Settings)
  await AppVersionService.instance.load();

  // Khởi tạo persistent cookie storage cho Thongke
  await ThongkeAuthService.instance.initPersistence();
  // Splash sẽ handle auto-login. Chỉ restore session ở main.
  await HisApiService().thongkeRestoreSession();
  // v2.55.0: Khởi tạo catalog + service req + tracking services
  await HisCatalogService.instance.init();
  await HisServiceReqService.instance.init();
  await HisTrackingService.instance.init();

  // v2.66.0: Load departments từ HIS Pro HisDepartment/Get (81 khoa thật)
  await DepartmentService.instance.load();

  // v2.75.1: Load HIS config (URLs + user + dept)
  await HisConfigService.instance.load();
  await ConnectionService.instance.load();

  // v3.0.165: Bootstrap TokenSyncService - áp dụng token cho TẤT CẢ services
  // - Bước 1: Load từ SharedPreferences (paste trước đó)
  // - Bước 2: Nếu chưa có → auto-fetch từ multi-source (proxy → login API → renew → hardcoded)
  // - Bước 3: Apply cho cả HisApiService + HisProApiService (cả 2 class) + ThongkeAuthService
  // - Cũng giữ hardcode fallback cuối cùng (giống v3.0.159)
  try {
    // Bước 1: Load từ SharedPreferences
    await TokenSyncService.instance.loadFromStorage();

    // Bước 2: Nếu chưa có token → auto-fetch
    if (!TokenSyncService.instance.hasToken) {
      debugPrint('🔑 [v3.0.165] No token in storage, auto-fetching from multi-source...');
      final event = await TokenSyncService.instance.autoFetchToken(force: false);
      debugPrint('🔑 [v3.0.165] Auto-fetch: success=${event.token != null} source=${event.source} msg=${event.message}');
    }

    // Bước 3: Backward-compat - set cả class PHỤ + Thongke
    final currentToken = TokenSyncService.instance.currentToken;
    if (currentToken != null && currentToken.isNotEmpty) {
      HisProApiService.instance.setTokenCode(token: currentToken, clientIp: '172.16.200.101');
      try {
        await ThongkeAuthService.instance.setHisProToken(
          currentToken,
          source: TokenSyncService.instance.currentSource ?? 'bootstrap',
        );
        await ThongkeAuthService.instance.loadHisProToken();
      } catch (_) {}
      debugPrint('🔑 [v3.0.165] TokenSyncService bootstrap OK: ${currentToken.substring(0, 8)}… source=${TokenSyncService.instance.currentSource}');
    } else {
      // Hardcode fallback cuối cùng
      const String hardcodeToken = 'e365259dd4997a1a7235ccb48511044f413b1b63cbd46e26222fa4c6a9ffe8a4';
      await TokenSyncService.instance.setToken(
        hardcodeToken,
        source: 'hardcoded',
        eventType: TokenEventType.loaded,
        broadcast: false,
      );
      HisProApiService.instance.setTokenCode(token: hardcodeToken, clientIp: '172.16.200.101');
      debugPrint('🔑 [v3.0.165] Hardcode fallback applied');
    }
  } catch (e) {
    debugPrint('⚠️ [v3.0.165] Bootstrap EMR Token failed: $e');
  }

  // v3.0.62: FORCE tất cả HIS Pro URLs về 172.16.9.6 (LAN) - port mới theo HIS_ICU v2.35.13
  // - 12 services: 80 (IIS), 1401 (ACS), 1405 (FSS), **1429** (MOS - v3.0.62 đổi từ 1408), 1409 (SAR),
  //   1410 (SDA), 1417 (EMR), 1418 (Aup), 1419 (LIS), 1425 (DMS), **1425** (OCR - v3.0.62 đổi từ 1429), 1530 (EMR Web)
  // - Plus Redis 8335, VVA 8926 (BS cung cấp)
  // - VPN BS chỉ route LAN → không dùng public 117.2.25.67 (timeout)
  // - NẾU port sai, dùng restore_v361.bat để quay lại v3.0.61
  try {
    const String lanBase = 'http://172.16.9.6';
    const int emrPort = 1417;
    const int fssPort = 1405;
    // v3.0.62: Đổi MOS 1408 → 1429 (theo HIS_ICU v2.35.13 verified)
    const int mosPort = 1429;
    const int sdaPort = 1410;
    const int sarPort = 1409;
    const int lisPort = 1419;
    // v3.0.62: Đổi OCR 1429 → 1425 (lấy chỗ trống vì 1429 đã dùng cho MOS)
    const int ocrPort = 1425;
    const int acsPort = 1401;
    const int dmsPort = 1425;     // v3.0.57: DMS Medilink HL7
    const int emrWebPort = 1530;  // v3.0.57: EMR Web Oracle DB (on-demand)
    const int redisPort = 8335;   // v3.0.57: Redis Cache
    const int vvaPort = 8926;     // v3.0.57: VVA Backend
    // Ghi đè HisConfigService (singleton)
    final cfg = HisConfigService.instance.config.copyWith(
      mode: 'lan', // v3.0.49: default = LAN vì VPN BS route LAN
      acsUrl: '$lanBase:$acsPort/',
      emrUrl: '$lanBase:$emrPort/',
      mosUrl: '$lanBase:$mosPort/',
      sarUrl: '$lanBase:$sarPort/',
      sdaUrl: '$lanBase:$sdaPort/',
      fssUrl: '$lanBase:$fssPort/',
      lisUrl: '$lanBase:$lisPort/',
      ocrUrl: '$lanBase:$ocrPort/',
      dmsUrl: '$lanBase:$dmsPort/',
      emrWebUrl: '$lanBase:$emrWebPort/',
      redisUrl: '$lanBase:$redisPort/',
      vvaUrl: '$lanBase:$vvaPort/',
    );
    await HisConfigService.instance.save(cfg);
    // Ghi đè URL trong emr_push_service (key riêng)
    await prefs.setString('emr_base_url', '$lanBase:$emrPort');
    await prefs.setString('fss_base_url', '$lanBase:$fssPort');
    print('🌐 [v3.0.62] Force HIS Pro URLs: mode=lan base=$lanBase (12 services, MOS=1429, OCR=1425)');
  } catch (e) {
    print('⚠️ Force URLs failed: $e');
  }

  runApp(HisMobileApp(prefs: prefs));
}

class HisMobileApp extends StatefulWidget {
  final SharedPreferences prefs;

  const HisMobileApp({super.key, required this.prefs});

  @override
  State<HisMobileApp> createState() => _HisMobileAppState();
}

class _HisMobileAppState extends State<HisMobileApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // v3.0.144: Auto check update sau 5s khi mở app
    _autoCheckUpdateOnStart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// v3.0.144: Tự động check update khi mở app
  /// Delay 5s để app init xong (VPN, theme, routing) rồi mới check
  /// Nếu có bản mới → hiện dialog thông báo
  /// v3.0.173: Restore lại từ v3.0.169 (bỏ v3.0.171 vì user thấy thiếu)
  Future<void> _autoCheckUpdateOnStart() async {
    final info = await UpdateService.autoCheckUpdate(
      delay: const Duration(seconds: 5),
    );
    if (info != null && mounted) {
      final navKey = AppRouter.router.routerDelegate.navigatorKey;
      final ctx = navKey.currentContext;
      if (ctx != null) {
        UpdateService.showUpdateDialog(ctx, info);
      } else {
        debugPrint('autoCheckUpdateOnStart: no navigator context');
      }
    }
  }

  /// v3.0.77: Lifecycle - khi user thoát app / chuyển sang background, đợi 5 phút rồi auto-disconnect VPN
  /// (v3.0.171: dùng 5-min timer của VpnBenhVienService thay vì ngắt ngay - tránh ngắt nhầm khi user chỉ chuyển tab nhanh)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final vpn = VpnBenhVienService.instance;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      debugPrint('HisMobileApp: lifecycle ${state.name} → start 5min auto-disconnect timer');
      vpn.onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('HisMobileApp: lifecycle ${state.name} → cancel 5min auto-disconnect timer');
      vpn.onAppResumed();
    } else if (state == AppLifecycleState.detached) {
      // App bị kill hoàn toàn → ngắt VPN ngay
      if (vpn.isConnected) {
        debugPrint('HisMobileApp: lifecycle detached → immediate disconnect VPN');
        vpn.disconnect();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthBloc(prefs: widget.prefs),
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeManager.instance.themeModeNotifier,
        builder: (_, mode, __) => MaterialApp.router(
          title: 'HIS Mobile - Khoa Cap Cuu',
          debugShowCheckedModeBanner: false,
          // v3.0.144: navigatorKey không có sẵn trên MaterialApp.router
          // Dùng builder để lấy context thông qua Navigator.of
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          routerConfig: AppRouter.router,
        ),
      ),
    );
  }
}