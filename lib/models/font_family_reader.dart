// @dart=2.10
import 'dart:typed_data';

/// Read OpenType naming tables locally. Only family names go to Office's API.
class FontFamilyReader {
  static List<String> read(List<int> bytes) {
    if (bytes.length < 12 || bytes.length > 32 * 1024 * 1024)
      throw FormatException('字体文件为空、损坏或超过 32 MB');
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    void bounds(int offset, int size) {
      if (offset < 0 || size < 0 || offset + size > data.lengthInBytes)
        throw FormatException('字体文件结构损坏');
    }

    int u16(int offset) {
      bounds(offset, 2);
      return data.getUint16(offset);
    }

    int u32(int offset) {
      bounds(offset, 4);
      return data.getUint32(offset);
    }

    final offsets = <int>[];
    if (u32(0) == 0x74746366) {
      final count = u32(8);
      if (count < 1 || count > 256) throw FormatException('字体集合数量无效');
      bounds(12, count * 4);
      for (var i = 0; i < count; i++) offsets.add(u32(12 + i * 4));
    } else
      offsets.add(0);
    final families = <String>{};
    for (final base in offsets) {
      final signature = u32(base);
      if (!const {0x00010000, 0x4f54544f, 0x74727565}.contains(signature))
        throw FormatException('请选择 TTF、OTF 或 TTC 字体文件');
      final count = u16(base + 4);
      if (count > 4096) throw FormatException('字体表数量无效');
      bounds(base + 12, count * 16);
      for (var i = 0; i < count; i++) {
        final table = base + 12 + i * 16;
        if (u32(table) != 0x6e616d65) continue;
        final start = u32(table + 8), length = u32(table + 12);
        bounds(start, length);
        if (length < 6) throw FormatException('字体名称表损坏');
        final records = u16(start + 2), storage = u16(start + 4);
        if (6 + records * 12 > length || storage > length)
          throw FormatException('字体名称表损坏');
        String selected;
        var best = -1;
        for (var n = 0; n < records; n++) {
          final r = start + 6 + n * 12,
              platform = u16(r),
              encoding = u16(r + 2),
              language = u16(r + 4),
              id = u16(r + 6),
              size = u16(r + 8),
              offset = u16(r + 10);
          if (id != 1 && id != 16) continue;
          if (storage + offset + size > length)
            throw FormatException('字体名称超出数据范围');
          final pos = start + storage + offset;
          String name;
          if (platform == 0 ||
              (platform == 3 && (encoding == 1 || encoding == 10))) {
            if (size.isOdd) continue;
            name = String.fromCharCodes(
                [for (var j = 0; j < size; j += 2) u16(pos + j)]);
          } else if (platform == 1 && encoding == 0) {
            final chars = bytes.sublist(pos, pos + size);
            if (chars.any((v) => v > 127)) continue;
            name = String.fromCharCodes(chars);
          } else
            continue;
          name = name.replaceFirst(RegExp(r'^\.'), '').trim();
          if (name.isEmpty ||
              name.length > 256 ||
              RegExp(r'[\x00-\x1f]').hasMatch(name)) continue;
          final score = (id == 16 ? 100 : 0) +
              (platform == 3 ? 20 : 0) +
              (language == 0x409 ? 10 : 0);
          if (score > best) {
            best = score;
            selected = name;
          }
        }
        if (selected != null) families.add(selected);
      }
    }
    if (families.isEmpty) throw FormatException('未找到可登记的字体家族名称');
    return families.toList();
  }
}
