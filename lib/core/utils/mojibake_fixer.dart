/// Vietnamese mojibake fixer for API responses.
/// API trả về text bị double-encoded: "NGUYỄN" (6 bytes) thay vì "NGUYỄN" (8 bytes).
/// Pattern: mỗi ký tự có dấu tiếng Việt bị biến thành 2-3 ký tự lạ.
/// v2.89.0: Rewrite - fix compile errors from earlier corrupt edits
library;

/// Fix double-encoded Vietnamese text. Returns fixed string.
/// If no mojibake detected, returns input unchanged.
String fixVietnameseMojibake(String input) {
  if (input.isEmpty) return input;
  var s = input;

  // Step 1: Replace common mojibake patterns
  // Format: key = mojibake string, value = correct Vietnamese
  final mojibakeTable = <String, String>{
    // 'Ã' + 1 char (most common double-encoded)
    'á': 'á', 'Ã ': 'à', 'ã': 'ã', 'ä': 'ä',
    'è': 'è', 'é': 'é', 'ê': 'ê', 'ë': 'ë',
    'ì': 'ì', 'í': 'í', 'î': 'î', 'ï': 'ï',
    'ò': 'ò', 'ó': 'ó', 'ô': 'ô', 'õ': 'õ',
    'ù': 'ù', 'ú': 'ú', 'û': 'û', 'ü': 'ü',
    'ý': 'ý', 'ÿ': 'ÿ',
    'Ä' + 'Ÿ': 'đ', // 'đ' = 'đ'
    'Ä' + 'š': 'Đ', // 'Đ' = 'Đ'
    // 'á' + 2 chars (3-byte UTF-8 mojibake)
    'á»' + '¡': 'ẹ', 'á»' + '¢': 'ẻ', 'á»' + '£': 'ẽ',
    'á»' + '¤': 'ế', 'á»' + '¥': 'ề', 'á»' + '¦': 'ể',
    'á»' + '§': 'ễ', 'á»' + '¨': 'ệ',
    'á»' + '°': 'ọ', 'á»' + '±': 'ỏ', 'á»' + '²': 'õ',
    'á»' + '³': 'ố', 'á»' + '´': 'ồ', 'á»' + 'µ': 'ổ',
    'á»' + '¶': 'ỗ', 'á»' + '·': 'ộ', 'á»' + '¸': 'ớ',
    'á»' + '¹': 'ờ', 'á»' + 'º': 'ở', 'á»' + '»': 'ỡ',
    'á»' + '¼': 'ợ', 'á»' + '½': 'ụ', 'á»' + '¾': 'ủ',
    'á»' + '¿': 'ũ',
    'áº' + '£': 'ả', 'áº' + '¡': 'ạ', 'áº' + '¤': 'ậ',
    'áº' + '¥': 'ầ', 'áº' + '¦': 'ẩ', 'áº' + '§': 'ẫ',
    'áº' + '¨': 'ặ', 'áº' + '©': 'ằ', 'áº' + 'ª': 'ắ',
    'áº' + '«': 'ẳ', 'áº' + '¬': 'ẵ',
  };

  for (final entry in mojibakeTable.entries) {
    if (s.contains(entry.key)) {
      s = s.replaceAll(entry.key, entry.value);
    }
  }

  // Step 2: Try CP1252 roundtrip if still has mojibake
  if (_hasMojibake(s)) {
    try {
      // Treat each char code as 1 byte, decode as UTF-8
      final bytes = <int>[];
      var allValid = true;
      for (final r in s.runes) {
        if (r < 256) {
          bytes.add(r);
        } else {
          allValid = false;
          break;
        }
      }
      if (allValid && bytes.isNotEmpty) {
        final fixed = _decodeUtf8(bytes);
        if (fixed != null && !_hasMojibake(fixed)) {
          return fixed;
        }
      }
    } catch (_) {}
  }

  return s;
}

String? _decodeUtf8(List<int> bytes) {
  try {
    final sb = StringBuffer();
    var i = 0;
    while (i < bytes.length) {
      final b = bytes[i];
      if (b < 0x80) {
        sb.writeCharCode(b);
        i++;
      } else if ((b & 0xE0) == 0xC0) {
        if (i + 1 >= bytes.length) return null;
        final b1 = bytes[i + 1];
        if ((b1 & 0xC0) != 0x80) return null;
        final code = ((b & 0x1F) << 6) | (b1 & 0x3F);
        sb.writeCharCode(code);
        i += 2;
      } else if ((b & 0xF0) == 0xE0) {
        if (i + 2 >= bytes.length) return null;
        final b1 = bytes[i + 1];
        final b2 = bytes[i + 2];
        if ((b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80) return null;
        final code = ((b & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F);
        sb.writeCharCode(code);
        i += 3;
      } else if ((b & 0xF8) == 0xF0) {
        if (i + 3 >= bytes.length) return null;
        final b1 = bytes[i + 1];
        final b2 = bytes[i + 2];
        final b3 = bytes[i + 3];
        if ((b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80) return null;
        final code = ((b & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F);
        sb.writeCharCode(code);
        i += 4;
      } else {
        return null;
      }
    }
    return sb.toString();
  } catch (_) {
    return null;
  }
}

bool _hasMojibake(String s) {
  // Detect common mojibake markers
  return s.contains('Ã') ||
      s.contains('Ä') ||
      s.contains('á»') ||
      s.contains('áº') ||
      s.contains('Â');
}

/// v2.37.0: Chuẩn hóa tên BN đúng in hoa/thường
/// "nguyễn văn a" → "Nguyễn Văn A"
/// "NGUYEN VAN A" → "Nguyen Van A"
String capitalizeVietnameseName(String raw) {
  if (raw.isEmpty) return raw;
  final s = fixVietnameseMojibake(raw).trim();
  return s.split(RegExp(r'\s+')).map((w) {
    if (w.isEmpty) return w;
    if (RegExp(r'^\d+$').hasMatch(w)) return w;
    final lower = w.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }).join(' ');
}
