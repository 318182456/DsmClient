// @dart=2.10
class TorrentPresentation {
  static num number(dynamic value) =>
      value is num ? value : num.tryParse('$value') ?? 0;
  static String group(Map task, {bool transmission = false}) {
    final raw = task['raw'] as Map ?? {};
    if ('${raw['errorString'] ?? ''}'.isNotEmpty || number(raw['error']) > 0)
      return 'error';
    final state = '${task['state'] ?? ''}'.toLowerCase();
    if (transmission)
      return const {
            '0': 'paused',
            '1': 'checking',
            '2': 'checking',
            '3': 'queued',
            '4': 'downloading',
            '5': 'queued',
            '6': 'seeding'
          }[state] ??
          'other';
    if (state == 'error' || state == 'missingfiles') return 'error';
    if (state.startsWith('paused') || state.startsWith('stopped'))
      return 'paused';
    if (state.startsWith('checking')) return 'checking';
    if (state.startsWith('queued')) return 'queued';
    if (['uploading', 'stalledup', 'forcedup'].contains(state))
      return 'seeding';
    if ([
      'downloading',
      'stalleddl',
      'forceddl',
      'metadl',
      'forcedmetadl',
      'allocating',
      'moving'
    ].contains(state)) return 'downloading';
    return 'other';
  }

  static const labels = {
    'all': '全部',
    'downloading': '下载中',
    'seeding': '做种',
    'paused': '暂停',
    'checking': '校验',
    'queued': '排队',
    'error': '错误',
    'other': '其他'
  };
  static List<String> tags(Map task) {
    final raw = task['raw'] as Map ?? {};
    final values = raw['labels'] ?? raw['tags'] ?? [];
    return (values is List ? values.map((v) => '$v') : '$values'.split(','))
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList();
  }

  static List<String> trackers(Map task) {
    final raw = task['raw'] as Map ?? {};
    final values = <dynamic>[
      ...(task['trackers'] as List ?? []),
      ...(raw['trackers'] as List ?? []),
      if (raw['tracker'] != null) raw['tracker']
    ];
    return values
        .map((v) =>
            Uri.tryParse('${v is Map ? v['announce'] ?? v['url'] ?? '' : v}')
                ?.host
                ?.toLowerCase() ??
            '')
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList();
  }

  static String category(Map t) =>
      '${(t['raw'] as Map ?? {})['category'] ?? ''}';
  static String directory(Map t) {
    final r = t['raw'] as Map ?? {};
    return '${r['downloadDir'] ?? r['save_path'] ?? ''}';
  }

  static const sorts = {
    'added': '添加时间',
    'size': '大小',
    'name': '名称',
    'progress': '进度',
    'speed': '下载速度',
    'upload': '上传速度',
    'ratio': '分享率',
    'eta': '剩余时间'
  };
  static List<Map> select(List<Map> tasks,
      {String filter = 'all',
      String query = '',
      String sort = 'added',
      bool descending,
      String categoryFilter,
      String tagFilter,
      String trackerFilter,
      String directoryFilter,
      bool transmission = false}) {
    final rows = tasks
        .where((t) =>
            (filter == 'all' ||
                group(t, transmission: transmission) == filter) &&
            '${t['name']}'.toLowerCase().contains(query.toLowerCase()) &&
            (categoryFilter == null || category(t) == categoryFilter) &&
            (directoryFilter == null || directory(t) == directoryFilter) &&
            (tagFilter == null ||
                (tagFilter.isEmpty
                    ? tags(t).isEmpty
                    : tags(t).contains(tagFilter))) &&
            (trackerFilter == null ||
                (trackerFilter.isEmpty
                    ? trackers(t).isEmpty
                    : trackers(t).contains(trackerFilter))))
        .toList();
    rows.sort((a, b) {
      int result;
      if (sort == 'name') {
        result = '${a['name']}'
            .toLowerCase()
            .compareTo('${b['name']}'.toLowerCase());
      } else {
        final ar = a['raw'] as Map ?? {}, br = b['raw'] as Map ?? {};
        num key(Map task, Map raw) {
          if (sort == 'added')
            return number(raw[transmission ? 'addedDate' : 'added_on']);
          if (sort == 'ratio')
            return number(raw[transmission ? 'uploadRatio' : 'ratio']);
          if (sort == 'eta') {
            final v = number(raw['eta']);
            return v < 0 || v >= 8640000 ? double.infinity : v;
          }
          return number(task[const {
            'size': 'size',
            'progress': 'progress',
            'speed': 'downloadSpeed',
            'upload': 'uploadSpeed'
          }[sort]]);
        }

        result = key(a, ar).compareTo(key(b, br));
      }
      if (descending ?? sort != 'name') result = -result;
      return result == 0 ? '${a['id']}'.compareTo('${b['id']}') : result;
    });
    return rows;
  }
}
