import 'dart:convert';



import 'dart:io';



import 'package:flutter/material.dart';



import 'package:flutter/services.dart';



import 'package:flutter/foundation.dart' show debugPrint;



import 'package:his_mobile/core/constants/app_constants.dart';



import 'package:his_mobile/data/api/his_catalog_service.dart';



import 'package:his_mobile/data/local/scanned_forms_service.dart';



import 'package:his_mobile/data/models/phieu.dart';



import 'package:his_mobile/data/services/form_draft_service.dart';



import 'package:his_mobile/data/models/phieu_catalog.dart';



import 'package:his_mobile/data/services/data_service.dart';



import 'package:his_mobile/data/api/his_pro_api_service.dart';



import 'package:his_mobile/data/services/phieu_save_service.dart';



import 'package:his_mobile/data/api/emr_push_service.dart';



import 'package:his_mobile/presentation/widgets/catalog_picker.dart';



import 'package:his_mobile/presentation/widgets/dept_picker_widget.dart';



import 'package:his_mobile/presentation/widgets/icd_picker_widgets.dart';



import 'package:his_mobile/presentation/widgets/icd_input_field.dart';



import 'package:his_mobile/presentation/widgets/searchable_picker.dart';



import 'package:his_mobile/presentation/widgets/user_header.dart';



import 'package:path/path.dart' as pathJoin;



import 'package:shared_preferences/shared_preferences.dart';



import 'package:signature/signature.dart';







/// v3.0.0: Chế độ lưu phiếu



enum SaveMode {



  local,      // chỉ lưu local (không EMR)



  unsigned,   // lưu + đẩy EMR (chưa ký)



  signed,     // lưu + ký + đẩy EMR



}







/// MĂ n hình Điền form phiếu - generic cho mọi loại phiếu.


/// Nếu không truyền `phieu` thì hiện dropdown chọn loại phiếu ở đầu form.



/// Hỗ trợ field types: text, textLong, number, date, dateTime, select, bool, icd, medicine, service, signature.



/// 2 nứt save:



///   - "Lưu" (chỉ lưu local - không đẩy EMR)



///   - "Lưu chưa ký" (lưu + đẩy EMR IsFinishSign=false - BS ký sau trên HIS Pro)



///   - "Lưu ký" (lưu + ký số + đẩy EMR IsFinishSign=true)



class PhieuFormScreen extends StatefulWidget {



  final Phieu? phieu; // null = cho user chọn loại phiếu trong form



  final Map<String, dynamic> patient;



  final Map<String, dynamic> department;







  const PhieuFormScreen({



    super.key,



    this.phieu,



    required this.patient,



    required this.department,



  });







  @override



  State<PhieuFormScreen> createState() => _PhieuFormScreenState();



}







class _PhieuFormScreenState extends State<PhieuFormScreen> {



  final Map<String, TextEditingController> _controllers = {};



  final Map<String, dynamic> _values = {};



  final Map<String, List<Map<String, dynamic>>> _listValues = {};



  bool _saving = false;



  String _pcForDraft = 'unknown';



  final SignatureController _signatureCtrl = SignatureController(



    penStrokeWidth: 2,



    penColor: Colors.black,



    exportBackgroundColor: Colors.white,



  );



  bool _withSignature = false;



  String? _lastResult;



  Phieu? _selectedPhieu;







  @override



  void initState() {



    super.initState();



    _selectedPhieu = widget.phieu;



    if (_selectedPhieu != null) {



      _initFields();



    }



    // v2.58.0: Restore draft (nếu có) từ FormDraftService



    _restoreDraft();



  }







  void _selectPhieu(Phieu? p) {



    setState(() {



      _selectedPhieu = p;



      for (final c in _controllers.values) {



        c.dispose();



      }



      _controllers.clear();



      _values.clear();



      _listValues.clear();



      if (p != null) {



        _initFields();



        _restoreDraft();



      }



    });



  }







  void _initFields() {



    final p = _selectedPhieu!;



    for (final field in p.fields) {



      if (field.defaultValue != null) {



        _values[field.key] = field.defaultValue;



        _controllers[field.key] = TextEditingController(text: field.defaultValue);



      } else if (field.type == PhieuFieldType.bool_) {



        _values[field.key] = false;



      } else if (field.type == PhieuFieldType.medicine) {



        _listValues[field.key] = [];



      } else if (field.type == PhieuFieldType.service) {



        _listValues[field.key] = [];



      } else {



        _controllers[field.key] = TextEditingController();



      }



    }



    _autoFillFromPatient();



  }







  /// v2.58.0: Restore draft từ FormDraftService (nếu có)



  Future<void> _restoreDraft() async {



    if (_selectedPhieu == null) return;



    final pc = widget.patient['TDL_PATIENT_CODE']?.toString() ??



        widget.patient['tdl_patient_code']?.toString() ??



        widget.patient['PATIENT_CODE']?.toString() ??



        widget.patient['id']?.toString() ??



        'unknown';



    final draft = await FormDraftService.instance.loadDraft(



      _selectedPhieu!.code,



      pc,



    );



    if (draft == null || draft.values == null) return;



    if (!mounted) return;



    final savedAt = draft.savedAt;



    setState(() {



      // Restore values (tránh đè auto-fill)



      draft.values!.forEach((k, v) {



        if (_values[k] != v) {



          _values[k] = v;



          if (_controllers.containsKey(k)) {



            _controllers[k]!.text = v?.toString() ?? '';



          } else if (k.endsWith('_icd') || k.endsWith('_text')) {



            // v2.63.0: Tạo controller cho icd/text sub-keys nếu chưa có



            _controllers[k] = TextEditingController(text: v?.toString() ?? '');



          }



        }



      });



      // Restore list values



      draft.listValues?.forEach((k, v) {



        _listValues[k] = v.map((e) => Map<String, dynamic>.from(e as Map)).toList();



      });



    });



    if (mounted) {



      ScaffoldMessenger.of(context).showSnackBar(



        SnackBar(



          content: Text('đã khôi phục bản nháp từ ${savedAt != null ? _fmtTimeAgo(savedAt) : "trước"}'),



          backgroundColor: Colors.blue.shade700,



          duration: const Duration(seconds: 3),



        ),



      );



    }



  }







  String _fmtTimeAgo(DateTime dt) {



    final diff = DateTime.now().difference(dt);



    if (diff.inMinutes < 1) return 'vừa xong';



    if (diff.inMinutes < 60) return '${diff.inMinutes} phứt trước';



    if (diff.inHours < 24) return '${diff.inHours} giờ trước';



    return '${diff.inDays} ngĂ y trước';



  }







  /// v2.58.0: Auto-save draft (má»—i khi user thay đổi gì Đó)



  void _autoSaveDraft() {



    if (_selectedPhieu == null) return;



    FormDraftService.instance.saveDraft(



      _selectedPhieu!.code,



      _pcForDraft,



      _values,



      _listValues,



    );



  }







  /// v2.58.0: Set value + auto-save draft



  void _setVal(String key, dynamic value) {



    _values[key] = value;



    _autoSaveDraft();



  }







  void _autoFillFromPatient() {



    if (_selectedPhieu == null) return;



    final p = widget.patient;



    final d = widget.department;



    final data = DataService.instance.user;



    final username = data?.userName ?? 'BS';







    // Ensure _pc is captured



    _pcForDraft = p['TDL_PATIENT_CODE']?.toString() ??



        p['tdl_patient_code']?.toString() ??



        p['PATIENT_CODE']?.toString() ??



        p['id']?.toString() ??



        'unknown';







    String _g(String k1, [String? k2, String? k3]) =>



        (p[k1] ?? p[k2 ?? ''] ?? p[k3 ?? ''] ?? '').toString();







    final autoFill = <String, String>{



      'TDL_PATIENT_UNSIGNED_NAME': _g('TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_NAME', 'tdl_patient_name'),



      'TDL_PATIENT_NAME': _g('TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_NAME', 'tdl_patient_name'),



      'PATIENT_NAME': _g('TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_NAME', 'tdl_patient_name'),



      'VIR_PATIENT_NAME': _g('TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_NAME', 'tdl_patient_name'),



      'TDL_PATIENT_GENDER_NAME': _g('TDL_PATIENT_GENDER_NAME', 'tdl_patient_gender_name'),



      'GENDER_NAME': _g('TDL_PATIENT_GENDER_NAME', 'tdl_patient_gender_name'),



      'VIR_ADDRESS': _g('TDL_PATIENT_ADDRESS', 'tdl_patient_address'),



      'TDL_PATIENT_ADDRESS': _g('TDL_PATIENT_ADDRESS', 'tdl_patient_address'),



      'AGE': _g('TDL_PATIENT_DOB', 'tdl_patient_dob'),



      'TDL_PATIENT_DOB': _g('TDL_PATIENT_DOB', 'tdl_patient_dob'),



      'DEPARTMENT_NAME': d['name']?.toString() ?? '',



      'BED_CODE': _g('P', 'BED_CODE'),



      'BED_NAME': _g('BED_NAME'),



      'ROOM_NAME': _g('BED_NAME'),



      'IN_CODE': _g('TDL_TREATMENT_CODE', 'treatment_code'),



      'TREATMENT_CODE': _g('TDL_TREATMENT_CODE', 'treatment_code'),



      'PATIENT_CODE': _g('TDL_PATIENT_CODE', 'tdl_patient_code'),



      'ICD_NAME': _g('ICD_NAME', 'icd_name'),



      'ICD_CODE': _g('ICD_CODE', 'icd_code'),



      'ICD_TEXT': _g('ICD_TEXT'),



      'BS_KHAM': username,



      'BS_CHI_DINH': username,



      'BS_DIEU_TRI': username,



      'BS_KE_DON': username,



      'BS_CHUYEN': username,



      'BS_HEN': username,



      'BS_XAC_NHAN': username,



      'NGUOI_KY': username,



      'NGUOI_NHAP': username,



      'BS': username,



      'USERNAME': username,



    };



    autoFill.forEach((key, value) {



      if (value.isNotEmpty && _controllers.containsKey(key) && _controllers[key]!.text.isEmpty) {



        _controllers[key]!.text = value;



        _values[key] = value;



      }



    });







    // v2.64.0: BỎ auto-fill ICD - để user nhập tay rõ rĂ ng (BS yêu cầu)



    // Giữ hint "Gõ ICD hoặc tên bệnh..." + nứt search picker 174+ ICD



  }







  @override



  void dispose() {



    for (final c in _controllers.values) {



      c.dispose();



    }



    super.dispose();



  }







  /// v3.0.0: 3 chế độ lưu



  /// - [SaveMode.local]: Chỉ lưu local (không đẩy EMR)



  /// - [SaveMode.unsigned]: Lưu local + đẩy EMR KHÔNG ký (IsFinishSign=false)



  /// - [SaveMode.signed]: Lưu local + đẩy EMR CÓ ký (IsFinishSign=true)



  /// v3.0.46: Thêm useVnptSignature=true → ký PKCS#7 qua VNPT SmartCA



  Future<void> _save({required SaveMode mode, bool useVnptSignature = false}) async {



    if (_selectedPhieu == null || _saving) return;



    setState(() {



      _saving = true;



      _withSignature = mode != SaveMode.local;



    });



    final stopwatch = Stopwatch()..start();







    final p = _selectedPhieu!;



    final treatmentCode = widget.patient['TDL_TREATMENT_CODE'] ?? widget.patient['treatment_code'] ?? '';



    final patientCode = widget.patient['TDL_PATIENT_CODE'] ?? widget.patient['tdl_patient_code'] ?? '';



    final patientName = (widget.patient['TDL_PATIENT_UNSIGNED_NAME'] ?? widget.patient['TDL_PATIENT_NAME'] ?? widget.patient['tdl_patient_name'] ?? 'BN').toString();







    // v3.0.0: Nếu Lưu ký -> mở signature dialog trước



    String? signaturePath;



    if (mode == SaveMode.signed) {



      final sigResult = await _captureSignatureForForm(p);



      if (sigResult == null) {



        // User hễy



        if (mounted) setState(() => _saving = false);



        return;



      }



      signaturePath = sigResult;



    }







    // v2.38.1: Lưu local ngay để không mất data, rồi má»›i thá»­ sync HIS Pro



    // Lưu local vĂ o SharedPreferences (cache)



    try {



      await _saveLocal(p, treatmentCode, patientCode);



    } catch (e) {



      debugPrint('Save local error: $e');



    }







    // v2.43.0: Lưu vĂ o ScannedFormsService để hiện trong Xem bệnh án



    try {



      await _saveAsScannedForm(



        phieu: p,



        treatmentCode: treatmentCode,



        patientName: patientName,



        signaturePath: signaturePath,



      );



    } catch (e) {



      debugPrint('Save scanned form error: $e');



    }







    // v2.36.2: Thá»­ save qua HIS Pro API (cần VPN đến BV) - có timeout 8s



    String resultMsg;



    bool success = false;







    // v3.0.46: Nếu useVnptSignature=true → dùng PhieuSaveService (flow mới, hỗ trợ VNPT SmartCA)



    if (useVnptSignature && mode == SaveMode.signed) {



      debugPrint('PhieuForm: Ký VNPT SmartCA → dùng PhieuSaveService');



      try {



        final vnptResult = await PhieuSaveService.instance.save(



          mode: PhieuSaveMode.signed,



          input: PhieuSaveInput(

  useVnptSignature: true,



            patient: widget.patient,



            formName: p.name,



            formData: _values,



            signaturePath: signaturePath,



            documentTypeId: EmrDocumentKind.phieuKhac.docTypeId,



            phieuLabel: p.name,



            departmentCode: 'HSCC',



            roomCode: 'PKCC',



            workingDeptName: 'Khoa Cấp Cứu',



          ),



        );



        if (vnptResult.emrPushed) {



          resultMsg = vnptResult.vnptSigned



              ? '✅ Ký VNPT SmartCA + đẩy EMR thành công\n'



              : '✅ Đẩy EMR thành công (chưa ký VNPT - cần backend BV)\n';



          resultMsg += 'DocumentCode: ${vnptResult.documentCode}';



          success = true;



        } else if (vnptResult.success) {



          resultMsg = '⚠ EMR fail: ${vnptResult.error}\nPDF giữ tại: ${vnptResult.tempPdfPath}';



        } else {



          resultMsg = '❌ ${vnptResult.error}';



        }



      } catch (e) {



        debugPrint('VNPT save error: $e');



        resultMsg = '❌ Lỗi VNPT: ${e.toString().split("\n").first}';



      }



    } else {



    // Legacy flow - hisPro.post Mps Save



    try {



      final hisPro = HisProApiService.instance;



      // Wrap API call vá»›i timeout 8s để không treo app



      final r = await hisPro.post('${p.code}/Save', {



        'TreatmentCode': treatmentCode,



        'PatientCode': patientCode,



        'Data': _values,



        'ListData': _listValues,



        'SignEmr': mode == SaveMode.signed,



        'UploadUnsignedEmr': mode == SaveMode.unsigned,  // v3.0.0: NEW



      }).timeout(const Duration(seconds: 8), onTimeout: () {
        debugPrint('HisPro save timeout');
        return (success: false, status: null, data: null, message: 'timeout');
      });



      if (r != null) {



        resultMsg = mode == SaveMode.signed



            ? '✅ ĐÃ LƯU + KÝ + ĐẨY EMR\n'



            : '✅ ĐÃ LƯU + ĐẨY EMR (CHƯA KÝ)\n';



        resultMsg += 'Hiện trong Xem bệnh án';



        success = true;


      } else {



        resultMsg = '⚠ HIS Pro không phản hồi (cần VPN BV).\n✅ Đã lưu local thành công.\n✅ Hiện trong Xem bệnh án.\n\nVào Cài đặt → bật VPN → bấm "ĐB HIS" để đồng bộ sau.';



      }



    } catch (e) {



      debugPrint('Save HIS Pro error: $e');



      resultMsg = '⚠ Không kết nối được HIS Pro.\n✅ Đã lưu local thành công.\n\nLỗi: \${e.toString().split("\n").first}';



    }



    }  // end else (legacy)







    stopwatch.stop();



    if (!mounted) return;



    setState(() {



      _saving = false;



      _lastResult = '$resultMsg\n\n⏱ ${stopwatch.elapsedMilliseconds}ms';



    });







    // v2.58.0: Clear draft nếu save thành công



    if (success) {



      try {



        await FormDraftService.instance.clearDraft(p.code, patientCode);



      } catch (_) {}



    }







    // v2.38.1: Dùng try/catch cho showDialog để tránh crash nếu context invalid



    try {



      String title;



      Color titleColor;



      IconData titleIcon;



      switch (mode) {



        case SaveMode.local:



          title = 'Lưu';



          titleColor = Colors.indigo;



          titleIcon = Icons.save;



          break;



        case SaveMode.unsigned:



          title = 'Lưu chưa ký';



          titleColor = Colors.orange.shade700;



          titleIcon = Icons.cloud_upload;



          break;



        case SaveMode.signed:



          title = 'Lưu ký';



          titleColor = Colors.green.shade700;



          titleIcon = Icons.draw;



          break;



      }



      showDialog(



        context: context,



        builder: (ctx) => AlertDialog(



          title: Row(



            children: [



              Icon(success ? titleIcon : Icons.info, color: success ? titleColor : Colors.amber),



              const SizedBox(width: 8),



              Text(title, style: TextStyle(color: titleColor, fontWeight: FontWeight.bold)),



            ],



          ),



          content: SingleChildScrollView(



            child: Column(



              mainAxisSize: MainAxisSize.min,



              crossAxisAlignment: CrossAxisAlignment.start,



              children: [



                Text(_lastResult!, style: const TextStyle(fontSize: 13)),



                const SizedBox(height: 12),



                if (!success) const Text(



                  '⚠ Đẩy lên EMR:\n'



                  '1. Bật VPN BV (OpenVPN BV)\n'



                  '2. Bấm "ĐB HIS" trên Trang chính\n'



                  '3. Đồng bộ lại để đẩy phiếu lên EMR',



                  style: TextStyle(fontSize: 11, color: Colors.black54),



                ),



              ],



            ),



          ),



          actions: [



            if (mode == SaveMode.unsigned && success)



              TextButton.icon(



                onPressed: () {



                  Navigator.pop(ctx);



                  _openEmrSignNow();



                },



                icon: const Icon(Icons.edit_note, size: 18),



                label: const Text('Mở ký EMR'),



              ),



            TextButton(



              onPressed: () => Navigator.pop(ctx),



              child: const Text('đóng'),



            ),



          ],



        ),



      );



    } catch (e) {



      debugPrint('Show dialog error: $e');



    }



  }







  /// v2.38.1: Lưu phiếu vĂ o SharedPreferences local



  Future<void> _saveLocal(Phieu p, String tcode, String pcode) async {



    final prefs = await SharedPreferences.getInstance();



    final key = 'phieu_${p.code}_${tcode}_${DateTime.now().millisecondsSinceEpoch}';



    final data = {



      'PhieuCode': p.code,



      'PhieuName': p.name,



      'TreatmentCode': tcode,



      'PatientCode': pcode,



      'Values': _values,



      'ListData': _listValues,



      'CreatedAt': DateTime.now().toIso8601String(),



      'Saved': true,



    };



    await prefs.setString(key, jsonEncode(data));



    debugPrint('Saved local: $key');



  }







  /// v2.43.0: Hien thi signature dialog, tra ve path file signature (null neu user huy)



  Future<String?> _captureSignatureForForm(Phieu p) async {



    _signatureCtrl.clear();



    final result = await showDialog<bool>(



      context: context,



      barrierDismissible: false,



      builder: (ctx) {



        return Dialog(



          insetPadding: const EdgeInsets.all(16),



          child: Container(



            padding: const EdgeInsets.all(16),



            child: Column(



              mainAxisSize: MainAxisSize.min,



              children: [



                Text(



                  'Ký tên cho phiếu: ${p.name}',



                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),



                ),



                const SizedBox(height: 4),



                Text(



                  'Người ký: ${DataService.instance.user?.userName ?? 'user'}',



                  style: const TextStyle(fontSize: 11, color: Colors.black54),



                ),



                const SizedBox(height: 8),



                Container(



                  decoration: BoxDecoration(



                    border: Border.all(color: Colors.grey.shade400),



                    borderRadius: BorderRadius.circular(8),



                  ),



                  height: 220,



                  child: Signature(



                    controller: _signatureCtrl,



                    backgroundColor: Colors.grey.shade50,



                  ),



                ),



                const SizedBox(height: 12),



                Row(



                  children: [



                    Expanded(



                      child: TextButton.icon(



                        onPressed: () => Navigator.pop(ctx, false),



                        icon: const Icon(Icons.close),



                        label: const Text('Hễy'),



                      ),



                    ),



                    const SizedBox(width: 8),



                    Expanded(



                      child: OutlinedButton.icon(



                        onPressed: () => _signatureCtrl.clear(),



                        icon: const Icon(Icons.refresh),



                        label: const Text('Xóa'),



                      ),



                    ),



                    const SizedBox(width: 8),



                    Expanded(



                      child: FilledButton.icon(



                        onPressed: () {



                          if (_signatureCtrl.isNotEmpty) {



                            Navigator.pop(ctx, true);



                          }



                        },



                        icon: const Icon(Icons.check),



                        label: const Text('Xong'),



                        style: FilledButton.styleFrom(



                          backgroundColor: const Color(0xFF2E7D32),



                        ),



                      ),



                    ),



                  ],



                ),



              ],



            ),



          ),



        );



      },



    );



    if (result != true || _signatureCtrl.isEmpty) return null;



    final bytes = await _signatureCtrl.toPngBytes();



    if (bytes == null) return null;



    final dir = await ScannedFormsService.instance.getImageDir();



    final sigPath = pathJoin.join(dir, 'form_sig_${DateTime.now().millisecondsSinceEpoch}.png');



    final f = File(sigPath);



    await f.writeAsBytes(bytes);



    return sigPath;



  }







  /// v2.43.0: Luu phieu vao ScannedFormsService (de hien thi trong Xem benh an)



  Future<void> _saveAsScannedForm({



    required Phieu phieu,



    required String treatmentCode,



    required String patientName,



    String? signaturePath,



  }) async {



    try {



      // Tao hinh anh tom tat tu cac field da dien



      final imgBytes = await _generatePhieuSummaryImage(phieu);



      if (imgBytes == null) return;  // Skip neu khong tao duoc image



      final dir = await ScannedFormsService.instance.getImageDir();



      final id = 'phieu_${DateTime.now().millisecondsSinceEpoch}';



      final imgPath = pathJoin.join(dir, '$id.png');



      final f = File(imgPath);



      await f.writeAsBytes(imgBytes);







      final form = ScannedForm(



        id: id,



        treatmentCode: treatmentCode,



        patientName: patientName,



        formName: phieu.name,



        imagePath: imgPath,



        signaturePath: signaturePath,



        signedBy: DataService.instance.user?.userName ?? 'user',



        createdAt: DateTime.now(),



        updatedAt: DateTime.now(),



        uploaded: false,



        note: _values.isNotEmpty ? '${_values.length} fields' : null,



      );



      await ScannedFormsService.instance.save(form);



    } catch (e) {



      debugPrint('_saveAsScannedForm error: $e');



    }



  }







  /// v2.43.0: Render tom tat phieu thanh hinh anh PNG (de hien thi trong Xem benh an)



  Future<List<int>?> _generatePhieuSummaryImage(Phieu phieu) async {



    // Don't generate image for now (avoids pulling in pdf/screenshot library)



    // Instead, return null - phiếu vẫn hiện trong Xem bện án thông qua metadata



    return null;



  }







    Future<void> _openEmrSignNow() async {



    final p = _selectedPhieu;



    if (p == null) return;



    final treatmentCode = widget.patient['TDL_TREATMENT_CODE'] ?? widget.patient['treatment_code'] ?? '';



    final url = 'http://172.16.9.6:1401/mps/preview?code=${p.code}&treatment=$treatmentCode&signNow=1';



    debugPrint('Open EMR sign URL: $url');



  }







  @override



  Widget build(BuildContext context) {



    final hasPhieu = _selectedPhieu != null;



    return Scaffold(



      backgroundColor: Colors.white,



      appBar: AppBar(



        backgroundColor: hasPhieu ? _selectedPhieu!.color : Colors.indigo,



        foregroundColor: Colors.white,



        title: Row(



          children: [



            Icon(hasPhieu ? _selectedPhieu!.icon : Icons.assignment, size: 18),



            const SizedBox(width: 6),



            Expanded(



              child: Text(



                hasPhieu ? _selectedPhieu!.name : 'Lập phiếu',



                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),



                maxLines: 1,



                overflow: TextOverflow.ellipsis,



              ),



            ),



          ],



        ),



      ),



      body: Column(



        children: [



          UserHeader.fromAuth(compact: true, department: widget.department['name']?.toString()),



          // Hiện dropdown chọn loại phiếu nếu chưa chọn



          if (!hasPhieu)



            Expanded(child: _buildPhieuSelector())



          else ...[



            // Save bar



            Container(



              color: _selectedPhieu!.color.withOpacity(0.08),



              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),



              child: Row(



                children: [



                  Container(



                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),



                    decoration: BoxDecoration(



                      color: Colors.white,



                      borderRadius: BorderRadius.circular(4),



                      border: Border.all(color: _selectedPhieu!.color.withOpacity(0.5)),



                    ),



                    child: Row(



                      mainAxisSize: MainAxisSize.min,



                      children: [



                        Container(



                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),



                          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(3)),



                          child: Text(_selectedPhieu!.code, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),



                        ),



                        const SizedBox(width: 4),



                        Text(_selectedPhieu!.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),



                      ],



                    ),



                  ),



                  const Spacer(),



                  if (_saving)



                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))



                  else



                    Text(



                      _selectedPhieu!.canSignEmr ? 'Lưu ký' : 'Lưu HIS',



                      style: TextStyle(fontSize: 10, color: _selectedPhieu!.color, fontWeight: FontWeight.bold),



                    ),



                ],



              ),



            ),



            // Nứt đổi loại phiếu (nếu cần)



            Container(



              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),



              child: Row(



                children: [



                  TextButton.icon(



                    onPressed: () => _selectPhieu(null),



                    icon: const Icon(Icons.swap_horiz, size: 14),



                    label: const Text('Đổi loại phiếu', style: TextStyle(fontSize: 11)),



                  ),



                ],



              ),



            ),



            // Form



            Expanded(



              child: ListView(



                padding: const EdgeInsets.all(12),



                children: [



                  ..._selectedPhieu!.fields.map((f) => _buildField(f)),



                  const SizedBox(height: 20),



                  if (_selectedPhieu!.canSignEmr) _buildSaveButtons() else _buildSaveButtonOnly(),



                  const SizedBox(height: 80),



                ],



              ),



            ),



          ],



        ],



      ),



    );



  }







  /// MĂ n hình chọn loại phiếu (grid)



  Widget _buildPhieuSelector() {



    final grouped = PhieuCatalog.groupedByCategory();



    return Column(



      children: [



        // Banner BN



        Container(



          decoration: const BoxDecoration(



            gradient: LinearGradient(colors: [Color(0xFF1565C0), Color(0xFF0D47A1)]),



          ),



          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),



          child: Row(



            children: [



              Container(



                width: 40, height: 40,



                decoration: BoxDecoration(color: Colors.white24, shape: BoxShape.circle, border: Border.all(color: Colors.white54)),



                child: const Icon(Icons.person, color: Colors.white, size: 24),



              ),



              const SizedBox(width: 12),



              Expanded(



                child: Column(



                  crossAxisAlignment: CrossAxisAlignment.start,



                  children: [



                    Text(



                      _getPatientName().isEmpty ? 'Chọn loại phiếu' : _getPatientName(),



                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),



                      maxLines: 1, overflow: TextOverflow.ellipsis,



                    ),



                    Text(



                      'Chọn 1 loại phiếu để bắt đầu lập',



                      style: const TextStyle(color: Colors.white70, fontSize: 11),



                    ),



                  ],



                ),



              ),



            ],



          ),



        ),



        Expanded(



          child: ListView(



            padding: const EdgeInsets.all(8),



            children: grouped.entries.map((entry) {



              return _buildSelectorSection(entry.key, entry.value);



            }).toList(),



          ),



        ),



      ],



    );



  }







  Widget _buildSelectorSection(PhieuCategory cat, List<Phieu> phieus) {



    return Column(



      crossAxisAlignment: CrossAxisAlignment.start,



      children: [



        Padding(



          padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),



          child: Row(



            children: [



              Icon(cat.icon, size: 14, color: Colors.indigo),



              const SizedBox(width: 6),



              Text(



                cat.label.toUpperCase(),



                style: const TextStyle(color: Colors.indigo, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),



              ),



              const SizedBox(width: 6),



              Container(



                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),



                decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(6)),



                child: Text('${phieus.length}', style: TextStyle(color: Colors.indigo.shade700, fontSize: 9)),



              ),



            ],



          ),



        ),



        GridView.builder(



          shrinkWrap: true,



          physics: const NeverScrollableScrollPhysics(),



          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(



            crossAxisCount: 4,



            childAspectRatio: 1.0,



            crossAxisSpacing: 6,



            mainAxisSpacing: 6,



          ),



          itemCount: phieus.length,



          itemBuilder: (ctx, i) {



            final p = phieus[i];



            return _buildSelectorTile(p);



          },



        ),



      ],



    );



  }







  Widget _buildSelectorTile(Phieu p) {



    return InkWell(



      borderRadius: BorderRadius.circular(8),



      onTap: () => _selectPhieu(p),



      child: Container(



        padding: const EdgeInsets.all(6),



        decoration: BoxDecoration(



          color: Colors.white,



          borderRadius: BorderRadius.circular(8),



          border: Border.all(color: p.color.withOpacity(0.4), width: 1),



        ),



        child: Column(



          mainAxisAlignment: MainAxisAlignment.center,



          children: [



            Container(



              padding: const EdgeInsets.all(6),



              decoration: BoxDecoration(color: p.color.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),



              child: Icon(p.icon, color: p.color, size: 20),



            ),



            const SizedBox(height: 4),



            Text(



              p.name,



              textAlign: TextAlign.center,



              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.black87),



              maxLines: 2,



              overflow: TextOverflow.ellipsis,



            ),



            if (p.canSignEmr)



              Padding(



                padding: const EdgeInsets.only(top: 2),



                child: Container(



                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),



                  decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(3)),



                  child: const Text('Ký EMR', style: TextStyle(fontSize: 8, color: Color(0xFFFF8F00), fontWeight: FontWeight.bold)),



                ),



              ),



          ],



        ),



      ),



    );



  }







  String _getPatientName() {



    String _g(String k1, [String? k2, String? k3]) =>



        (widget.patient[k1] ?? widget.patient[k2 ?? ''] ?? widget.patient[k3 ?? ''] ?? '').toString();



    return _g('TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_UNSIGNED_NAME');



  }







  Widget _buildField(PhieuField f) {



    switch (f.type) {



      case PhieuFieldType.text:



        return Padding(



          padding: const EdgeInsets.only(bottom: 12),



          child: TextFormField(



            controller: _controllers[f.key],



            decoration: InputDecoration(



              labelText: f.label + (f.required ? ' *' : ''),



              border: const OutlineInputBorder(),



              isDense: true,



            ),



            onChanged: (v) => _setVal(f.key, v),



          ),



        );



      case PhieuFieldType.textLong:



        return Padding(



          padding: const EdgeInsets.only(bottom: 12),



          child: TextFormField(



            controller: _controllers[f.key],



            maxLines: 3,



            decoration: InputDecoration(



              labelText: f.label + (f.required ? ' *' : ''),



              border: const OutlineInputBorder(),



              isDense: true,



            ),



            onChanged: (v) => _setVal(f.key, v),



          ),



        );



      case PhieuFieldType.number:



        return Padding(



          padding: const EdgeInsets.only(bottom: 12),



          child: TextFormField(



            controller: _controllers[f.key],



            keyboardType: TextInputType.number,



            decoration: InputDecoration(



              labelText: f.label + (f.required ? ' *' : ''),



              border: const OutlineInputBorder(),



              isDense: true,



            ),



            onChanged: (v) => _setVal(f.key, int.tryParse(v) ?? 0),



          ),



        );



      case PhieuFieldType.date:



        return Padding(



          padding: const EdgeInsets.only(bottom: 12),



          child: InkWell(



            onTap: () => _pickDate(f),



            child: InputDecorator(



              decoration: InputDecoration(



                labelText: f.label + (f.required ? ' *' : ''),



                border: const OutlineInputBorder(),



                isDense: true,



                suffixIcon: const Icon(Icons.calendar_today, size: 16),



              ),



              child: Text(



                _values[f.key]?.toString() ?? 'Chọn ngĂ y',



                style: TextStyle(fontSize: 14, color: _values[f.key] != null ? Colors.black : Colors.black54),



              ),



            ),



          ),



        );



      case PhieuFieldType.dateTime:



        return Padding(



          padding: const EdgeInsets.only(bottom: 12),



          child: InkWell(



            onTap: () => _pickDateTime(f),



            child: InputDecorator(



              decoration: InputDecoration(



                labelText: f.label + (f.required ? ' *' : ''),



                border: const OutlineInputBorder(),



                isDense: true,



                suffixIcon: const Icon(Icons.access_time, size: 16),



              ),



              child: Text(



                _values[f.key]?.toString() ?? 'Chọn ngĂ y giờ',



                style: TextStyle(fontSize: 14, color: _values[f.key] != null ? Colors.black : Colors.black54),



              ),



            ),



          ),



        );



      case PhieuFieldType.select:



        // v2.65.0: select field - nếu options > 5 thì dùng SearchablePicker, ngược lại dùng DropdownButtonFormField



        final options = f.options ?? [];



        if (options.length > 5) {



          // Dùng SearchablePicker cho nhiều options



          final selectedValue = _values[f.key]?.toString() ?? '';



          return Padding(



            padding: const EdgeInsets.only(bottom: 12),



            child: InkWell(



              onTap: () async {



                final picked = await SearchablePicker.show(



                  context: context,



                  items: options.map((o) => PickerItem(



                    id: o,



                    code: o.length > 10 ? o.substring(0, 10) : o,



                    name: o,



                  )).toList(),



                  title: 'Chọn ${f.label} (${options.length} mục)',



                  hintText: 'Tìm trong ${options.length} mục...',



                  multiSelect: false,



                );



                if (picked is PickerItem) {



                  setState(() => _setVal(f.key, picked.id));



                }



              },



              child: Container(



                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),



                decoration: BoxDecoration(



                  border: Border.all(color: Colors.grey.shade400),



                  borderRadius: BorderRadius.circular(4),



                ),



                child: Row(



                  children: [



                    const Icon(Icons.arrow_drop_down, color: Colors.indigo, size: 20),



                    const SizedBox(width: 4),



                    Expanded(



                      child: Text(



                        f.label + (f.required ? ' *' : ''),



                        style: const TextStyle(fontSize: 10, color: Colors.black54),



                      ),



                    ),



                    Expanded(



                      flex: 2,



                      child: Text(



                        selectedValue.isEmpty ? 'Bấm để chọn...' : selectedValue,



                        style: TextStyle(



                          fontSize: 14,



                          color: selectedValue.isNotEmpty ? Colors.black : Colors.black54,



                          fontWeight: selectedValue.isNotEmpty ? FontWeight.w500 : FontWeight.normal,



                        ),



                        maxLines: 2,



                        overflow: TextOverflow.ellipsis,



                      ),



                    ),



                    const Icon(Icons.search, size: 18, color: Colors.indigo),



                  ],



                ),



              ),



            ),



          );



        }



        // Options <= 5: dùng DropdownButtonFormField (compact)



        return Padding(



          padding: const EdgeInsets.only(bottom: 12),



          child: DropdownButtonFormField<String>(



            value: _values[f.key],



            decoration: InputDecoration(



              labelText: f.label + (f.required ? ' *' : ''),



              border: const OutlineInputBorder(),



              isDense: true,



            ),



            items: options.map((o) => DropdownMenuItem(value: o, child: Text(o, maxLines: 2, overflow: TextOverflow.ellipsis))).toList(),



            onChanged: (v) {



              setState(() => _setVal(f.key, v));



            },



          ),



        );



      case PhieuFieldType.deptSelect:



        // v2.56.0: Dropdown chọn khoa với search, lấy từ AppConstants.departments



        return Padding(



          padding: const EdgeInsets.only(bottom: 12),



          child: _buildDeptSelectField(f),



        );



      case PhieuFieldType.icdSuggest:



        // v2.98.5: Dùng IcdInputField dùng chung (multi-select)



        return IcdInputField(



          fieldKey: f.key,



          label: f.label,



          required: f.required,



          multiSelect: true,



          initialValues: _parseIcdValuesFromValues(f),



          onChanged: (values) {



            setState(() {



              _setVal(f.key, values.map((v) => v.displayText).toList());



            });



          },



        );



      case PhieuFieldType.icdText:



        // v2.98.5: ICD + text mô tả chẩn đoán (2 phần)



        return Padding(



          padding: const EdgeInsets.only(bottom: 12),



          child: Column(



            crossAxisAlignment: CrossAxisAlignment.start,



            children: [



              IcdInputField(



                fieldKey: f.key,



                label: f.label,



                required: f.required,



                multiSelect: false,



                initialValues: _parseIcdValuesFromValues(f),



                onChanged: (values) {



                  setState(() {



                    _setVal('${f.key}_icd',



                        values.isNotEmpty ? values.first.displayText : '');



                  });



                },



              ),



              // Phần 2: Text mô tả chẩn đoán chi tiết



              const SizedBox(height: 8),



              TextField(



                controller: _controllers.putIfAbsent(



                  '${f.key}_text',



                  () => TextEditingController(text: _values['${f.key}_text']?.toString() ?? ''),



                ),



                maxLines: 3,



                decoration: const InputDecoration(



                  labelText: 'Mô tả chẩn đoán chi tiết (tùy chọn)',



                  hintText: 'Ví dụ: Tăng huyết áp độ 2, nghi ngờ cơn THA kịch phát...',



                  border: OutlineInputBorder(),



                  isDense: true,



                ),



                onChanged: (v) {



                  setState(() {



                    _values['${f.key}_text'] = v;



                  });



                  _autoSaveDraft();



                },



              ),



            ],



          ),



        );



      case PhieuFieldType.bool_:



        return Padding(



          padding: const EdgeInsets.only(bottom: 8),



          child: CheckboxListTile(



            value: _values[f.key] == true,



            title: Text(f.label),



            contentPadding: EdgeInsets.zero,



            dense: true,



            onChanged: (v) => setState(() => _setVal(f.key, v ?? false)),



          ),



        );



      case PhieuFieldType.icd:



        // v2.98.5: Dung IcdInputField dung chung (don - 1 ma)



        return IcdInputField(



          fieldKey: f.key,



          label: f.label,



          required: f.required,



          multiSelect: false,



          initialValues: _parseIcdValuesFromValues(f),



          onChanged: (values) {



            setState(() {



              _setVal(f.key, values.isNotEmpty ? values.first.displayText : '');



            });



          },



        );







      case PhieuFieldType.medicine:


        return _buildListField(f);


      case PhieuFieldType.service:


        return _buildListField(f);


      case PhieuFieldType.signature:


        return Padding(


          padding: const EdgeInsets.only(bottom: 12),


          child: Container(


            padding: const EdgeInsets.all(12),


            decoration: BoxDecoration(


              color: Colors.amber.shade50,


              borderRadius: BorderRadius.circular(6),


              border: Border.all(color: Colors.amber.shade300),


            ),


            child: const Row(


              children: [


                Icon(Icons.edit_note, color: Color(0xFFFF8F00)),


                SizedBox(width: 8),


                Expanded(


                  child: Text(


                    'Ky so - se ky tren EMR portal sau khi luu',


                    style: TextStyle(fontSize: 12, color: Colors.black87),


                  ),


                ),


              ],


            ),


          ),


        );


    }


  }





  /// v2.98.5: Parse IcdValue list tu _values (cho icd/icdSuggest/icdText)


  List<IcdValue> _parseIcdValuesFromValues(PhieuField f) {


    final raw = _values[f.key];


    if (raw == null) return [];


    if (raw is List) {


      return raw


          .whereType<String>()


          .map((s) => IcdValue.tryParse(s))


          .whereType<IcdValue>()


          .toList();


    }


    if (raw is String && raw.isNotEmpty) {


      final parsed = IcdValue.tryParse(raw);


      if (parsed != null) return [parsed];


    }


    return [];


  }





  /// v2.56.0: Dropdown chon khoa tu AppConstants.departments (co search + icon)


  Widget _buildDeptSelectField(PhieuField f) {


    return InkWell(


      onTap: () async {


        final searchText = _controllers[f.key]?.text ?? '';


        final selected = await showModalBottomSheet<Map<String, dynamic>>(


          context: context,


          isScrollControlled: true,


          backgroundColor: Colors.transparent,


          useSafeArea: true,


          builder: (ctx) => DeptPicker(


            initialQuery: searchText,


            onSelected: (dept) {


              Navigator.pop(ctx, dept);


            },


          ),


        );


        if (selected != null) {


          setState(() {


            _setVal(f.key, '${selected['code']} - ${selected['name']}');


            _listValues[f.key] = [selected];


            if (!_controllers.containsKey(f.key)) {


              _controllers[f.key] = TextEditingController();


            }


            _controllers[f.key]!.text = '${selected['code']} - ${selected['name']}';


            _autoSaveDraft();


          });


        }


      },


      child: InputDecorator(


        decoration: InputDecoration(


          labelText: f.label + (f.required ? ' *' : ''),


          border: const OutlineInputBorder(),


          isDense: true,


          suffixIcon: const Icon(Icons.arrow_drop_down, size: 20),


        ),


        child: Text(


          _values[f.key]?.toString() ?? 'Bam de chon khoa...',


          style: TextStyle(


            fontSize: 14,


            color: _values[f.key] != null ? Colors.black : Colors.black54,


          ),


        ),


      ),


    );


  }





  /// v2.98.7: List field cho medicine/service - đầy đủ UI + nút "Chọn tất cả"



  Widget _buildListField(PhieuField f) {



    final items = _listValues[f.key] ?? [];



    return Padding(



      padding: const EdgeInsets.only(bottom: 12),



      child: Column(



        crossAxisAlignment: CrossAxisAlignment.start,



        children: [



          Row(



            children: [



              Expanded(



                child: Text(



                  '${f.label} (${items.length} mục)',



                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),



                ),



              ),



              if (f.required) const Text(' *', style: TextStyle(color: Colors.red)),



              // v2.98.7: Nút chọn tất cả



              if (items.isEmpty && (f.type == PhieuFieldType.medicine || f.type == PhieuFieldType.service))



                FilledButton.tonalIcon(



                  onPressed: () => _selectAllForField(f),



                  icon: const Icon(Icons.select_all, size: 14),



                  label: const Text('Chọn tất cả', style: TextStyle(fontSize: 10)),



                  style: FilledButton.styleFrom(



                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),



                    minimumSize: const Size(0, 28),



                  ),



                )



              else



                TextButton.icon(



                  onPressed: () => setState(() => _listValues[f.key] = []),



                  icon: const Icon(Icons.clear, size: 14, color: Colors.red),



                  label: const Text('Xóa hết', style: TextStyle(fontSize: 10, color: Colors.red)),



                  style: TextButton.styleFrom(



                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),



                    minimumSize: const Size(0, 28),



                  ),



                ),



            ],



          ),



          if (items.isEmpty)



            Container(



              padding: const EdgeInsets.all(8),



              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),



              child: Text(



                'Chưa có ${f.type == PhieuFieldType.medicine ? 'thuốc' : 'dịch vụ CLS'} nào - bấm "Chọn tất cả" để thêm nhanh',



                style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),



              ),



            )



          else



            ...items.asMap().entries.map((entry) {



              final i = entry.key;



              final item = entry.value as Map<String, dynamic>;



              return Container(



                margin: const EdgeInsets.only(top: 4),



                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),



                decoration: BoxDecoration(



                  color: Colors.blue.shade50,



                  borderRadius: BorderRadius.circular(4),



                  border: Border.all(color: Colors.blue.shade200),



                ),



                child: Row(



                  children: [



                    const Icon(Icons.check_circle, size: 14, color: Colors.blue),



                    const SizedBox(width: 6),



                    Expanded(



                      child: Text(



                        '${item['name'] ?? item['code'] ?? item.toString()}',



                        style: const TextStyle(fontSize: 12),



                        maxLines: 2, overflow: TextOverflow.ellipsis,



                      ),



                    ),



                    IconButton(



                      icon: const Icon(Icons.close, size: 14, color: Colors.red),



                      padding: EdgeInsets.zero,



                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),



                      onPressed: () => setState(() {



                        _listValues[f.key]!.removeAt(i);



                      }),



                    ),



                  ],



                ),



              );



            }),



        ],



      ),



    );



  }







  /// v2.98.7: Chọn tất cả cho field medicine/service



  Future<void> _selectAllForField(PhieuField f) async {



    if (f.type == PhieuFieldType.medicine) {



      final all = HisCatalogService.instance.searchMedicines('', limit: 500);



      setState(() {



        _listValues[f.key] = all.map((m) => {'code': m.code, 'name': m.name, 'id': m.code}).toList();



      });



      if (mounted) {



        ScaffoldMessenger.of(context).showSnackBar(



          SnackBar(content: Text('Đã chọn tất cả ${all.length} thuốc'), backgroundColor: Colors.teal),



        );



      }



    } else if (f.type == PhieuFieldType.service) {



      final all = HisCatalogService.instance.searchServices('', limit: 500);



      setState(() {



        _listValues[f.key] = all.map((s) => {'code': s.code, 'name': s.name, 'id': s.code}).toList();



      });



      if (mounted) {



        ScaffoldMessenger.of(context).showSnackBar(



          SnackBar(content: Text('Đã chọn tất cả ${all.length} CLS'), backgroundColor: Colors.teal),



        );



      }



    }



  }





  /// v2.98.5: Placeholder - show date picker


  Future<void> _pickDate(PhieuField f) async {


    final picked = await showDatePicker(


      context: context,


      firstDate: DateTime(2020),


      lastDate: DateTime(2030),


      initialDate: DateTime.now(),


    );


    if (picked != null) {


      setState(() {


        _setVal(f.key, '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');


      });


      _autoSaveDraft();


    }


  }





  /// v2.98.5: Placeholder - show date time picker


  Future<void> _pickDateTime(PhieuField f) async {


    final picked = await showDatePicker(


      context: context,


      firstDate: DateTime(2020),


      lastDate: DateTime(2030),


      initialDate: DateTime.now(),


    );


    if (picked != null) {


      setState(() {


        _setVal(f.key, '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')} 00:00:00');


      });


      _autoSaveDraft();


    }


  }





  /// v3.0.46: 3 nút save - [Lưu] [Lưu ký] [Ký VNPT SmartCA] theo mẫu Bàn giao BN



  /// - Lưu: chỉ lưu local



  /// - Lưu ký: lưu + ký tay + đẩy EMR (IsFinishSign=true) - dùng legacy hisPro.post MPS Save



  /// - Ký VNPT SmartCA: lưu + ký PKCS#7 qua app VNPT + đẩy EMR - dùng PhieuSaveService



  Widget _buildSaveButtons() {



    return Column(



      mainAxisSize: MainAxisSize.min,



      children: [



        Row(



          children: [



            Expanded(



              child: OutlinedButton.icon(



                onPressed: _saving ? null : () => _save(mode: SaveMode.local),



                icon: const Icon(Icons.save_outlined, size: 16),



                label: const Text("Lưu", style: TextStyle(fontSize: 12)),



                style: OutlinedButton.styleFrom(



                  foregroundColor: Colors.indigo,



                  side: const BorderSide(color: Colors.indigo, width: 1.5),



                  padding: const EdgeInsets.symmetric(vertical: 12),



                ),



              ),



            ),



            const SizedBox(width: 4),



            Expanded(



              child: FilledButton.icon(



                onPressed: _saving ? null : () => _save(mode: SaveMode.signed),



                icon: const Icon(Icons.draw, size: 16),



                label: const Text("Lưu ký", style: TextStyle(fontSize: 12)),



                style: FilledButton.styleFrom(



                  backgroundColor: Colors.green.shade700,



                  padding: const EdgeInsets.symmetric(vertical: 12),



                ),



              ),



            ),



          ],



        ),



        const SizedBox(height: 6),



        // v3.0.46: Nút Ký VNPT SmartCA - ký PKCS#7 thật qua app VNPT



        SizedBox(



            width: double.infinity,



            child: FilledButton.tonalIcon(



              icon: const Icon(Icons.verified, size: 16),



              label: const Text("Ký VNPT SmartCA", style: TextStyle(fontSize: 12)),



              style: FilledButton.styleFrom(



                backgroundColor: Colors.purple.shade50,



                foregroundColor: Colors.purple.shade800,



                padding: const EdgeInsets.symmetric(vertical: 10),



              ),



              onPressed: _saving ? null : () => _save(mode: SaveMode.signed, useVnptSignature: true),



            ),



          ),



      ],



    );



  }







  /// v2.98.7: Save button only (no EMR) - chỉ 1 nút "Lưu"



  Widget _buildSaveButtonOnly() {



    return SizedBox(



      width: double.infinity,



      child: FilledButton.icon(



        onPressed: _saving ? null : () => _save(mode: SaveMode.local),



        icon: const Icon(Icons.save, size: 18),



        label: const Text("Lưu"),



        style: FilledButton.styleFrom(



          backgroundColor: Colors.indigo,



          padding: const EdgeInsets.symmetric(vertical: 14),



        ),



      ),



    );



  }





  /// v2.98.5: Xóa _save và _saveDraft placeholder (đã có _save ở line 245)



}


