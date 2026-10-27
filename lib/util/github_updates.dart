// @dart=2.10
import 'dart:convert';
import 'dart:io';

import '../models/app_release.dart';
import 'update_route.dart';

/// Independent HTTPS client; no NAS cookies, tokens or TLS overrides.
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

  /// Keep discovery on the same domestic route as APK downloads. The reader
  /// remains independent of NAS authentication and certificate overrides.
  static Future<String> routedBody(
      Uri uri, Future<String> Function(Uri) reader) async {
    try {
      return await reader(Uri.parse('${UpdateRoute.domestic}$uri'));
    } catch (_) {
      return await reader(uri);
    }
  }

  static Future<String> _body(HttpClient client, Uri uri,
          {String accept = 'application/vnd.github+json'}) =>
      routedBody(uri, (target) => _directBody(client, target, accept: accept));

  static Future<String> _directBody(HttpClient client, Uri uri,
      {String accept = 'application/vnd.github+json'}) async {
    final request = await client.getUrl(uri).timeout(Duration(seconds: 15));
    request.headers.set(HttpHeaders.acceptHeader, accept);
    request.headers.set(HttpHeaders.userAgentHeader, 'DsmClient-Update');
    final response = await request.close().timeout(Duration(seconds: 20));
    if (response.statusCode != 200) {
      await response.drain();
      throw HttpException('GitHub returned ${response.statusCode}');
    }
    return utf8.decoder.bind(response).join().timeout(Duration(seconds: 20));
  }

  static Future<dynamic> _json(HttpClient client, Uri uri) async =>
      jsonDecode(await _body(client, uri));

  static List<String> tagsFromFeed(String feed) {
    final expression = RegExp('<link\\b[^>]*\\bhref="https://github\\.com/' +
        RegExp.escape(AppRelease.repository) +
        '/releases/tag/([^\"]+)"[^>]*>');
    final tags = <String>{};
    for (final match in expression.allMatches(feed)) {
      try {
        final tag = Uri.decodeComponent(match.group(1));
        if (RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(tag) && !tag.contains('..'))
          tags.add(tag);
      } catch (_) {}
    }
    return tags.toList();
  }

  static Future<AppRelease> _fromApi(HttpClient client) async {
    final releases = await _json(
        client,
        Uri.https('api.github.com', '/repos/${AppRelease.repository}/releases',
            {'per_page': '10'}));
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
  }

  static Future<AppRelease> _fromFeed(HttpClient client) async {
    final feed = await _body(client,
        Uri.parse('https://github.com/${AppRelease.repository}/releases.atom'),
        accept: 'application/atom+xml');
    AppRelease latest;
    for (final tag in tagsFromFeed(feed).take(10)) {
      try {
        final value = await _json(
            client,
            Uri.parse(
                'https://github.com/${AppRelease.repository}/releases/download/${Uri.encodeComponent(tag)}/update-arm64.json'));
        final candidate = AppRelease.fromPublishedManifest(value, tag,
            notes: '修复与功能改进，详细说明可在版本页面查看。');
        if (latest == null || candidate.buildNumber > latest.buildNumber)
          latest = candidate;
      } on HttpException catch (error) {
        // Older releases predate the in-app update manifest.
        if (error.message != 'GitHub returned 404') rethrow;
      }
    }
    return latest;
  }

  static Future<AppRelease> _load() async {
    final client = HttpClient()..connectionTimeout = Duration(seconds: 15);
    try {
      try {
        return await _fromApi(client);
      } catch (_) {
        return await _fromFeed(client);
      }
    } finally {
      client.close(force: true);
    }
  }
}
