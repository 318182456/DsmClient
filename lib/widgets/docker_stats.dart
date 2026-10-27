import 'package:flutter/material.dart';
import 'package:dsm_client/util/function.dart';

class DockerStatsPanel extends StatelessWidget {
  final Map stats;
  final bool compact;
  const DockerStatsPanel(this.stats, {this.compact = false});
  static num value(dynamic raw) {
    final n = raw is num ? raw : num.tryParse('$raw');
    return n != null && n.isFinite && n >= 0 ? n : null;
  }

  static String percent(dynamic raw) {
    final n = value(raw);
    return n == null ? '—' : '${n.toStringAsFixed(1)}%';
  }

  static String bytes(dynamic raw) {
    final n = value(raw);
    return n == null ? '—' : Util.formatSize(n);
  }

  static Map totals(Iterable<Map> rows) {
    final items = rows.toList();
    final result = <String, num>{};
    for (final key in [
      'cpuPercent',
      'memoryUsage',
      'networkRx',
      'networkTx',
      'blockRead',
      'blockWrite'
    ]) {
      final values =
          items.map((r) => value(r[key])).where((v) => v != null).toList();
      if (values.isNotEmpty) result[key] = values.fold<num>(0, (a, b) => a + b);
    }
    // A per-container memoryLimit can be the host's total; never sum it.
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final metrics = <String, String>{
      'CPU': percent(stats['cpuPercent']),
      '内存':
          '${bytes(stats['memoryUsage'])}${stats['memoryLimit'] == null ? '' : ' / ${bytes(stats['memoryLimit'])}'}',
      if (!compact)
        '网络接收 / 发送':
            '${bytes(stats['networkRx'])} / ${bytes(stats['networkTx'])}',
      if (!compact)
        '磁盘读取 / 写入':
            '${bytes(stats['blockRead'])} / ${bytes(stats['blockWrite'])}',
    };
    return LayoutBuilder(
        builder: (context, constraints) => Wrap(
            spacing: 12,
            runSpacing: compact ? 8 : 16,
            children: metrics.entries
                .map((e) => SizedBox(
                    width: (constraints.maxWidth - 12) / 2,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.key,
                              style: Theme.of(context).textTheme.caption),
                          SizedBox(height: 4),
                          Text(e.value,
                              style: compact
                                  ? Theme.of(context).textTheme.bodyText2
                                  : Theme.of(context).textTheme.subtitle1),
                        ])))
                .toList()));
  }
}
