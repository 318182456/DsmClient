import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'torrent_client.dart';

/// Separate records for each NAS and each normalized Dockhand service URL.
class DockhandCredentials {
  final FlutterSecureStorage storage;
  const DockhandCredentials({this.storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true))});
  static String key(String profile, String address) => 'dockhand_v1_${sha256.convert(
    utf8.encode(jsonEncode([profile ?? '', TorrentClient.validate(address).toString()])))}';
  Future<Map> read(String profile, String address) async {
    final value = await storage.read(key: key(profile, address));
    if (value == null) return null;
    final record = jsonDecode(value);
    return record is Map && ['local','token'].contains(record['mode']) ? record : null;
  }
  Future<void> save(String profile, String address, Map value) => storage.write(
    key: key(profile, address), value: jsonEncode({
      'mode': value['mode'], 'account': value['account'] ?? '',
      'password': value['mode'] == 'local' ? value['password'] : '',
      'token': value['mode'] == 'token' ? value['token'] : '',
    }));
  Future<void> delete(String profile, String address) => storage.delete(key: key(profile, address));
}
