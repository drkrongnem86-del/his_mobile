/// Diacritic-insensitive search helpers for Vietnamese text.
/// "Kỳ" matches "Ky", "Kỳ", "KY", etc.

/// Loại bỏ dấu tiếng Việt: Kỳ → Ky, Ường → Uong
String removeDiacritics(String s) {
  const withDia = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ';
  const withoutDia = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyydAAAAAAAAAAAAAAAAAEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD';
  var result = s;
  for (var i = 0; i < withDia.length; i++) {
    result = result.replaceAll(withDia[i], withoutDia[i]);
  }
  return result;
}

/// Check if [query] appears in [text] (both diacritic-insensitive, case-insensitive).
bool matchesVietnamese(String text, String query) {
  if (query.isEmpty) return true;
  return removeDiacritics(text.toLowerCase()).contains(removeDiacritics(query.toLowerCase()));
}
