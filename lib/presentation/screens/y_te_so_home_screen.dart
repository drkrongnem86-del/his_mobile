// v3.0.9: Màn hình chính "Y tế số" - grid chức năng
// v3.0.93: Bỏ 'Bệnh án' (dư - đã có ở patient actions sheet). Còn 19 chức năng.
import 'package:flutter/material.dart';
import 'package:his_mobile/data/models/y_te_so_feature.dart';
import 'package:his_mobile/data/models/y_te_so_router.dart';

class YTeSoHomeScreen extends StatelessWidget {
  final Map<String, dynamic>? patient;
  final Map<String, dynamic>? department;

  const YTeSoHomeScreen({super.key, this.patient, this.department});

  @override
  Widget build(BuildContext context) {
    final features = YTeSoFeatures.all;
    final hasPatient = patient != null;
    final patientName = patient?['TDL_PATIENT_UNSIGNED_NAME']?.toString() ??
        patient?['TDL_PATIENT_NAME']?.toString() ??
        patient?['tdl_patient_name']?.toString() ??
        '';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF00838F),
        foregroundColor: Colors.white,
        title: Row(
          children: [
            const Icon(Icons.health_and_safety, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            const Text('Y tế số', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (hasPatient && patientName.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '● ${patientName.length > 20 ? '${patientName.substring(0, 20)}…' : patientName}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Thông tin',
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Header banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF00838F), Color(0xFF006064)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'BỘ Y TẾ',
                        style: TextStyle(
                          color: Color(0xFF00838F),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'API Y tế số Bộ Y tế (113.163.187.3:3000)',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${features.length} chức năng y tế số',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  hasPatient
                      ? 'Sử dụng cho: ${patientName.isEmpty ? "BN" : patientName}'
                      : 'Tab vào tên bệnh nhân để dùng cho từng BN cụ thể',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Grid 15 features
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.85,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                itemCount: features.length,
                itemBuilder: (ctx, i) {
                  final f = features[i];
                  return InkWell(
                    onTap: () {
                      // v3.0.23: Vào thẳng screen tương ứng (bỏ màn giới thiệu workflow)
                      YTeSoRouter.navigate(
                        ctx,
                        f.id,
                        patient: patient ?? {},
                        department: department ?? {},
                      );
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: f.color.withValues(alpha: 0.2)),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 3,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [f.color, f.color.withValues(alpha: 0.7)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(f.icon, color: Colors.white, size: 24),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            f.name,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: f.color,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Color(0xFF00838F)),
            SizedBox(width: 8),
            Text('Y tế số'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${YTeSoFeatures.all.length} chức năng y tế số (Bộ Y tế)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              const Text(
                'Đồng bộ từ app Y tế số gốc (com.snd.adbc) - phân tích từ file APK + test với API thật.',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 12),
              const Text(
                'Cách dùng:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),
              const Text(
                '• Bấm vào 1 chức năng để mở màn hình chi tiết\n'
                '• API: http://113.163.187.3:3000/v1/...\n'
                '• Tab vào tên BN → bottom sheet có grid chức năng cho BN đó',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }
}
