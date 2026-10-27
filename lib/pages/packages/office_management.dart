import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dsm_client/models/font_family_reader.dart';
import 'package:dsm_client/util/drive_admin_api.dart';
import 'package:dsm_client/widgets/workspace.dart';
import 'drive_console.dart';
import 'ai_console.dart';
import 'program_page.dart';
import 'package:dsm_client/models/nas_package.dart';

class OfficeConsole extends StatelessWidget {
  final NasPackage package;
  final DriveAdminApi api;
  OfficeConsole(this.package, {DriveAdminApi api})
      : api = api ?? DriveAdminApi();
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('Office 管理'), actions: [
        IconButton(
            tooltip: '套件运行管理',
            icon: Icon(Icons.info_outline),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ProgramPage(package, sections: []))))
      ]),
      body: ListView(padding: EdgeInsets.all(16), children: [
        for (final title in ['字体', '版本轮换', 'AI 助理'])
          Card(
              child: ListTile(
                  title: Text(title),
                  trailing: Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => title == '字体'
                              ? OfficeFontsPage(api)
                              : title == '版本轮换'
                                  ? OfficeHistoryPage(api)
                                  : AiConsolePage(api))))),
      ]));
}

class OfficeFontsPage extends StatefulWidget {
  final DriveAdminApi api;
  const OfficeFontsPage(this.api);
  @override
  State<OfficeFontsPage> createState() => _OfficeFontsState();
}

class _OfficeFontsState extends State<OfficeFontsPage> {
  Map fonts = {};
  bool busy = false;
  String error = '', query = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final v = await widget.api.fonts();
      if (mounted)
        setState(() {
          fonts = v;
          error = '';
        });
    } catch (e) {
      if (mounted) setState(() => error = driveError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> action(String verb, List<String> names) async {
    if (busy) return;
    final title = const {
      'add': '登记字体',
      'enable': '启用字体',
      'disable': '停用字体',
      'delete': '删除字体'
    }[verb];
    if (!await confirmDrive(context, title,
            '$title：${names.join('、')}。这会改变 Office 中可用的字体列表；登记字体只提交家族名称，显示效果取决于编辑设备是否支持该字体。') ||
        !mounted) return;
    setState(() => busy = true);
    String failure;
    try {
      await widget.api.fontAction(verb, names);
    } catch (e) {
      failure = driveError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) {
      await load();
      if (failure != null && mounted) setState(() => error = failure);
    }
  }

  Future<void> addName() async {
    final text = await askDriveText(context, '登记字体名称', '字体家族名称（多个用逗号或换行分隔）');
    if (text == null || !mounted) return;
    final names = text
        .split(RegExp(r'[,，\n]'))
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList();
    if (names.isNotEmpty) await action('add', names);
  }

  Future<void> fromFile() async {
    if (busy) return;
    try {
      final selected = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['ttf', 'otf', 'ttc']);
      if (selected == null || selected.files.isEmpty || !mounted) return;
      final path = selected.files.single.path;
      if (path == null) throw FormatException('无法读取所选字体文件');
      final file = File(path);
      if (await file.length() > 32 * 1024 * 1024)
        throw FormatException('字体文件不能超过 32 MB');
      final families = FontFamilyReader.read(await file.readAsBytes());
      if (mounted) await action('add', families);
    } catch (e) {
      if (mounted) setState(() => error = driveError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = fonts.entries
        .where((e) =>
            '${e.key} ${(e.value is Map ? e.value : {})['display'] ?? ''}'
                .toLowerCase()
                .contains(query.toLowerCase()))
        .toList()
      ..sort((a, b) =>
          '${a.key}'.toLowerCase().compareTo('${b.key}'.toLowerCase()));
    return Scaffold(
        appBar: AppBar(title: Text('Office 字体'), actions: [
          IconButton(
              tooltip: '刷新字体',
              icon: Icon(Icons.refresh),
              onPressed: busy ? null : load),
          PopupMenuButton<String>(
              tooltip: '添加字体',
              enabled: !busy,
              onSelected: (v) => v == 'file' ? fromFile() : addName(),
              itemBuilder: (_) => [
                    PopupMenuItem(value: 'name', child: Text('输入字体名称')),
                    PopupMenuItem(value: 'file', child: Text('从字体文件读取'))
                  ])
        ]),
        body: Column(children: [
          if (busy) LinearProgressIndicator(minHeight: 2),
          Padding(
              padding: EdgeInsets.all(16),
              child: TextField(
                  onChanged: (v) => setState(() => query = v),
                  decoration: InputDecoration(
                      labelText: '搜索字体', prefixIcon: Icon(Icons.search)))),
          Expanded(
              child: RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                      padding: EdgeInsets.all(16),
                      physics: AlwaysScrollableScrollPhysics(),
                      children: [
                        if (error.isNotEmpty)
                          Text(error,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        if (rows.isEmpty && !busy && error.isEmpty)
                          WorkspaceEmpty('暂无字体'),
                        for (final e in rows)
                          Card(
                              child: ListTile(
                                  title: Text(
                                      '${(e.value is Map ? e.value : {})['display'] ?? e.key}'),
                                  subtitle: Text(
                                      '${(e.value is Map ? e.value : {})['system'] != false ? '系统字体' : '自定义字体'} · ${(e.value is Map ? e.value : {})['disable'] == true ? '已停用' : '已启用'}'),
                                  trailing: PopupMenuButton<String>(
                                      tooltip: '字体操作',
                                      enabled: !busy,
                                      onSelected: (v) =>
                                          action(v, ['${e.key}']),
                                      itemBuilder: (_) => [
                                            PopupMenuItem(
                                                value: (e.value is Map
                                                            ? e.value
                                                            : {})['disable'] ==
                                                        true
                                                    ? 'enable'
                                                    : 'disable',
                                                enabled: '${e.key}'
                                                            .toLowerCase() !=
                                                        'arial' ||
                                                    (e.value is Map
                                                            ? e.value
                                                            : {})['disable'] ==
                                                        true,
                                                child: Text((e.value is Map
                                                            ? e.value
                                                            : {})['disable'] ==
                                                        true
                                                    ? '启用'
                                                    : '停用')),
                                            if ((e.value is Map
                                                    ? e.value
                                                    : {})['system'] ==
                                                false)
                                              PopupMenuItem(
                                                  value: 'delete',
                                                  child: Text('删除')),
                                          ]))),
                      ]))),
        ]));
  }
}

class OfficeHistoryPage extends StatefulWidget {
  final DriveAdminApi api;
  const OfficeHistoryPage(this.api);
  @override
  State<OfficeHistoryPage> createState() => _OfficeHistoryState();
}

class _OfficeHistoryState extends State<OfficeHistoryPage> {
  bool busy = false, enabled = false, original = false, loaded = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final v = await widget.api.officeSettings();
      if (v['history_prune'] is! bool)
        throw FormatException('当前 Office 未返回版本轮换设置');
      if (mounted)
        setState(() {
          enabled = v['history_prune'];
          original = enabled;
          loaded = true;
          error = '';
        });
    } catch (e) {
      if (mounted) setState(() => error = driveError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (busy || !loaded || enabled == original) return;
    if (!await confirmDrive(
            context,
            '保存版本轮换设置',
            enabled
                ? '开启后 Office 会按服务器策略精简文档历史版本，被清理的版本无法通过此页面恢复。是否继续？'
                : '关闭 Office 文档历史版本轮换？已有文档和当前版本会保留。') ||
        !mounted) return;
    setState(() => busy = true);
    try {
      await widget.api.setOfficeHistory(enabled);
      if (mounted)
        setState(() {
          original = enabled;
          error = '';
        });
    } catch (e) {
      if (mounted) setState(() => error = driveError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('Office 版本轮换'), actions: [
        IconButton(
            tooltip: '刷新版本设置',
            icon: Icon(Icons.refresh),
            onPressed: busy ? null : load)
      ]),
      body: ListView(padding: EdgeInsets.all(16), children: [
        if (busy) LinearProgressIndicator(minHeight: 2),
        Card(
            child: SwitchListTile(
                title: Text('启用文档历史版本轮换'),
                subtitle:
                    Text('按 Office 服务器策略管理文档历史版本，区别于 Drive 团队文件夹的版本数量设置。'),
                value: enabled,
                onChanged: busy || !loaded
                    ? null
                    : (v) => setState(() => enabled = v))),
        if (error.isNotEmpty)
          Text(error,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        SizedBox(height: 16),
        ElevatedButton(
            onPressed: busy || !loaded || enabled == original ? null : save,
            child: Text('保存设置')),
      ]));
}
