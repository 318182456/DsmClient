import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dsm_client/models/nas_package.dart';
import 'dsm_compatibility.dart';
import 'function.dart';

class ProgramCatalogCache {
  static const lifetime = Duration(minutes: 5);
  static const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true));
  static final memory = <String, Map>{};
  static String get scope =>
      '${DsmCompatibility.connectionKey(Util.baseUrl)}|${Util.account}';
  static String key(String scope) =>
      'program_catalog_v1_${sha256.convert(utf8.encode(scope))}';
  static bool fresh(Map snapshot) {
    final age =
        DateTime.now().millisecondsSinceEpoch - (snapshot['time'] as num ?? 0);
    return age >= 0 && age < lifetime.inMilliseconds;
  }

  static Future<Map> read(String scope) async {
    if (memory.containsKey(scope)) return memory[scope];
    try {
      final raw = await storage.read(key: key(scope));
      if (raw == null || raw.length > 1024 * 1024) return null;
      final data = jsonDecode(raw);
      if (data is! Map ||
          data['packages'] is! List ||
          data['containers'] is! List) return null;
      memory[scope] = data;
      return data;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(
      String scope, List<NasPackage> packages, List<Map> containers) async {
    final data = {
      'time': DateTime.now().millisecondsSinceEpoch,
      'packages': [
        for (final p in packages)
          {
            'id': p.id,
            'name': p.name,
            'version': p.version,
            'additional': {
              'status': p.status,
              'description': p.description,
              'dsm_apps': p.appIds,
              'startable': p.canControl
            }
          }
      ],
      'containers': [
        for (final c in containers)
          {
            'name': c['name'],
            'image': c['image'],
            if (c['icon'] is String) 'icon': c['icon']
          }
      ]
    };
    if (memory.length >= 12 && !memory.containsKey(scope))
      memory.remove(memory.keys.first);
    memory[scope] = data;
    try {
      await storage.write(key: key(scope), value: jsonEncode(data));
    } catch (_) {}
  }
}
