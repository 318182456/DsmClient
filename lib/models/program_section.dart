// @dart=2.10
/// An explicit, versioned business endpoint. Never accepts arbitrary API names
/// or methods from NAS metadata or from a saved website address.
class ProgramSection {
  final String title, api, method, listKey;
  final int version;
  final Map<String, dynamic> params;
  const ProgramSection(this.title, this.api, this.method,
      {this.version = 1, this.listKey, this.params = const {}});

  Map<String, dynamic> request({int offset = 0, int limit = 100}) => {
        ...params,
        'api': api,
        'method': method,
        'version': version,
        if (listKey != null && params.containsKey('offset')) 'offset': offset,
        if (listKey != null && params.containsKey('limit')) 'limit': limit,
      };

  List<Map> rows(dynamic data) {
    if (data == null) return [];
    dynamic value = data;
    if (listKey != null) {
      for (final key in listKey.split('.')) {
        value = value is Map ? value[key] : null;
      }
    }
    if (value is List) return value.whereType<Map>().toList();
    return [];
  }

  /// Some package APIs return an empty name rather than omitting the field.
  /// Pick an actual nonblank label without changing the NAS record itself.
  String rowTitle(Map record) {
    final repository = api == 'SYNO.Backup.Repository';
    final keys = repository
        ? ['title', 'name', 'repo_name', 'target_id', 'share', 'path']
        : ['title', 'name', 'task_display_name', 'task_name', 'client_name',
            'file_name', 'local_sync_path', 'event', 's1', 'share', 'path', 'time', 'id'];
    for (final key in keys) {
      final value = record[key];
      if ((value is String || value is num) && '$value'.trim().isNotEmpty)
        return '$value';
    }
    final id = record['repo_id'];
    return repository
        ? (id != null && '$id'.trim().isNotEmpty ? '存储库 #$id' : '未命名存储库')
        : '详细信息';
  }

  static bool sensitive(String key) => RegExp(
          r'password|passwd|(^|_)(pwd|pass)(_|$)|secret|token|cookie|(^|_)sid$|session|private_key|auth_key|api[_-]?key|access[_-]?key|credential',
          caseSensitive: false)
      .hasMatch(key);

  static dynamic publicValue(dynamic value) {
    if (value is Map)
      return {
        for (final key in value.keys)
          if (!sensitive('$key')) '$key': publicValue(value[key])
      };
    if (value is List) return value.map(publicValue).toList();
    return value;
  }
}
