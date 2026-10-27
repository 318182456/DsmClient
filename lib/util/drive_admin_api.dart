import 'package:dsm_client/models/program_section.dart';
import 'program_api.dart';

typedef DriveAdminRequest = Future<Map> Function(
    String api, String method, int version, Map<String, dynamic> params);

/// Contracts checked against Drive 4.0.3 and Office 3.7.2 admin interfaces.
class DriveAdminApi {
  final DriveAdminRequest request;
  DriveAdminApi({DriveAdminRequest request}) : request = request ?? _request;
  static Future<Map> _request(String api, String method, int version,
          Map<String, dynamic> params) =>
      ProgramApi.call(ProgramSection('', api, method, version: version),
          params: params);
  Future<dynamic> call(String api, String method,
      {int version = 1, Map<String, dynamic> params = const {}}) async {
    final response = await request(api, method, version, params);
    if (response['success'] != true)
      throw StateError(ProgramApi.error(response));
    return response['data'];
  }

  Future<Map> status() async =>
      Map.from(await call('SYNO.SynologyDrive', 'get_status') as Map ?? {});
  Future<Map> summary() async => Map.from(
      (await call('SYNO.SynologyDrive.Connection', 'summary', version: 2)
                  as Map ??
              {})['summary'] as Map ??
          {});
  Future<Map> list(String api,
          {int offset = 0, String keyword = '', int logType = -1}) async =>
      Map.from(await call(api, 'list', params: {
            'offset': offset,
            'limit': 100,
            if (api == 'SYNO.SynologyDrive.Connection') ...{
              'sort_by': 'last_auth_time',
              'sort_direction': 'DESC'
            },
            if (api == 'SYNO.SynologyDrive.Share') ...{
              'sort_by': 'share_name',
              'sort_direction': 'ASC'
            },
            if (api == 'SYNO.SynologyDrive.Log') ...{
              'target': 'all',
              'share_type': 'all',
              'get_all': true,
              'keyword': keyword,
              'log_type': logType < 0 ? [] : [logType]
            },
          }) as Map ??
          {});
  Future<Map> settings() async => Map.from(
      await call('SYNO.SynologyDrive.Settings', 'list', version: 2) as Map ??
          {});
  Future<Map> config() async =>
      Map.from(await call('SYNO.SynologyDrive.Config', 'get') as Map ?? {});
  Future<Map> activation() async =>
      Map.from(await call('SYNO.SynologyDrive.Activation', 'get') as Map ?? {});
  Future<void> activate(String code) async {
    if (code.trim().isEmpty) throw FormatException('请输入合法的高级功能激活码');
    await call('SYNO.SynologyDrive.Activation', 'set',
        params: {'activation_code': code.trim(), 'activated': true});
  }

  Future<void> disconnect(String sessionId) async {
    if (sessionId.isEmpty) throw FormatException('该客户端未提供可断开的会话');
    await call('SYNO.SynologyDrive.Connection', 'delete',
        params: {'client_sess_id': sessionId, 'data_wipe': false});
  }

  static const shareFields = {
    'share_name',
    'share_enable',
    'share_status',
    'share_type',
    'rotate_cnt',
    'rotate_policy',
    'rotate_days',
    'disable_download',
    'enable_watermark',
    'watermark_font',
    'watermark_font_color',
    'watermark_font_px_size',
    'watermark_text',
    'watermark_opacity_percent',
    'watermark_rotate_degree',
    'watermark_is_repeat',
    'watermark_density',
    'watermark_version',
    'force_watermark_download',
    'enable_node_locking'
  };
  Future<Map> share(String name) async {
    for (var offset = 0; offset < 10000; offset += 100) {
      final data = await list('SYNO.SynologyDrive.Share', offset: offset);
      final rows = (data['items'] as List ?? []).whereType<Map>().toList();
      final found = rows.where((r) => r['share_name'] == name);
      if (found.isNotEmpty) return Map.from(found.first);
      if (rows.length < 100 ||
          (data['total'] is num && offset + rows.length >= data['total']))
        break;
    }
    throw StateError('团队文件夹已变更，请刷新列表后重试');
  }

  Future<void> saveShare(String name, Map<String, dynamic> changes) async {
    if (changes.keys.any((k) =>
        !shareFields.contains(k) ||
        const {'share_name', 'share_status', 'share_type'}.contains(k)))
      throw ArgumentError('Invalid share update');
    final current = await share(name);
    if (const {'home', 'homes'}.contains(name) &&
        changes['share_enable'] == false)
      throw FormatException('个人空间由 DSM 家目录服务管理，不能在此停用');
    final updated = <String, dynamic>{
      for (final k in shareFields)
        if (current.containsKey(k)) k: current[k],
      ...changes
    };
    final count = updated['rotate_cnt'];
    if (count is! num ||
        count < 0 ||
        count > 32 ||
        count != count.roundToDouble())
      throw FormatException('版本数量需为 0 至 32 的整数');
    if (count > 0 &&
        !const {'fifo', 'smart'}.contains(updated['rotate_policy']))
      throw FormatException('请选择有效的版本保留策略');
    if (updated['rotate_days'] is! num || updated['rotate_days'] < 0)
      throw FormatException('版本保留天数无效');
    await call('SYNO.SynologyDrive.Share', 'set', params: {
      'share': [updated]
    });
  }

  static const settingBools = {
    'default_enable_full_content_indexing',
    'enable_c2share_offload',
    'file_request_enabled',
    'file_request_force_password',
    'force_https_sharing_link',
    'sharing_force_password',
    'file_request_link_by_email',
    'sharing_link_by_email',
    'enable_sharing_link_customization'
  };
  static const configBools = {
    'enable_non_admin_user_sync',
    'enable_vmtouch',
    'use_del_by_cnt',
    'use_del_by_span'
  };
  static const logCounts = {1000000, 3000000, 5000000, 10000000, 50000000};
  static const logSpans = {2592000, 7776000, 15552000, 31104000};
  static const configFields = {
    'enable_non_admin_user_sync',
    'enable_vmtouch',
    'use_del_by_cnt',
    'use_del_by_span',
    'del_cnt',
    'del_span',
    'db_volume'
  };
  Future<void> saveSettings(Map<String, dynamic> changes,
      {bool serverConfig = false}) async {
    final allowed = serverConfig ? configBools : settingBools;
    if (serverConfig) {
      for (final e in changes.entries) {
        if (e.key == 'db_volume') {
          final current = await config(),
              volumes = (current['volume_list'] as List ?? []).whereType<Map>();
          if (e.value is! String ||
              !volumes.any((v) => v['mount_point'] == e.value))
            throw FormatException('请选择 NAS 当前可用的数据库存储空间');
        } else if (e.key == 'del_cnt') {
          if (!logCounts.contains(e.value)) throw FormatException('日志数量上限无效');
        } else if (e.key == 'del_span') {
          if (!logSpans.contains(e.value)) throw FormatException('日志保留时间无效');
        } else if (!configBools.contains(e.key) || e.value is! bool)
          throw ArgumentError('Invalid Drive setting');
      }
    }
    if (changes.isEmpty ||
        !serverConfig &&
            changes.entries.any((e) => e.key == 'sharing_level' && !serverConfig
                ? !const {'disallow', 'internal', 'public'}.contains(e.value)
                : !allowed.contains(e.key) || e.value is! bool))
      throw ArgumentError('Invalid Drive setting');
    await call(
        serverConfig
            ? 'SYNO.SynologyDrive.Config'
            : 'SYNO.SynologyDrive.Settings',
        serverConfig ? 'set' : 'update',
        version: serverConfig ? 1 : 2,
        params: changes);
  }

  Future<Map> fonts() async =>
      Map.from(await call('SYNO.Office.Setting.Font', 'list') as Map ?? {});
  Future<void> fontAction(String action, List<String> names) async {
    if (!const {'add', 'enable', 'disable', 'delete'}.contains(action) ||
        names.isEmpty) throw ArgumentError('Invalid font action');
    if (names.any((n) =>
        n.trim().isEmpty ||
        n.length > 256 ||
        RegExp(r'[\x00-\x1f]').hasMatch(n))) throw FormatException('字体名称无效');
    final latest = await fonts();
    for (final name in names) {
      if (action == 'add') {
        if (latest.containsKey(name)) throw FormatException('字体已存在：$name');
        continue;
      }
      if (latest[name] is! Map) throw FormatException('字体列表已变更，请刷新');
      if (action == 'disable' && name.toLowerCase() == 'arial')
        throw FormatException('Arial 为必需字体，不能停用');
      if (action == 'delete' && latest[name]['system'] != false)
        throw FormatException('系统字体不能删除');
    }
    await call('SYNO.Office.Setting.Font', action,
        params: {'fonts': names.toSet().toList()});
  }

  Future<Map> officeSettings() async =>
      Map.from(await call('SYNO.Office.Setting.System', 'get') as Map ?? {});
  Future<void> setOfficeHistory(bool enabled) async {
    await call('SYNO.Office.Setting.System', 'set',
        params: {'history_prune': enabled});
  }
}
