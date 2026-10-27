// @dart=2.10
import 'dart:typed_data';
import '../lib/models/display_text.dart';
import '../lib/models/font_family_reader.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Uint8List font(String family, {int nameId = 1}) {
  final chars = family.codeUnits,
      bytes = Uint8List(28 + 18 + chars.length * 2),
      d = ByteData.sublistView(bytes);
  d.setUint32(0, 0x00010000);
  d.setUint16(4, 1);
  d.setUint32(12, 0x6e616d65);
  d.setUint32(20, 28);
  d.setUint32(24, 18 + chars.length * 2);
  d.setUint16(30, 1);
  d.setUint16(32, 18);
  d.setUint16(34, 3);
  d.setUint16(36, 1);
  d.setUint16(38, 0x409);
  d.setUint16(40, nameId);
  d.setUint16(42, chars.length * 2);
  for (var i = 0; i < chars.length; i++) d.setUint16(46 + i * 2, chars[i]);
  return bytes;
}

void main() {
  check(
      DisplayText.field('downloadDir') == '下载目录' &&
          DisplayText.field('NetworkSettings') == '网络配置',
      'Both service key styles translated');
  check(DisplayText.value('status', 4, context: 'transmission') == '下载中',
      'Transmission activity enum');
  check(DisplayText.value('status', 4, context: 'qb-tracker') == '未正常工作',
      'Tracker enum must not be interpreted as torrent activity');
  check(DisplayText.tracker({'status': 6, 'msg': ''}) == '无法连接',
      'qB 5.3 unreachable tracker status');
  check(
      DisplayText.status('exited') == '已停止' &&
          DisplayText.status('Up 2 hours (healthy)').contains('小时'),
      'Container states and duration translated');
  check(
      DisplayText.value('name', 'running') == 'running' &&
          DisplayText.value('path', '/running/name') == '/running/name',
      'Names and paths are user data');
  check(
      DisplayText.field('new_vendor_key') == 'new_vendor_key' &&
          DisplayText.value('status', 'future-state') == 'future-state',
      'Unknown schema remains inspectable');
  check(
      DisplayText.value('name', 'always', context: 'restart-policy') == '始终重启',
      'Restart policy translated only in policy context');
  final single = font('示例字体');
  check(FontFamilyReader.read(single).single == '示例字体',
      'Read OpenType UTF-16BE family');
  check(FontFamilyReader.read(font('Example', nameId: 16)).single == 'Example',
      'Typographic family supported');
  final collection = Uint8List(single.length + 16),
      header = ByteData.sublistView(collection);
  header.setUint32(0, 0x74746366);
  header.setUint32(4, 0x00010000);
  header.setUint32(8, 1);
  header.setUint32(12, 16);
  collection.setRange(16, collection.length, single);
  header.setUint32(36, 44);
  check(FontFamilyReader.read(collection).single == '示例字体',
      'TTC table offsets are absolute');
  for (final data in [
    Uint8List(0),
    Uint8List(12),
    single.sublist(0, single.length - 1)
  ]) {
    var rejected = false;
    try {
      FontFamilyReader.read(data);
    } on FormatException {
      rejected = true;
    }
    check(rejected, 'Reject malformed or truncated fonts');
  }
  print(
      'Chinese presentation boundaries and local OpenType name parsing passed');
}
