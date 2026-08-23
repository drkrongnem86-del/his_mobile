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
  // v3.0.166: Fix - map CP1252 chars (€ = 0x80, Š = 0x8A, ...) sang byte values
  // trước khi thử decode UTF-8. Nếu không, các ký tự như '€' (U+20AC) sẽ bị skip.
  if (_hasMojibake(s)) {
    try {
      // Map từng rune sang byte value (CP1252 mapping cho > 0x7F)
      final bytes = <int>[];
      var allValid = true;
      for (final r in s.runes) {
        final byte = _cp1252Byte(r);
        if (byte != null) {
          bytes.add(byte);
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

/// v3.0.166: Map Unicode rune sang byte value theo CP1252
/// - 0x00-0x7F: ASCII, giữ nguyên
/// - 0xA0-0xFF: Latin-1 supplement, giữ nguyên (CP1252 = Latin-1 ở dải này)
/// - 0x80-0x9F: CP1252 specific (€, Š, š, Ž, ž, ... - KHÔNG có trong Latin-1/UTF-8 control chars)
/// Returns null nếu rune không phải CP1252 char
int? _cp1252Byte(int rune) {
  if (rune < 0x80) return rune; // ASCII
  if (rune >= 0xA0 && rune < 0x100) return rune; // Latin-1 supplement (giống CP1252)
  // CP1252 0x80-0x9F mapping
  switch (rune) {
    case 0x20AC: return 0x80; // €
    case 0x201A: return 0x82; // ‚
    case 0x0192: return 0x83; // ƒ
    case 0x201E: return 0x84; // „
    case 0x2026: return 0x85; // …
    case 0x2020: return 0x86; // †
    case 0x2021: return 0x87; // ‡
    case 0x02C6: return 0x88; // ˆ
    case 0x2030: return 0x89; // ‰
    case 0x0160: return 0x8A; // Š
    case 0x2039: return 0x8B; // ‹
    case 0x0152: return 0x8C; // Œ
    case 0x017D: return 0x8E; // Ž
    case 0x2018: return 0x91; // ‘
    case 0x2019: return 0x92; // ’
    case 0x201C: return 0x93; // "
    case 0x201D: return 0x94; // "
    case 0x2022: return 0x95; // •
    case 0x2013: return 0x96; // –
    case 0x2014: return 0x97; // —
    case 0x02DC: return 0x98; // ˜
    case 0x2122: return 0x99; // ™
    case 0x0161: return 0x9A; // š
    case 0x203A: return 0x9B; // ›
    case 0x0153: return 0x9C; // œ
    case 0x017E: return 0x9E; // ž
    case 0x0178: return 0x9F; // Ÿ
    default: return null; // Không phải CP1252 char
  }
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
