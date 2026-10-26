// @dart=2.10

/// Update metadata is bound to an APK asset in this repository's release.
class AppRelease {
  static const repository = '318182456/DsmClient';
  static const packageId = 'fit.flutter.dsm_helper';

  final int buildNumber;
  final String version;
  final String apkName;
  final String downloadUrl;
  final String sha256;
  final int size;
  final String notes;
  final String releaseUrl;

  AppRelease._(this.buildNumber, this.version, this.apkName, this.downloadUrl,
      this.sha256, this.size, this.notes, this.releaseUrl);

  static bool trustedAssetUrl(String value, String tag) {
    final uri = Uri.tryParse(value ?? '');
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'github.com' &&
        uri.port == 443 &&
        uri.userInfo.isEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty &&
        uri.path.startsWith(
            '/$repository/releases/download/${Uri.encodeComponent(tag)}/');
  }

  static AppRelease fromManifest(Map manifest, Map release) {
    if (release['draft'] == true) throw FormatException('Draft release');
    final tag = '${release['tag_name'] ?? ''}';
    if (tag.isEmpty || tag.contains('/') || tag.contains('..')) {
      throw FormatException('Invalid release tag');
    }
    final build = int.tryParse('${manifest['buildNumber']}') ?? 0;
    final size = int.tryParse('${manifest['size']}') ?? 0;
    final name = '${manifest['apkName'] ?? ''}';
    final digest = '${manifest['sha256'] ?? ''}'.toLowerCase();
    if (manifest['packageId'] != packageId ||
        manifest['abi'] != 'arm64-v8a' ||
        build <= 0 ||
        size <= 0 ||
        !RegExp(r'^[A-Za-z0-9_.-]+\.apk$').hasMatch(name) ||
        name.contains('..') ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw FormatException('Invalid update manifest');
    }
    final assets = (release['assets'] as List ?? []).whereType<Map>();
    final asset =
        assets.firstWhere((item) => item['name'] == name, orElse: () => null);
    if (asset == null ||
        asset['state'] != 'uploaded' ||
        int.tryParse('${asset['size']}') != size ||
        !trustedAssetUrl(asset['browser_download_url'], tag)) {
      throw FormatException('APK asset does not match manifest');
    }
    return AppRelease._(
        build,
        '${manifest['version'] ?? ''}',
        name,
        asset['browser_download_url'],
        digest,
        size,
        '${release['body'] ?? ''}',
        'https://github.com/$repository/releases/tag/${Uri.encodeComponent(tag)}');
  }

  bool newerThan(String installedBuild) =>
      buildNumber > (int.tryParse(installedBuild ?? '') ?? 0);

  Map<String, dynamic> toLegacyData() => {
        'buildVersionNo': '$buildNumber',
        'buildVersion': version,
        'buildUpdateDescription': notes,
        'downloadURL': downloadUrl,
        'apkName': apkName,
        'sha256': sha256,
        'size': size,
        'releaseURL': releaseUrl,
      };
}
