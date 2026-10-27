import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TorrentRssStore {
  final String profile;
  const TorrentRssStore(this.profile);
  static const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true));
  String get key => 'torrent_rss_v1_${sha256.convert(utf8.encode(profile))}';
  Future<List<Map>> read() async {
    final raw = await storage.read(key: key);
    if (raw == null) return [];
    final data = jsonDecode(raw);
    if (data is! List) throw FormatException('订阅数据格式不正确');
    return data.whereType<Map>().toList();
  }

  Future<void> save(List<Map> feeds) =>
      storage.write(key: key, value: jsonEncode(feeds));
}
