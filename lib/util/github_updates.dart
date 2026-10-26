// @dart=2.10
import 'dart:convert';
import 'dart:io';

import '../models/app_release.dart';

/// Uses its own HTTPS client, with no NAS cookies, tokens or TLS overrides.
class GithubUpdates {
  static AppRelease _cached;
  static DateTime _checked;
  static Future<AppRelease> _pending;

  static Future<AppRelease> latest({bool force = false}) {
    if (!force &&
        _checked != null &&
        DateTime.now().difference(_checked) < Duration(minutes: 10)) {
      return Future.value(_cached);
    }
    return _pending ??= _load().then((value) {
      _cached = value;
      _checked = DateTime.now();
      return value;
    }).whenComplete(() => _pending = null);
  }

  static Future<dynamic> _json(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri).timeout(Duration(seconds: 15));
    request.headers
        .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    request.headers.set(HttpHeaders.userAgentHeader, 'DsmClient-Update');
    final response = await request.close().timeout(Duration(seconds: 20));
    if (response.statusCode != 200) {
      await response.drain();
      throw HttpException('GitHub returned ${response.statusCode}');
    }
    return jsonDecode(await utf8.decoder
        .bind(response)
        .join()
        .timeout(Duration(seconds: 20)));
  }

  static Future<AppRelease> _load() async {
    final client = HttpClient()..connectionTimeout = Duration(seconds: 15);
    try {
      final releases = await _json(
          client,
          Uri.https('api.github.com',
              '/repos/${AppRelease.repository}/releases', {'per_page': '10'}));
      if (releases is! List) throw FormatException('Invalid release list');
      AppRelease latest;
      for (final release in releases.whereType<Map>()) {
        if (release['draft'] == true) continue;
        final tag = '${release['tag_name'] ?? ''}';
        final assets = (release['assets'] as List ?? []).whereType<Map>();
        final manifest = assets.firstWhere(
            (item) =>
                item['name'] == 'update-arm64.json' &&
                item['state'] == 'uploaded',
            orElse: () => null);
        if (manifest == null ||
            !AppRelease.trustedAssetUrl(manifest['browser_download_url'], tag))
          continue;
        final value =
            await _json(client, Uri.parse(manifest['browser_download_url']));
        final candidate = AppRelease.fromManifest(value, release);
        if (latest == null || candidate.buildNumber > latest.buildNumber)
          latest = candidate;
      }
      return latest;
    } finally {
      client.close(force: true);
    }
  }
}
