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

  static bool sensitive(String key) => RegExp(
          r'password|passwd|secret|token|cookie|(^|_)sid$|session|private_key|auth_key|api[_-]?key|access[_-]?key|credential',
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
