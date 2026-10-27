import 'package:flutter/material.dart';
import '../../util/backup_cloud_api.dart';
import '../../util/function.dart';
import '../../models/cloud_oauth.dart';
import '../../widgets/workspace.dart';
import '../file/select_folder.dart';
import 'cloud_authorization.dart';
import 'drive_console.dart' show confirmDrive;

String _failure(Object e) => e is StateError
    ? '${e.message}'
    : e is FormatException
        ? e.message
        : '连接失败，请重试';

Widget _input(TextEditingController controller, String label,
        {bool secret = false}) =>
    Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: TextField(
            controller: controller,
            obscureText: secret,
            autocorrect: false,
            enableSuggestions: !secret,
            decoration: InputDecoration(labelText: label)));

class LocalBackupCreate extends StatefulWidget {
  final BackupCloudApi api;
  LocalBackupCreate({BackupCloudApi api}) : api = api ?? BackupCloudApi();
  @override
  State<LocalBackupCreate> createState() => _LocalBackupCreateState();
}

class _LocalBackupCreateState extends State<LocalBackupCreate> {
  final name = TextEditingController(text: '本地备份');
  final folder = TextEditingController(text: 'DsmClientBackup');
  List<Map> shares = [], sources = [];
  final selected = <String>{};
  String share, error = '';
  bool busy = false, loading = true, compress = true, daily = false;
  TimeOfDay time = TimeOfDay(hour: 2, minute: 0);
  int repoId;
  Map<String, dynamic> pending;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    name.dispose();
    folder.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final results = await Future.wait(
          [widget.api.backupShares(), widget.api.backupSources()]);
      if (!mounted) return;
      setState(() {
        shares = results[0].where((v) => v['status'] == 0).toList();
        sources = results[1]
            .where((v) =>
                v['disabled'] != true &&
                v['isC2Share'] != true &&
                v['isTieringShare'] != true &&
                v['isTieringVault'] != true)
            .toList();
        share = shares.isEmpty ? null : '${shares.first['share']}';
      });
    } catch (e) {
      if (mounted) setState(() => error = _failure(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> create() async {
    if (busy) return;
    Map<String, dynamic> params;
    try {
      params = pending ??
          BackupCloudApi.localBackup(
              name: name.text,
              share: share,
              folder: folder.text,
              sources: selected.toList(),
              compress: compress,
              daily: daily,
              hour: time.hour,
              minute: time.minute);
    } catch (e) {
      setState(() => error = _failure(e));
      return;
    }
    final yes = await confirmDrive(
        context,
        repoId == null ? '创建本地备份任务' : '继续创建任务',
        '${params['name']}\n目标：/${params['share']}/${params['target_id']}\n'
        '备份 ${selected.length} 个共享文件夹。${daily ? '每天 ${time.format(context)} 运行。' : '创建后手动运行。'}'
        '\n${repoId == null ? '将创建新的多版本备份存储库和任务。' : '继续使用已创建的存储库 $repoId，不会重复创建存储库。'}');
    if (!yes || !mounted) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      pending = params;
      repoId ??= await widget.api.createRepository(params);
      await widget.api.createBackupTask(params, repoId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() => error =
            '${_failure(e)}${repoId == null ? '' : '\n存储库 $repoId 已创建。可点击继续创建任务，或返回存储库页查看。'}');
      if (repoId == null) pending = null;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('新建本地备份')),
      body: loading
          ? Center(child: CircularProgressIndicator())
          : ListView(padding: EdgeInsets.all(20), children: [
              WorkspaceHeader(
                  title: '保护 NAS 上的重要文件', subtitle: '本地共享文件夹 · 多版本备份（.hbk）'),
              if (busy) LinearProgressIndicator(),
              AbsorbPointer(
                  absorbing: busy || repoId != null,
                  child: Column(children: [
                    _input(name, '任务名称'),
                    DropdownButtonFormField<String>(
                        value: share,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: '目标共享文件夹'),
                        items: shares
                            .map((s) => DropdownMenuItem(
                                value: '${s['share']}',
                                child: Text('${s['share']}')))
                            .toList(),
                        onChanged: (v) => setState(() {
                              share = v;
                              selected.removeWhere(
                                  (s) => s == '/$v' || s.startsWith('/$v/'));
                            })),
                    SizedBox(height: 16),
                    _input(folder, '备份存储库文件夹名称'),
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Text('备份源',
                            style: Theme.of(context).textTheme.subtitle1)),
                    ...sources.map((s) => CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${s['text'] ?? s['id']}'),
                        value: selected.contains(s['id']),
                        onChanged: '${s['id']}' == '/$share'
                            ? null
                            : (v) => setState(() {
                                  if (v)
                                    selected.add('${s['id']}');
                                  else
                                    selected.remove('${s['id']}');
                                }))),
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('压缩备份数据'),
                        value: compress,
                        onChanged: (v) => setState(() => compress = v)),
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('每天自动备份'),
                        value: daily,
                        onChanged: (v) => setState(() => daily = v)),
                    if (daily)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('运行时间'),
                          trailing: Text(time.format(context)),
                          onTap: () async {
                            final value = await showTimePicker(
                                context: context, initialTime: time);
                            if (value != null && mounted)
                              setState(() => time = value);
                          }),
                  ])),
              Text('创建后保留全部版本，不自动清理历史版本。需要轮换时可在 DSM 中设置。'),
              if (error.isNotEmpty)
                Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(error,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              if (shares.isEmpty || sources.isEmpty)
                TextButton(
                    onPressed: busy ? null : load, child: Text('重新加载文件夹')),
              SizedBox(height: 16),
              ElevatedButton(
                  onPressed:
                      busy || shares.isEmpty || sources.isEmpty ? null : create,
                  child: Text(busy
                      ? '正在创建…'
                      : repoId == null
                          ? '创建备份任务'
                          : '继续创建任务')),
            ]));
}

class CloudSyncCreate extends StatefulWidget {
  final BackupCloudApi api;
  CloudSyncCreate({BackupCloudApi api}) : api = api ?? BackupCloudApi();
  @override
  State<CloudSyncCreate> createState() => _CloudSyncCreateState();
}

class _CloudSyncCreateState extends State<CloudSyncCreate> {
  final server = TextEditingController(text: 'https://');
  final user = TextEditingController(), password = TextEditingController();
  final name = TextEditingController(text: 'WebDAV 同步'),
      local = TextEditingController();
  String type = 'wd', direction = 'ONLY_UPLOAD', error = '';
  bool busy = false, keepDeleted = true;
  Map<String, dynamic> account;
  Map remote;
  @override
  void dispose() {
    for (final c in [server, user, password, name, local]) c.dispose();
    account?.clear();
    super.dispose();
  }

  Future<void> connect() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      Map<String, dynamic> info;
      if (type == 'bd') {
        info = await Navigator.push<Map<String, dynamic>>(
            context,
            MaterialPageRoute(
                builder: (_) => CloudAuthorization(CloudOAuth(Util.baseUrl))));
        if (info == null) return;
      } else {
        final uri = Uri.tryParse(server.text.trim());
        if (uri == null ||
            !['http', 'https'].contains(uri.scheme) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            uri.hasFragment ||
            user.text.trim().isEmpty ||
            password.text.isEmpty)
          throw FormatException('请填写 WebDAV 服务地址、账号和密码');
        info = {
          'client_type': 'wd',
          'server_addr': uri.toString(),
          'auth_user': user.text.trim(),
          'auth_pass': password.text
        };
      }
      final result = await widget.api.cloudAccount(info);
      if (!mounted) return;
      password.clear();
      setState(() {
        account = result;
        remote = {
          'path': '/',
          'file_id': result['root_folder_id'] ?? '',
          'meta_list': [
            {
              'path': '/',
              'file_id': result['root_folder_id'] ?? '',
              'parent_id': '',
              'title': '',
              'mtime': 0,
              'alternatelink': ''
            }
          ]
        };
      });
    } catch (e) {
      if (mounted) setState(() => error = _failure(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> create() async {
    if (busy || account == null) return;
    if (name.text.trim().isEmpty || local.text.trim().isEmpty) {
      setState(() => error = '请填写任务名称并选择本地文件夹');
      return;
    }
    final yes = await confirmDrive(
        context,
        '创建云同步任务',
        '${name.text.trim()}\n本地：${local.text.trim()}\n远程：${remote['path']}\n'
            '${_directions[direction]}。任务创建后会立即开始同步。'
            '${direction == 'BIDIRECTION' ? '\n双向同步会将文件修改及删除同步到另一端。' : keepDeleted ? '\n不删除目标端已有文件。' : '\n源端删除也会同步到目标端。'}');
    if (!yes || !mounted) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final info = await widget.api.cloudTask(account,
          name: name.text,
          local: local.text.trim(),
          remote: remote,
          direction: direction,
          keepDeleted: keepDeleted);
      await widget.api.createCloud(info);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = _failure(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  static const _directions = {
    'ONLY_UPLOAD': '仅上传本地更改',
    'ONLY_DOWNLOAD': '仅下载远程更改',
    'BIDIRECTION': '双向同步'
  };
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('新建云同步')),
      body: ListView(padding: EdgeInsets.all(20), children: [
        WorkspaceHeader(
            title: account == null ? '连接云端存储' : '设置同步任务',
            subtitle: account == null
                ? '选择服务并验证连接，然后设置同步文件夹。'
                : '服务端持续同步，关闭手机 App 后仍会运行。'),
        if (busy) LinearProgressIndicator(),
        if (account == null) ...[
          DropdownButtonFormField<String>(
              value: type,
              decoration: InputDecoration(labelText: '云服务'),
              items: [
                DropdownMenuItem(value: 'wd', child: Text('WebDAV')),
                DropdownMenuItem(value: 'bd', child: Text('百度网盘'))
              ],
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                        type = v;
                        error = '';
                        name.text = v == 'bd' ? '百度网盘同步' : 'WebDAV 同步';
                      })),
          SizedBox(height: 20),
          if (type == 'wd') ...[
            _input(server, 'WebDAV 服务地址'),
            _input(user, '账号'),
            _input(password, '密码', secret: true)
          ],
          ElevatedButton(
              onPressed: busy ? null : connect,
              child: Text(busy
                  ? '正在连接…'
                  : type == 'bd'
                      ? '登录并授权百度网盘'
                      : '验证并连接')),
        ] else ...[
          _input(name, '任务名称'),
          _input(local, '本地文件夹（如 /共享名称/子文件夹）'),
          TextButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      final paths = await Navigator.push<List>(context,
                          MaterialPageRoute(builder: (_) => SelectFolder()));
                      if (paths != null && paths.isNotEmpty && mounted)
                        setState(() => local.text = '${paths.first}');
                    },
              icon: Icon(Icons.folder_open),
              label: Text('选择 NAS 文件夹')),
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.cloud_outlined),
              title: Text('远程文件夹'),
              subtitle: Text('${remote['path']}'),
              trailing: Icon(Icons.chevron_right),
              onTap: busy
                  ? null
                  : () async {
                      final folder = await Navigator.push<Map>(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  CloudRemoteFolder(widget.api, account)));
                      if (folder != null && mounted)
                        setState(() => remote = folder);
                    }),
          SizedBox(height: 16),
          DropdownButtonFormField<String>(
              value: direction,
              decoration: InputDecoration(labelText: '同步方向'),
              items: _directions.entries
                  .map((v) =>
                      DropdownMenuItem(value: v.key, child: Text(v.value)))
                  .toList(),
              onChanged: busy ? null : (v) => setState(() => direction = v)),
          if (direction != 'BIDIRECTION')
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('不删除目标端文件'),
                subtitle: Text('源端删除后，目标端继续保留文件'),
                value: keepDeleted,
                onChanged:
                    busy ? null : (v) => setState(() => keepDeleted = v)),
          SizedBox(height: 16),
          ElevatedButton(
              onPressed: busy ? null : create,
              child: Text(busy ? '正在创建…' : '创建同步任务')),
          TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                        account?.clear();
                        account = null;
                        remote = null;
                      }),
              child: Text('重新选择账号')),
        ],
        if (error.isNotEmpty)
          Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(error,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
      ]));
}

class CloudRemoteFolder extends StatefulWidget {
  final BackupCloudApi api;
  final Map<String, dynamic> account;
  const CloudRemoteFolder(this.api, this.account);
  @override
  State<CloudRemoteFolder> createState() => _CloudRemoteFolderState();
}

class _CloudRemoteFolderState extends State<CloudRemoteFolder> {
  final stack = <Map>[];
  List<Map> folders = [];
  bool loading = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    stack.add({
      'path': '/',
      'file_id': widget.account['root_folder_id'] ?? '',
      'meta_list': [
        {
          'path': '/',
          'file_id': widget.account['root_folder_id'] ?? '',
          'parent_id': '',
          'title': '',
          'mtime': 0,
          'alternatelink': ''
        }
      ]
    });
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final r = await widget.api.cloudFolder(widget.account, stack.last);
      if (mounted)
        setState(() =>
            folders = (r['children'] as List ?? []).whereType<Map>().toList());
    } catch (e) {
      if (mounted) setState(() => error = _failure(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('选择远程文件夹')),
      body: Column(children: [
        ListTile(
            title: Text('${stack.last['path']}'),
            leading: IconButton(
                icon: Icon(Icons.arrow_upward),
                onPressed: loading || stack.length < 2
                    ? null
                    : () {
                        stack.removeLast();
                        load();
                      })),
        if (loading) LinearProgressIndicator(),
        if (error.isNotEmpty)
          ListTile(
              title: Text(error),
              trailing: IconButton(
                  icon: Icon(Icons.refresh), onPressed: loading ? null : load)),
        Expanded(
            child: ListView(
                children: folders
                    .map((f) => ListTile(
                        leading: Icon(Icons.folder_outlined),
                        title: Text('${f['text'] ?? f['title'] ?? f['path']}'),
                        trailing: Icon(Icons.chevron_right),
                        onTap: loading
                            ? null
                            : () {
                                stack.add(f);
                                load();
                              }))
                    .toList())),
        SafeArea(
            child: Padding(
                padding: EdgeInsets.all(16),
                child: ElevatedButton(
                    onPressed: loading || error.isNotEmpty
                        ? null
                        : () => Navigator.pop(context, stack.last),
                    child: Text('选择此文件夹')))),
      ]));
}
