import 'drive_admin_api.dart';

class AiConsoleApi {
  final DriveAdminApi api;
  AiConsoleApi(this.api);
  Future<List<Map>> providers() async {
    final data = await api.call('SYNO.AI.Proxy.Provider', 'list') as Map ?? {};
    const publicFields = {
      'id',
      'name',
      'type',
      'base_url',
      'chat_completion_model',
      'context_window',
      'context_window_output_tokens',
      'created_time',
      'verified_time'
    };
    return (data['providers'] as List ?? [])
        .whereType<Map>()
        .map((row) => <String, dynamic>{
              for (final k in publicFields)
                if (row.containsKey(k)) k: row[k]
            })
        .toList();
  }

  Future<List<Map>> policies() async {
    final data =
        await api.call('SYNO.AI.Policy.Application', 'list') as Map ?? {};
    return (data['applications'] as List ?? [])
        .whereType<Map>()
        .map((v) => Map.from(v))
        .toList();
  }

  Future<void> rename(int id, String name) async {
    if (id < 0 || name.trim().isEmpty || name.length > 128)
      throw FormatException('请输入 1 至 128 字的集成名称');
    await api.call('SYNO.AI.Proxy.Provider', 'rename',
        params: {'id': id, 'name': name.trim()});
  }

  Future<void> remove(int id) async {
    if (id < 0) throw ArgumentError('Invalid provider');
    await api.call('SYNO.AI.Proxy.Provider', 'delete', params: {
      'ids': [id]
    });
  }

  Future<void> policy(String namespace, int enabled, int provider) async {
    if (!const {0, 1, 2}.contains(enabled)) throw FormatException('应用策略无效');
    final latest = await policies(),
        found = latest.where((p) => p['ns'] == namespace);
    if (found.isEmpty) throw StateError('应用策略已变更，请刷新');
    final update = Map<String, dynamic>.from(found.first)
      ..['enable_policy'] = enabled;
    if (enabled != 0) {
      final available = await providers();
      if (!available.any((p) => p['id'] == provider))
        throw FormatException('请选择当前可用的 API 集成');
      update['provider_id'] = provider;
    }
    if (enabled == 1) {
      update.remove('except_user_ids');
      update.remove('except_group_ids');
    }
    await api.call('SYNO.AI.Policy.Application', 'update', params: {
      'applications': [update]
    });
  }

  Future<Map> logSettings() async => Map.from(
      await api.call('SYNO.AI.Statistics.Request.Log.Setting', 'get') as Map ??
          {});
  Future<void> saveLogSettings(Map<String, dynamic> settings) async {
    final days = settings['retention_days'], size = settings['max_size'];
    if (days != null && (days is! int || days < 1 || days > 9999) ||
        size != null && (size is! int || size < 1000 || size > 10000000) ||
        settings['save_content_output'] is! bool)
      throw FormatException('日志保留天数或数量超出允许范围');
    await api.call('SYNO.AI.Statistics.Request.Log.Setting', 'set', params: {
      'setting': {
        if (days != null) 'retention_days': days,
        if (size != null) 'max_size': size,
        'save_content_output': settings['save_content_output'],
      }
    });
  }

  Future<List<Map>> logs({int offset = 0, String query = ''}) async {
    final data =
        await api.call('SYNO.AI.Statistics.Request.Log', 'list', params: {
              'offset': offset,
              'limit': 100,
              'filter_options': {'search_text': query}
            }) as Map ??
            {};
    return (data['logs'] as List ?? []).whereType<Map>().toList();
  }
}
