"""Test mojibake fix với data thật từ depttran_response.json"""
import json
import sys

# Read sample response
with open(r'C:\Users\drkro\Desktop\depttran_response.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

# Test cases: mojibake -> expected
test_cases = [
    ('Sáº¦M THá»Š THUYá»€N', 'SẦM THỊ THUYỀN'),
    ('NghÄ©a', 'Nghĩa'),
    ('Háº£i', 'Hải'),
    ('KhÃ¡nh HÃ²a', 'Khánh Hòa'),
    ('Cháº¥n thÆ°Æ¡ng', 'Chấn thương'),
    ('Ä‘áº¡i', 'đại'),
    ('Ä‘Ã¡', 'đá'),
    ('Ä‘á»“', 'đồ'),
    ('Ä‘áº§u', 'đầu'),
    ('Tá»•n thÆ°Æ¡ng', 'Tổn thương'),
    ('Cáº¥p Cá»©u', 'Cấp Cứu'),
    ('Ná»¯', 'Nữ'),
]

def cp1252_byte(rune):
    """Map Unicode rune to CP1252 byte value (for chars >= 0x80)"""
    if rune < 0x80:
        return rune
    if 0xA0 <= rune < 0x100:
        return rune
    cp1252_map = {
        0x20AC: 0x80,  # €
        0x201A: 0x82,  # ‚
        0x0192: 0x83,  # ƒ
        0x201E: 0x84,  # „
        0x2026: 0x85,  # …
        0x2020: 0x86,  # †
        0x2021: 0x87,  # ‡
        0x02C6: 0x88,  # ˆ
        0x2030: 0x89,  # ‰
        0x0160: 0x8A,  # Š
        0x2039: 0x8B,  # ‹
        0x0152: 0x8C,  # Œ
        0x017D: 0x8E,  # Ž
        0x2018: 0x91,  # ‘
        0x2019: 0x92,  # ’
        0x201C: 0x93,  # "
        0x201D: 0x94,  # "
        0x2022: 0x95,  # •
        0x2013: 0x96,  # –
        0x2014: 0x97,  # —
        0x02DC: 0x98,  # ˜
        0x2122: 0x99,  # ™
        0x0161: 0x9A,  # š
        0x203A: 0x9B,  # ›
        0x0153: 0x9C,  # œ
        0x017E: 0x9E,  # ž
        0x0178: 0x9F,  # Ÿ
    }
    return cp1252_map.get(rune)

def decode_utf8(bytes_list):
    """Decode bytes as UTF-8"""
    result = []
    i = 0
    while i < len(bytes_list):
        b = bytes_list[i]
        if b < 0x80:
            result.append(chr(b))
            i += 1
        elif (b & 0xE0) == 0xC0:
            if i + 1 >= len(bytes_list):
                return None
            b1 = bytes_list[i + 1]
            if (b1 & 0xC0) != 0x80:
                return None
            code = ((b & 0x1F) << 6) | (b1 & 0x3F)
            result.append(chr(code))
            i += 2
        elif (b & 0xF0) == 0xE0:
            if i + 2 >= len(bytes_list):
                return None
            b1 = bytes_list[i + 1]
            b2 = bytes_list[i + 2]
            if (b1 & 0xC0) != 0x80 or (b2 & 0xC0) != 0x80:
                return None
            code = ((b & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
            result.append(chr(code))
            i += 3
        else:
            return None
    return ''.join(result)

def fix_mojibake(s):
    """Test the v3.0.166 fix"""
    bytes_list = []
    all_valid = True
    for ch in s:
        rune = ord(ch)
        byte = cp1252_byte(rune)
        if byte is not None:
            bytes_list.append(byte)
        else:
            all_valid = False
            break
    if all_valid and bytes_list:
        return decode_utf8(bytes_list)
    return None

# Test all cases
print('=== Test mojibake fix v3.0.166 ===')
passed = 0
failed = 0
for mojibake, expected in test_cases:
    fixed = fix_mojibake(mojibake)
    status = '✅' if fixed == expected else '❌'
    if fixed == expected:
        passed += 1
    else:
        failed += 1
    print(f'{status} {mojibake!r:40} → {fixed!r:40} (expected: {expected!r})')

print(f'\nResult: {passed} passed, {failed} failed')

# Test with real data
print('\n=== Test với data thật từ depttran_response.json ===')
if data.get('Data'):
    for item in data['Data'][:2]:
        name = item.get('TDL_PATIENT_NAME', '')
        if name:
            fixed = fix_mojibake(name)
            print(f'Mojibake: {name!r}')
            print(f'Fixed:    {fixed!r}')

        addr = item.get('TDL_PATIENT_ADDRESS', '')
        if addr:
            fixed = fix_mojibake(addr)
            print(f'Address Mojibake: {addr!r}')
            print(f'Address Fixed:    {fixed!r}')

        dept = item.get('DEPARTMENT_NAME', '')
        if dept:
            fixed = fix_mojibake(dept)
            print(f'Dept Mojibake: {dept!r}')
            print(f'Dept Fixed:    {fixed!r}')
        print()
