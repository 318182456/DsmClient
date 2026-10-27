import 'dart:convert';
import 'package:dsm_client/models/program_section.dart';
import 'package:dsm_client/util/function.dart';

class ProgramApi {
  static String url(ProgramSection section, Map<String, dynamic> params) {
    final data = Util.dsmParameters('entry.cgi', {
      ...section.request(),
      ...params,
      '_sid': Util.sid,
    });
    final path = Util.dsmPath('entry.cgi', data);
    return Uri.parse(
            '${Util.baseUrl.replaceFirst(RegExp(r'/+$'), '')}/webapi/$path')
        .replace(queryParameters: {
      for (final e in data.entries)
        e.key: e.value is Map || e.value is List
            ? jsonEncode(e.value)
            : '${e.value}'
    }).toString();
  }

  static Future<Map> call(ProgramSection section,
      {Map<String, dynamic> params = const {},
      int offset = 0,
      int timeout = 20}) async {
    if (Api.apiList.isNotEmpty && !Api.apiList.containsKey(section.api)) {
      return {
        'success': false,
        'error': {'code': 102}
      };
    }
    final data = {
      ...section.request(offset: offset),
      ...params,
      '_sid': Util.sid
    };
    final encoded = <String, dynamic>{};
    data.forEach((key, value) {
      encoded[key] = value is Map || value is List || value is bool
          ? jsonEncode(value)
          : value;
    });
    return await Util.post('entry.cgi', data: encoded, timeout: timeout);
  }

  static String error(Map result) {
    final code = (result['error'] ?? {})['code'];
    if (code == 105 || code == 119) return '当前账号无权访问，或会话已失效，请重新登录';
    if (code == 102 || code == 103 || code == 104) return '当前套件版本未提供此功能（$code）';
    return '请求失败（${code ?? '连接异常'}），请重试';
  }

  static const drive = [
    ProgramSection('团队文件夹', 'SYNO.SynologyDrive.TeamFolders', 'list',
        listKey: 'items', params: {'filter': {}, 'offset': 0, 'limit': 100}),
    ProgramSection('连接设备', 'SYNO.SynologyDrive.Connection', 'list',
        listKey: 'items', params: {'offset': 0, 'limit': 100}),
    ProgramSection('同步日志', 'SYNO.SynologyDrive.Log', 'list',
        listKey: 'items',
        params: {
          'target': 'all',
          'share_type': 'all',
          'get_all': true,
          'sort_direction': 'desc',
          'offset': 0,
          'limit': 100
        }),
    ProgramSection('服务信息', 'SYNO.SynologyDrive.Info', 'get', version: 2),
  ];
  static const backup = [
    // Hyper Backup 7.x advertises v2, but list is only implemented in v1.
    ProgramSection('备份任务', 'SYNO.Backup.Task', 'list',
        listKey: 'task_list',
        params: {
          'additional': [
            'last_bkp_time',
            'last_bkp_result',
            'get_source',
            'progress_title_type'
          ]
        }),
    ProgramSection('备份存储库', 'SYNO.Backup.Repository', 'list',
        listKey: 'repo_list'),
    ProgramSection('备份日志', 'SYNO.SDS.Backup.Client.Common.Log', 'list',
        listKey: 'log_list',
        params: {
          'offset': 0,
          'limit': 100,
          'filter_keyword': '',
          'filter_date_from': 0,
          'filter_date_to': 0
        }),
  ];
  static const cloud = [
    ProgramSection('云端连接', 'SYNO.CloudSync', 'list_conn',
        listKey: 'conn',
        params: {'is_tray': false, 'group_by': 'group_by_user'}),
    ProgramSection('同步中文件', 'SYNO.CloudSync', 'get_recently_change',
        listKey: 'processing_items'),
    ProgramSection('最近同步', 'SYNO.CloudSync', 'get_recently_change',
        listKey: 'history_items'),
    ProgramSection('同步设置', 'SYNO.CloudSync', 'get_config'),
  ];
  static const san = [
    ProgramSection('LUN', 'SYNO.Core.ISCSI.LUN', 'list', listKey: 'luns'),
    ProgramSection('Target', 'SYNO.Core.ISCSI.Target', 'list',
        listKey: 'targets'),
  ];
  static List<ProgramSection> sections(String id) {
    switch (id) {
      case 'SynologyDrive':
        return drive;
      case 'HyperBackup':
        return backup;
      case 'CloudSync':
        return cloud;
      case 'ScsiTarget':
        return san;
      case 'WebDAVServer':
        return [ProgramSection('服务设置', 'SYNO.WebDAV.Common', 'get')];
      case 'HybridShare':
        return [ProgramSection('共享文件夹', 'SYNO.C2FS.Share', 'list')];
      default:
        return [];
    }
  }
}
