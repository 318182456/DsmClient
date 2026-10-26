// @dart=2.10
/// Installed package metadata, including DSM's space-separated class registry.
class NasPackage {
  final String id;
  final String name;
  final String version;
  final String status;
  final String description;
  final List<String> appIds;

  NasPackage.fromJson(Map source)
      : id = '${source['id'] ?? ''}',
        name = '${source['name'] ?? source['id'] ?? ''}',
        version = '${source['version'] ?? ''}',
        status = '${(source['additional'] ?? {})['status'] ?? 'unknown'}',
        description = '${(source['additional'] ?? {})['description'] ?? ''}',
        appIds = parseAppIds((source['additional'] ?? {})['dsm_apps']);

  static List<String> parseAppIds(dynamic source) {
    final values = source is List ? source : '$source'.split(RegExp(r'\s+'));
    return values
        .whereType<String>()
        .where((value) =>
            value.contains('.') && RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(value))
        .toSet()
        .toList();
  }

  /// A registry also contains internal components; only desktop apps can launch.
  List<String> launchApps(Iterable desktopApps) =>
      desktopApps.whereType<String>().where(appIds.contains).toSet().toList();
}
