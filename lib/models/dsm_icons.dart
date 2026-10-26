// @dart=2.10
class DsmIcons {
  static List<String> builtinPaths(String id) {
    final file = const {'FileStation': 'FileStation.png', 'SynologyPhotos': 'photos.png',
      'SynologyDrive': 'Drive.png', 'CloudSync': 'CloudSync.png',
      'HyperBackup': 'HyperBackup.png', 'SnapshotReplication': 'SnapshotReplication.png'}[id];
    return file == null ? [] : ['/webman/modules/HelpBrowser/images/2x/$file'];
  }
  static String resolve(String base, String path) {
    final origin = Uri.tryParse(base ?? '');
    if (origin == null || !origin.hasAuthority || path == null || path.isEmpty ||
        path.contains('\\') || path.split('/').contains('..')) return null;
    final root = Uri.parse('${base.replaceFirst(RegExp(r'/+$'), '')}/');
    final target = root.resolve(path);
    if (target.scheme != origin.scheme || target.host != origin.host || target.port != origin.port ||
        target.userInfo.isNotEmpty || target.hasFragment) return null;
    return target.toString();
  }

  static List<String> paths(String id, dynamic config, Iterable<String> appIds) {
    if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(id ?? '') || id.contains('..')) return [];
    final templates = <String>[];
    void icon(dynamic value) {
      if (value is String && value.isNotEmpty) templates.add(value);
      if (value is Map) for (final v in value.values) icon(v);
    }
    void findApp(dynamic value, String name) {
      if (value is Map) {
        if (value[name] is Map) icon(value[name]['icon']);
        for (final v in value.values) if (v is Map || v is List) findApp(v, name);
      } else if (value is List) { for (final v in value) findApp(v, name); }
    }
    for (final name in appIds) findApp(config, name);
    void remaining(dynamic value) {
      if (value is Map) {
        icon(value['icon']);
        for (final v in value.values) if (v is Map || v is List) remaining(v);
      } else if (value is List) { for (final v in value) remaining(v); }
    }
    if (templates.isEmpty) remaining(config);
    final results = <String>{};
    for (final template in templates.toSet()) {
      final values = template.contains('{0}')
          ? [72, 64, 48, 32, 16].map((size) => template.replaceAll('{0}', '$size')) : [template];
      for (final value in values) results.add(value.startsWith('/') || value.startsWith('http')
        ? value : '/webman/3rdparty/$id/$value');
    }
    return results.toList();
  }
}
