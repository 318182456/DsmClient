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
  static List<Map> select(List<Map> tasks,
      {String filter = 'all',
      String query = '',
      String sort = 'added',
      bool transmission = false}) {
    final rows = tasks
        .where((t) =>
            (filter == 'all' ||
                group(t, transmission: transmission) == filter) &&
            '${t['name']}'.toLowerCase().contains(query.toLowerCase()))
        .toList();
    rows.sort((a, b) {
      if (sort == 'name')
        return '${a['name']}'
            .toLowerCase()
            .compareTo('${b['name']}'.toLowerCase());
      if (sort == 'progress')
        return number(b['progress']).compareTo(number(a['progress']));
      if (sort == 'speed')
        return number(b['downloadSpeed']).compareTo(number(a['downloadSpeed']));
      final ar = a['raw'] as Map ?? {}, br = b['raw'] as Map ?? {};
      return number(br[transmission ? 'addedDate' : 'added_on'])
          .compareTo(number(ar[transmission ? 'addedDate' : 'added_on']));
    });
    return rows;
  }
}
