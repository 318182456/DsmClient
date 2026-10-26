// @dart=2.10

/// Metadata from a published manifest, optionally cross-checked with GitHub's API.
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

  /// The caller fetches this manifest from this repository's published release.
  /// Derive URLs locally, never accept a download host supplied by the manifest.
  static AppRelease fromPublishedManifest(Map manifest, String tag,
      {String notes = ''}) {
    if (tag.isEmpty ||
        !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(tag) ||
        tag.contains('..')) {
      throw FormatException('Invalid release tag');
    }
    final build = int.tryParse('${manifest['buildNumber']}') ?? 0;
    final size = int.tryParse('${manifest['size']}') ?? 0;
    final name = '${manifest['apkName'] ?? ''}';
    final digest = '${manifest['sha256'] ?? ''}'.toLowerCase();
    final version = '${manifest['version'] ?? ''}';
    if (manifest['packageId'] != packageId ||
        manifest['abi'] != 'arm64-v8a' ||
        build <= 0 ||
        size <= 0 ||
        version.isEmpty ||
        !RegExp(r'^[A-Za-z0-9_.-]+\.apk$').hasMatch(name) ||
        name.contains('..') ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw FormatException('Invalid update manifest');
    }
    return AppRelease._(
        build,
        version,
        name,
        'https://github.com/$repository/releases/download/${Uri.encodeComponent(tag)}/${Uri.encodeComponent(name)}',
        digest,
        size,
        notes,
        'https://github.com/$repository/releases/tag/${Uri.encodeComponent(tag)}');
  }

  static AppRelease fromManifest(Map manifest, Map release) {
    if (release['draft'] == true) throw FormatException('Draft release');
    final tag = '${release['tag_name'] ?? ''}';
    final parsed =
        fromPublishedManifest(manifest, tag, notes: '${release['body'] ?? ''}');
    final assets = (release['assets'] as List ?? []).whereType<Map>();
    final asset = assets.firstWhere((item) => item['name'] == parsed.apkName,
        orElse: () => null);
    if (asset == null ||
        asset['state'] != 'uploaded' ||
        int.tryParse('${asset['size']}') != parsed.size ||
        asset['browser_download_url'] != parsed.downloadUrl) {
      throw FormatException('APK asset does not match manifest');
    }
    return parsed;
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
