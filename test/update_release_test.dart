// @dart=2.10
import '../lib/models/app_release.dart';
import '../lib/util/github_updates.dart';

void expect(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final calls = <Uri>[];
  final endpoint =
      Uri.parse('https://api.github.com/repos/318182456/DsmClient/releases');
  final body = await GithubUpdates.routedBody(endpoint, (uri) async {
    calls.add(uri);
    return 'proxy-response';
  });
  expect(
      body == 'proxy-response' && calls.single.host == 'edgeone.gh-proxy.org',
      'Metadata uses the domestic proxy first');
  calls.clear();
  final fallback = await GithubUpdates.routedBody(endpoint, (uri) async {
    calls.add(uri);
    if (uri.host == 'edgeone.gh-proxy.org') throw StateError('offline');
    return 'direct-response';
  });
  expect(
      fallback == 'direct-response' &&
          calls.length == 2 &&
          calls.last == endpoint,
      'Direct fallback when the proxy cannot serve metadata');
  final digest = List.filled(64, 'a').join();
  Map manifest() => {
        'packageId': AppRelease.packageId,
        'abi': 'arm64-v8a',
        'version': '0.1.0',
        'buildNumber': 10007,
        'size': 1024,
        'apkName': 'DsmClient-dev-7-arm64.apk',
        'sha256': digest,
      };
  Map release() => {
        'tag_name': 'dev-7',
        'draft': false,
        'prerelease': true,
        'body': 'Changes',
        'assets': [
          {
            'name': 'DsmClient-dev-7-arm64.apk',
            'size': 1024,
            'state': 'uploaded',
            'browser_download_url':
                'https://github.com/318182456/DsmClient/releases/download/dev-7/DsmClient-dev-7-arm64.apk'
          }
        ],
      };
  final update = AppRelease.fromManifest(manifest(), release());
  final published = AppRelease.fromPublishedManifest(
      manifest()..['downloadURL'] = 'https://evil.invalid/app.apk', 'dev-7');
  expect(published.downloadUrl == update.downloadUrl,
      'Feed fallback derives the APK URL from this repository and tag');
  final feed = '''<feed>
    <link href="https://github.com/318182456/DsmClient/releases/tag/dev-7"/>
    <link href="https://github.com/318182456/DsmClient/releases/tag/dev-7"/>
    <link href="https://github.com/another/repo/releases/tag/dev-99"/>
    <content>&lt;link href=&quot;https://github.com/318182456/DsmClient/releases/tag/evil&quot;/&gt;</content>
    <link href="https://github.com/318182456/DsmClient/releases/tag/%2e%2e%2fevil"/>
  </feed>''';
  expect(GithubUpdates.tagsFromFeed(feed).join(',') == 'dev-7',
      'Accept only valid, unique release links in this repository feed');
  expect(update.newerThan('10006'), 'Offer a newer build');
  expect(!update.newerThan('10007'), 'Do not offer the same build repeatedly');
  expect(
      !update.newerThan('10008'), 'Never downgrade, including manual checks');
  expect(update.toLegacyData()['sha256'] == digest,
      'Keep verified checksum metadata');
  expect(
      !AppRelease.trustedAssetUrl(
          'http://github.com/318182456/DsmClient/releases/download/dev-7/app.apk',
          'dev-7'),
      'Require HTTPS');
  expect(
      !AppRelease.trustedAssetUrl(
          'https://github.com.evil.invalid/318182456/DsmClient/releases/download/dev-7/app.apk',
          'dev-7'),
      'Reject lookalike domains');
  expect(
      !AppRelease.trustedAssetUrl(
          'https://github.com/other/repo/releases/download/dev-7/app.apk',
          'dev-7'),
      'Bind updates to this repository');
  expect(
      !AppRelease.trustedAssetUrl(
          'https://github.com/318182456/DsmClient/releases/download/dev-8/app.apk',
          'dev-7'),
      'Bind manifest to release tag');
  void rejected(Map value, Map item, String message) {
    bool caught = false;
    try {
      AppRelease.fromManifest(value, item);
    } on FormatException {
      caught = true;
    }
    expect(caught, message);
  }

  rejected(
      manifest()..['sha256'] = 'invalid', release(), 'Reject invalid digest');
  rejected(
      manifest()..['size'] = 512, release(), 'Reject mismatched asset size');
  rejected(manifest()..['packageId'] = 'different.app', release(),
      'Reject wrong application');
  rejected(manifest()..['abi'] = 'x86', release(), 'Reject wrong ABI');
  rejected(manifest()..['apkName'] = '../app.apk', release(),
      'Reject path traversal');
  rejected(manifest(), release()..['draft'] = true, 'Do not install drafts');
  rejected(
      manifest(), release()..['assets'] = [], 'Require matching uploaded APK');
  print('GitHub update manifest regression tests passed.');
}
