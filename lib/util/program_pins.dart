import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'function.dart';
import 'dsm_compatibility.dart';

class ProgramPins {
  static final changed = ValueNotifier<int>(0);
  static String get key =>
      'program_pins_v1_${sha256.convert(utf8.encode('${DsmCompatibility.connectionKey(Util.baseUrl)}|${Util.account}'))}';
  static Future<List<String>> read([String scope]) async {
    final raw = await Util.getStorage(scope ?? key);
    if (raw == null || raw.isEmpty) return [];
    final value = jsonDecode(raw);
    return value is List ? value.whereType<String>().toSet().toList() : [];
  }

  static Future<void> toggle(String id) async {
    final scope = key, ids = await read(key);
    if (ids.contains(id))
      ids.remove(id);
    else
      ids.add(id);
    await Util.setStorage(scope, jsonEncode(ids));
    changed.value++;
  }
  static Future<void> replace(List<String> ids, {String scope}) async {
    final target = scope ?? key;
    if (target != key) throw StateError('NAS 账号已改变，请重新选择');
    await Util.setStorage(target, jsonEncode(ids.toSet().toList()));
    changed.value++;
  }

  static Future<void> move(String id, int delta) async {
    final scope = key, ids = await read(key);
    final index = ids.indexOf(id);
    if (index < 0) return;
    final target = (index + delta).clamp(0, ids.length - 1) as int;
    ids.removeAt(index);
    ids.insert(target, id);
    await Util.setStorage(scope, jsonEncode(ids));
    changed.value++;
  }
}
