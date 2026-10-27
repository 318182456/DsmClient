// @dart=2.10
class QbRssRule {
  static Map params(Map rule) => Map.from(rule['torrentParams'] as Map ?? {});
  static String category(Map rule) =>
      '${params(rule)['category'] ?? rule['assignedCategory'] ?? ''}';
  static String path(Map rule) =>
      '${params(rule)['save_path'] ?? rule['savePath'] ?? ''}';
  static List<String> tags(Map rule) =>
      ((params(rule)['tags'] as List) ?? []).map((v) => '$v').toList();
  static bool stopped(Map rule) {
    final value = params(rule).containsKey('stopped')
        ? params(rule)['stopped']
        : rule['addPaused'];
    return value is bool
        ? value
        : value == 1
            ? true
            : value == 2
                ? false
                : null;
  }

  static List<String> feeds(Map rule) {
    final value = rule['affectedFeeds'];
    return value is String
        ? [value]
        : (value as List ?? []).map((v) => '$v').toList();
  }

  static Map build(Map original,
      {bool enabled = true,
      bool regex = false,
      String include = '',
      String exclude = '',
      String episode = '',
      int ignoreDays = 0,
      List<String> feeds = const [],
      String category = '',
      List<String> tags = const [],
      String savePath = '',
      bool automaticPath = false,
      bool stopped}) {
    if (feeds.isEmpty) throw FormatException('至少选择一个订阅');
    if (ignoreDays < 0 || ignoreDays > 36500)
      throw FormatException('忽略天数需在 0 至 36500 之间');
    if (savePath.contains('\u0000') ||
        savePath.contains('\n') ||
        savePath.contains('\r')) throw FormatException('保存目录包含无效字符');
    final download = params(original)
      ..addAll({
        'category': category.trim(),
        'tags': tags
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList(),
        'save_path': automaticPath ? '' : savePath.trim(),
        'use_auto_tmm': automaticPath
      });
    if (stopped == null)
      download.remove('stopped');
    else
      download['stopped'] = stopped;
    return {
      ...original,
      'enabled': enabled,
      'useRegex': regex,
      'mustContain': include,
      'mustNotContain': exclude,
      'episodeFilter': episode,
      'ignoreDays': ignoreDays,
      'affectedFeeds': feeds.toSet().toList(),
      'assignedCategory': category.trim(),
      'savePath': automaticPath ? '' : savePath.trim(),
      'addPaused': stopped,
      'torrentParams': download
    };
  }
}
