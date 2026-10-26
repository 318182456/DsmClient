import 'package:dio/dio.dart';
import 'package:dsm_client/models/nas_package.dart';
import 'package:dsm_client/models/program_section.dart';
import 'package:dsm_client/util/function.dart';
import 'package:dsm_client/util/program_api.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'program_page.dart';
import 'package:dsm_client/widgets/workspace.dart';

class DrivePage extends StatefulWidget {
  final NasPackage package;
  final String path, title;
  const DrivePage(this.package, {this.path = '/mydrive', this.title = '我的文件'});
  @override
  State<DrivePage> createState() => _DrivePageState();
}

class _DrivePageState extends State<DrivePage> {
  List<Map> files = [], teams = [];
  int offset = 0, total = 0;
  bool loading = true, busy = false;
  String error = '', filter = '';
  final search = TextEditingController();
  static const api = 'SYNO.SynologyDrive.Files';
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load({bool next = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
      if (!next) loading = true;
    });
    try {
      final result = await ProgramApi.call(
          ProgramSection('', api, 'list', version: 2),
          params: {
            'path': widget.path,
            'filter': {},
            'sort_by': 'name',
            'sort_direction': 'asc',
            'offset': next ? offset : 0,
            'limit': 100,
          });
      if (!mounted) return;
      if (result['success'] == true) {
        final batch = ((result['data'] ?? {})['items'] as List ?? [])
            .whereType<Map>()
            .toList();
        setState(() {
          files = next ? [...files, ...batch] : batch;
          offset = files.length;
          total = ((result['data'] ?? {})['total'] as num ?? offset).toInt();
        });
      } else {
        setState(() => error = ProgramApi.error(result));
      }
      if (!next && widget.path == '/mydrive') {
        final result = await ProgramApi.call(ProgramApi.drive.first);
        if (mounted && result['success'] == true)
          setState(() => teams = ProgramApi.drive.first.rows(result['data']));
      }
    } catch (_) {
      if (mounted) setState(() => error = '文件加载失败，请重试');
    } finally {
      if (mounted)
        setState(() {
          loading = false;
          busy = false;
        });
    }
  }

  String filePath(Map file) => 'id:${file['file_id']}';
  bool can(Map file, String capability) =>
      (file['capabilities'] ?? {})[capability] == true;
  Future<String> input(String title,
      {String initial = '', bool path = false}) async {
    final text = TextEditingController(text: initial);
    final value = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: Text(title),
                content: TextField(
                    controller: text,
                    autofocus: true,
                    decoration: InputDecoration(
                        hintText: path ? '/mydrive/目标文件夹 或 id:文件夹编号' : '输入名称')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog),
                      child: Text('取消')),
                  TextButton(
                      onPressed: () {
                        final name = text.text.trim();
                        if (name.isEmpty ||
                            (!path &&
                                (name == '.' ||
                                    name == '..' ||
                                    RegExp(r'[/\\]').hasMatch(name)))) {
                          Util.toast('请输入有效的名称');
                          return;
                        }
                        Navigator.pop(dialog, name);
                      },
                      child: Text('确认'))
                ]));
    // Dispose after the dialog route has finished animating its TextField.
    Future.delayed(Duration(milliseconds: 400), text.dispose);
    return value;
  }

  Future<void> mutate(String method, Map<String, dynamic> params,
      {String confirm}) async {
    if (busy) return;
    if (confirm != null) {
      final yes = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
                  title: Text(confirm),
                  content: Text('确认操作所选文件？'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialog, false),
                        child: Text('取消')),
                    TextButton(
                        onPressed: () => Navigator.pop(dialog, true),
                        child: Text('确认'))
                  ]));
      if (yes != true || !mounted) return;
    }
    setState(() => busy = true);
    try {
      final result = await ProgramApi.call(
          ProgramSection('', api, method, version: 2),
          params: params);
      if (!mounted) return;
      Util.toast(
          result['success'] == true ? '操作已提交' : ProgramApi.error(result));
    } catch (_) {
      Util.toast('连接失败，请刷新确认文件状态');
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) await load();
  }

  Future<void> upload() async {
    if (busy) return;
    final picked = await FilePicker.platform.pickFiles();
    if (!mounted || picked == null || picked.files.single.path == null) return;
    setState(() => busy = true);
    try {
      final file = picked.files.single;
      final result = await Util.upload('entry.cgi', params: {
        'api': api,
        'version': 2,
        'method': 'upload',
        'path': '${widget.path}/${file.name}',
        'conflict_action': 'autorename',
        '_sid': Util.sid,
      }, data: {
        'file': await MultipartFile.fromFile(file.path, filename: file.name)
      });
      if (mounted)
        Util.toast(
            result['success'] == true ? '上传完成' : ProgramApi.error(result));
    } catch (_) {
      Util.toast('上传失败，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) await load();
  }

  Future<void> fileAction(String action, Map file) async {
    if (busy) return;
    if (action == 'info') {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => Scaffold(
                  appBar: AppBar(title: Text('${file['name']}')),
                  body: SingleChildScrollView(child: NativeProperties(file)))));
    } else if (action == 'download') {
      final url =
          ProgramApi.url(ProgramSection('', api, 'download', version: 2), {
        'files': [filePath(file)],
        'force_download': true
      });
      try {
        await Util.download('${file['name']}', url);
        Util.toast('已加入下载队列');
      } catch (_) {
        Util.toast('无法创建下载任务，请检查存储权限');
      }
    } else if (action == 'rename') {
      final name = await input('重命名', initial: '${file['name']}');
      if (name != null && mounted)
        await mutate('update', {'path': filePath(file), 'name': name});
    } else if (action == 'move') {
      final target = await input('移动到', path: true);
      if (target != null && mounted)
        await mutate(
            'move',
            {
              'files': [filePath(file)],
              'to_parent_folder': target,
              'conflict_action': 'autorename'
            },
            confirm: '移动 ${file['name']}');
    } else if (action == 'delete') {
      await mutate(
          'delete',
          {
            'files': [filePath(file)],
            'permanent': false,
            'revisions': file['revisions']
          },
          confirm: '移到回收站：${file['name']}');
    } else if (action == 'share') {
      setState(() => busy = true);
      try {
        final result = await ProgramApi.call(
            ProgramSection('', 'SYNO.SynologyDrive.Sharing', 'create_link'),
            params: {'path': filePath(file)});
        if (!mounted) return;
        if (result['success'] == true) {
          final data = result['data'] ?? {};
          final link = data['url'] ?? data['link'] ?? data['sharing_link'];
          if (link is String && link.isNotEmpty) {
            await Clipboard.setData(ClipboardData(text: link));
            Util.toast('分享链接已复制');
          } else
            Util.toast('链接已创建，请在详情中查看');
        } else
          Util.toast(ProgramApi.error(result));
      } catch (_) {
        Util.toast('创建分享链接失败');
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }
  }

  void folder(String path, String title) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                DrivePage(widget.package, path: path, title: title)));
    if (mounted) load();
  }

  @override
  Widget build(BuildContext context) {
    final shown = files
        .where(
            (f) => '${f['name']}'.toLowerCase().contains(filter.toLowerCase()))
        .toList();
    return Scaffold(
        appBar: AppBar(title: Text('Drive · ${widget.title}'), actions: [
          IconButton(
              icon: Icon(Icons.dashboard_outlined),
              tooltip: 'Drive 管理',
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ProgramPage(widget.package)))),
          PopupMenuButton<String>(
              enabled: !busy,
              onSelected: (v) async {
                if (v == 'upload') {
                  upload();
                  return;
                }
                final name = await input('新建文件夹');
                if (name != null && mounted)
                  mutate('create', {
                    'path': '${widget.path}/$name',
                    'type': 'folder',
                    'conflict_action': 'autorename'
                  });
              },
              itemBuilder: (_) => [
                    PopupMenuItem(value: 'folder', child: Text('新建文件夹')),
                    PopupMenuItem(value: 'upload', child: Text('上传文件'))
                  ]),
        ]),
        body: Column(children: [
          WorkspaceHeader(
              title: widget.title,
              subtitle: widget.path == '/mydrive'
                  ? '我的空间 · Synology Drive'
                  : widget.path),
          if (busy && !loading) LinearProgressIndicator(),
          Padding(
              padding: EdgeInsets.all(16),
              child: TextField(
                  controller: search,
                  onChanged: (v) => setState(() => filter = v),
                  decoration: InputDecoration(
                      prefixIcon: Icon(Icons.search), hintText: '筛选已加载文件'))),
          Expanded(
              child: loading
                  ? Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: load,
                      child: ListView(
                          physics: AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            if (error.isNotEmpty)
                              ListTile(
                                  title: Text(error),
                                  trailing: IconButton(
                                      icon: Icon(Icons.refresh),
                                      onPressed: () => load())),
                            ...teams.map((t) => ListTile(
                                leading: Icon(Icons.folder_shared),
                                title: Text('团队 · ${t['name']}'),
                                onTap: () =>
                                    folder(filePath(t), '${t['name']}'))),
                            if (error.isEmpty && files.isEmpty)
                              WorkspaceEmpty('文件夹为空',
                                  icon: Icons.folder_open_outlined,
                                  detail: '使用右上角菜单上传文件或新建文件夹。'),
                            ...shown.map((f) {
                              final directory = f['type'] == 'dir' ||
                                  f['content_type'] == 'dir';
                              return Card(
                                  child: ListTile(
                                      leading: Icon(directory
                                          ? Icons.folder
                                          : Icons.insert_drive_file_outlined),
                                      title: Text('${f['name']}'),
                                      subtitle: Text(directory
                                          ? '文件夹'
                                          : Util.formatSize(
                                              f['size'] as num ?? 0,
                                              showByte: true)),
                                      onTap: () => directory
                                          ? folder(filePath(f), '${f['name']}')
                                          : fileAction('info', f),
                                      trailing: PopupMenuButton<String>(
                                          enabled: !busy,
                                          onSelected: (v) => fileAction(v, f),
                                          itemBuilder: (_) => [
                                                PopupMenuItem(
                                                    value: 'info',
                                                    child: Text('详细信息')),
                                                if (can(f, 'can_download') &&
                                                    !directory)
                                                  PopupMenuItem(
                                                      value: 'download',
                                                      child: Text('下载')),
                                                if (can(f, 'can_rename'))
                                                  PopupMenuItem(
                                                      value: 'rename',
                                                      child: Text('重命名')),
                                                if (can(f, 'can_organize'))
                                                  PopupMenuItem(
                                                      value: 'move',
                                                      child: Text('移动')),
                                                if (can(f, 'can_share'))
                                                  PopupMenuItem(
                                                      value: 'share',
                                                      child: Text('创建分享链接')),
                                                if (can(f, 'can_delete'))
                                                  PopupMenuItem(
                                                      value: 'delete',
                                                      child: Text('移到回收站')),
                                              ])));
                            }),
                            if (offset < total)
                              TextButton(
                                  onPressed:
                                      busy ? null : () => load(next: true),
                                  child: Text('加载更多（$offset / $total）')),
                          ]))),
        ]));
  }
}
