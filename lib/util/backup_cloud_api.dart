// @dart=2.10
import '../models/program_section.dart';
import 'program_api.dart';

typedef BackupCloudRequest = Future<Map> Function(
    ProgramSection section, Map<String, dynamic> params);

class BackupCloudApi {
  final BackupCloudRequest request;
  BackupCloudApi({BackupCloudRequest request})
      : request = request ?? ((s, p) => ProgramApi.call(s, params: p));

  Future<Map> call(String api, String method,
      [Map<String, dynamic> params = const {}]) async {
    final r = await request(ProgramSection('', api, method), params);
    if (r['success'] != true) throw StateError(ProgramApi.error(r));
    if (r['data'] is Map && r['data']['has_fail'] == true)
      throw StateError('服务未完成操作，请刷新任务和存储库确认状态');
    if (r['data'] is! Map) return {};
    return Map<String, dynamic>.from(r['data']);
  }

  Future<List<Map>> backupShares() async {
    final r = await call('SYNO.Backup.Storage.Share.Local', 'list');
    return (r['share_list'] as List ?? [])
        .map<Map>((v) => v is Map
            ? Map<String, dynamic>.from(v)
            : {'share': v[0], 'status': v[1], 'volume': v[3]})
        .toList();
  }

  Future<List<Map>> backupSources() async {
    final r =
        await call('SYNO.Backup.Source.Folder', 'list', {'node': 'fm_root'});
    return (r['folder'] as List ?? []).whereType<Map>().toList();
  }

  static Map<String, dynamic> localBackup(
      {String name,
      String share,
      String folder,
      List<String> sources,
      bool compress = true,
      bool daily = false,
      int hour = 2,
      int minute = 0}) {
    name = (name ?? '').trim();
    folder = (folder ?? '').trim();
    if (name.isEmpty ||
        name.length > 32 ||
        share == null ||
        share.isEmpty ||
        folder.isEmpty ||
        folder == '.' ||
        folder == '..' ||
        RegExp(r'[/\\\x00-\x1f]').hasMatch(folder) ||
        sources == null ||
        sources.isEmpty ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      throw FormatException('请填写任务名称、目标文件夹及备份源');
    }
    if (sources.any((s) => s == '/$share' || s.startsWith('/$share/'))) {
      throw FormatException('备份源不能包含目标共享文件夹');
    }
    return {
      'action': 'create',
      'target_type': 'image',
      'transfer_type': 'image_local',
      'name': name,
      'share': share,
      'target_id': folder.endsWith('.hbk') ? folder : '$folder.hbk',
      'source': {
        'file_list': sources,
        'app_list': [],
        'app_config': [],
        'backup_volumes': [],
        'backup_filter': {'whitelist': [], 'exclude_list': []}
      },
      'backup_params': {
        'enable_data_compress': compress,
        'enable_data_encrypt': false,
        'enable_notify': true,
        'bkp_config': true,
        'enable_version_file_log': false
      },
      'schedule': {
        'schedule_enable': daily,
        'hour': hour,
        'min': minute,
        'date_type': 0,
        'repeat': 0,
        'repeat_hour': 0,
        'last_work_hour': hour,
        'week_name': '0,1,2,3,4,5,6'
      },
      'rotate_params': {
        'enable_rotate': false,
        'rotate_option': 'rotate_earliest',
        'rotate_customized_rules': []
      },
    };
  }

  Future<int> createRepository(Map<String, dynamic> params) async {
    final shares = await backupShares();
    if (!shares.any((s) => s['share'] == params['share'] && s['status'] == 0))
      throw StateError('所选目标已不可用，请重新选择共享文件夹');
    final roots = await backupSources();
    final selected = (params['source']['file_list'] as List).cast<String>();
    if (selected
        .any((id) => !roots.any((s) => s['id'] == id && s['disabled'] != true)))
      throw StateError('备份源已变化，请重新选择');
    final r = await call('SYNO.Backup.Repository', 'create', params);
    final id = int.tryParse('${r['repo_id']}');
    if (id == null) throw StateError('存储库已提交，但未返回编号，请刷新存储库确认');
    return id;
  }

  Future<void> createBackupTask(Map<String, dynamic> params, int repoId) async {
    await call('SYNO.Backup.Task', 'create', {...params, 'repo_id': repoId});
  }

  Future<Map> cloud(String method, [Map<String, dynamic> params = const {}]) =>
      call('SYNO.CloudSync', method, params);

  Future<Map> cloudAccount(Map<String, dynamic> info) async {
    if (info['client_type'] == 'wd') {
      final r = await cloud('test_connection_webdav', {'conn_info': info});
      if (r['test_connect_success'] != true) throw StateError('WebDAV 连接验证失败');
      info = {...info, 'auth_scheme': r['auth_scheme']};
    }
    final user = await cloud('get_user_info', {'conn_info': info});
    return {...info, ...user};
  }

  Future<Map> cloudFolder(Map<String, dynamic> info, Map folder) =>
      cloud('get_server_folder_list', {
        'conn_info': info,
        'folder_path': folder['path'],
        'folder_id': folder['file_id'],
        'meta_list': folder['meta_list'] ?? []
      });

  Future<Map<String, dynamic>> cloudTask(Map<String, dynamic> account,
      {String name,
      String local,
      Map remote,
      String direction,
      bool keepDeleted = true}) async {
    if (!['wd', 'bd'].contains(account['client_type']) ||
        (name ?? '').trim().isEmpty ||
        local == null ||
        !local.startsWith('/') ||
        local.split('/').length < 2 ||
        local.split('/')[1].isEmpty ||
        local.split('/').any((p) => p == '..' || p == '.') ||
        remote == null ||
        remote['file_id'] == null ||
        !['BIDIRECTION', 'ONLY_UPLOAD', 'ONLY_DOWNLOAD'].contains(direction)) {
      throw FormatException('请选择本地及远程文件夹，并填写任务名称');
    }
    final defaults = await cloud('get_default_selective_sync_config');
    final parts = local.split('/');
    return {
      ...account,
      'mode_add_session': false,
      'task_name': name.trim(),
      'path': local,
      'path_share': parts[1],
      'path_sync': parts.length == 2 ? '/' : '/${parts.skip(2).join('/')}',
      'server_folder': remote['path'],
      'server_folder_path': remote['path'],
      'server_folder_id': remote['file_id'],
      'server_folder_meta_list': remote['meta_list'] ?? [],
      'sync_direction': direction,
      'no_delete': direction != 'BIDIRECTION' && keepDeleted,
      'server_encryption': false,
      'sync_attr_check_option': false,
      'filter_changed': false,
      'filter_folder': defaults['filtered_paths'] ?? [],
      'filter_file': {
        for (final k in [
          'filtered_max_upload_size',
          'filtered_extensions',
          'filtered_names',
          'user_defined_extensions',
          'user_defined_names'
        ])
          k: defaults[k]
      },
    };
  }

  Future<void> createCloud(Map<String, dynamic> info) async {
    // The native wizard validates first. A failed validation must never create a link.
    await cloud('test_task_setting', {'conn_info': info});
    await cloud('create_link', {'conn_info': info});
  }
}
