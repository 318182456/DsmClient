import 'package:flutter/material.dart';
import 'package:dsm_client/models/nas_package.dart';
import 'package:dsm_client/util/drive_admin_api.dart';
import 'package:dsm_client/widgets/workspace.dart';
import 'package:dsm_client/widgets/nas_app_icon.dart';
import 'drive.dart';
import 'program_page.dart';
import 'drive_management.dart';
import 'office_management.dart';
import 'ai_console.dart';

Future<String> askDriveText(BuildContext context, String title, String label,
        {String initial = ''}) =>
    showDialog<String>(
        context: context,
        builder: (_) => _DriveTextDialog(title, label, initial));

class _DriveTextDialog extends StatefulWidget {
  final String title, label, initial;
  const _DriveTextDialog(this.title, this.label, this.initial);
  @override
  State<_DriveTextDialog> createState() => _DriveTextState();
}

class _DriveTextState extends State<_DriveTextDialog> {
  TextEditingController controller;
  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.title),
          content: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(labelText: widget.label)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: Text('下一步'))
          ]);
}

Future<bool> confirmDrive(
        BuildContext context, String title, String message) async =>
    await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: Text(title),
                content: SingleChildScrollView(child: Text(message)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: Text('确认'))
                ])) ??
    false;

String driveError(Object error) => error is StateError
    ? '${error.message}'
    : error is FormatException
        ? error.message
        : '连接失败，请检查网络、账号权限和套件版本';

class DriveConsole extends StatefulWidget {
  final NasPackage package;
  final DriveAdminApi api;
  DriveConsole(this.package, {DriveAdminApi api})
      : api = api ?? DriveAdminApi();
  @override
  State<DriveConsole> createState() => _DriveConsoleState();
}

class _DriveConsoleState extends State<DriveConsole> {
  bool busy = false;
  String error = '';
  Map status = {}, summary = {};
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final data =
          await Future.wait([widget.api.status(), widget.api.summary()]);
      if (mounted)
        setState(() {
          status = data[0];
          summary = data[1];
          error = '';
        });
    } catch (e) {
      if (mounted) setState(() => error = driveError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void open(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  Widget entry(String title, String description, IconData icon,
          Widget Function() page) =>
      Card(
          child: ListTile(
              leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
              title: Text(title),
              subtitle: Text(description),
              trailing: Icon(Icons.chevron_right),
              onTap: () => open(page())));
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('Drive 控制台'), actions: [
        IconButton(
            tooltip: '刷新控制台',
            icon: Icon(Icons.refresh),
            onPressed: busy ? null : load),
        IconButton(
            tooltip: '浏览 Drive 文件',
            icon: Icon(Icons.folder_outlined),
            onPressed: () => open(DrivePage(widget.package))),
        PopupMenuButton<String>(
            tooltip: '服务选项',
            onSelected: (_) => open(ProgramPage(widget.package, sections: [])),
            itemBuilder: (_) =>
                [PopupMenuItem(value: 'package', child: Text('套件运行管理'))]),
      ]),
      body: RefreshIndicator(
          onRefresh: load,
          child: ListView(
              padding: EdgeInsets.all(16),
              physics: AlwaysScrollableScrollPhysics(),
              children: [
                if (busy) LinearProgressIndicator(minHeight: 2),
                WorkspaceHeader(
                    title: 'Synology Drive',
                    subtitle: '总览与管理 · ${widget.package.version}',
                    leading: NasAppIcon(widget.package,
                        size: 44, appIds: ['SYNO.SDS.CSTN.Instance'])),
                if (error.isNotEmpty)
                  Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(error,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
                Card(
                    child: ListTile(
                        leading: Icon(
                            status['csrv_enable'] == true
                                ? Icons.check_circle
                                : Icons.info_outline,
                            color: Theme.of(context).colorScheme.primary),
                        title: Text(status.isEmpty
                            ? '服务状态待刷新'
                            : status['csrv_enable'] == true
                                ? 'Drive 服务已启用'
                                : 'Drive 服务未启用'),
                        subtitle: Text(status['cstn_freeze'] == true
                            ? '服务处于暂停状态'
                            : '查看服务详情可核对运行状态'),
                        onTap: () => open(Scaffold(
                            appBar: AppBar(title: Text('服务状态')),
                            body: SingleChildScrollView(
                                padding: EdgeInsets.all(16),
                                child: NativeProperties(status)))))),
                Card(
                    child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Wrap(spacing: 20, runSpacing: 16, children: [
                          for (final item in const {
                            'total': '客户端总数',
                            'desktop': '桌面客户端',
                            'sharesync': 'ShareSync',
                            'mobile': '移动设备'
                          }.entries)
                            SizedBox(
                                width: 130,
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('${summary[item.key] ?? '—'}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .headline5),
                                      Text(item.value)
                                    ])),
                        ]))),
                entry('客户端列表', '查看连接状态，断开指定客户端', Icons.devices,
                    () => DriveRecordsPage(widget.api, kind: 'clients')),
                entry('日志', '搜索、筛选和分页查看同步记录', Icons.list_alt,
                    () => DriveRecordsPage(widget.api, kind: 'logs')),
                entry('团队文件夹', '启停同步、版本保留及文件保护设置', Icons.folder_shared_outlined,
                    () => DriveRecordsPage(widget.api, kind: 'shares')),
                entry('高级功能', '查看激活状态，使用合法激活码激活', Icons.verified_outlined,
                    () => DriveActivationPage(widget.api)),
                entry('设置', '数据库、文件索引及共享权限设置', Icons.settings_outlined,
                    () => DriveSettingsPage(widget.api)),
                Padding(
                    padding: EdgeInsets.fromLTRB(4, 20, 4, 12),
                    child: Text('Synology Office',
                        style: Theme.of(context).textTheme.titleLarge)),
                entry(
                    '字体',
                    '登记字体名称、启用、停用及删除自定义字体',
                    Icons.font_download_outlined,
                    () => OfficeFontsPage(widget.api)),
                entry('版本轮换', '设置 Office 文档历史版本轮换', Icons.history,
                    () => OfficeHistoryPage(widget.api)),
                entry(
                    'AI 助理',
                    '查看 NAS AI Console 的集成及应用策略',
                    Icons.auto_awesome_outlined,
                    () => AiConsolePage(widget.api)),
              ])));
}
