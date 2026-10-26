// @dart=2.10
import 'dart:convert';

class RrProtocol {
  static const reads = {'overview', 'read', 'addons', 'modules', 'rr-release', 'rrm-release', 'log'};
  static const writes = {'write', 'save-addons', 'save-modules', 'start-rr-update-online',
    'start-rrm-update-online', 'start-rr-update-local', 'start-rrm-update-local'};
  static Map decode(dynamic value) {
    final parsed = value is String ? jsonDecode(value) : value;
    if (parsed is! Map || parsed['ok'] is! bool) throw FormatException('RR Manager 接口不可用，请确认已安装 4.x 并允许当前账号访问');
    return Map.from(parsed);
  }
  static void validate(String action, Map params, bool write) {
    if (!(write ? writes : reads).contains(action)) throw ArgumentError('RR 操作与请求方式不匹配');
    if ((action == 'read' || action == 'write') && params['file'] != 'user-config')
      throw ArgumentError('只支持 user-config.yml');
    if (action == 'write' && '${params['content'] ?? ''}'.trim().isEmpty)
      throw ArgumentError('不能保存空的引导配置');
    if (action.endsWith('-local') && !'${params['path'] ?? ''}'.startsWith('/'))
      throw ArgumentError('请输入 NAS 上更新包的绝对路径');
  }
  static bool systemItem(Map item) => item['system'] == true || item['system'] == 'true';
  static String selection(List<Map> items, Set<String> selected) => items
    .where((i) => systemItem(i) || selected.contains('${i['name']}'))
    .map((i) => '${i['name']}').toSet().join(',');
}
