// @dart=2.10
import '../lib/models/app_release.dart';

void expect(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
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
