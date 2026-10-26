import 'package:dsm_client/models/nas_package.dart';
import 'package:dsm_client/models/program_section.dart';
import 'package:dsm_client/pages/file/file.dart';
import 'package:dsm_client/pages/terminal/select_server.dart';
import 'package:dsm_client/util/function.dart';
import 'package:dsm_client/util/program_api.dart';
import 'package:flutter/material.dart';

/// Native package workspace: requests business APIs and renders Flutter widgets.
/// Packages without a business adapter explicitly show their supported scope.
class ProgramPage extends StatelessWidget {
  final NasPackage package;
  final List<ProgramSection> sections;
  ProgramPage(this.package, {List<ProgramSection> sections})
      : sections = sections ?? ProgramApi.sections(package.id);

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      ...sections.map((s) => Tab(text: s.title)),
      Tab(text: '套件信息')
    ];
    return DefaultTabController(
        length: tabs.length,
        child: Scaffold(
          appBar: AppBar(
              title: Text(package.name),
              bottom: tabs.length > 1
                  ? TabBar(isScrollable: true, tabs: tabs)
                  : null),
          body: TabBarView(children: [
            ...sections.map((s) => ProgramDataView(s, packageId: package.id)),
            ListView(padding: EdgeInsets.all(20), children: [
              ListTile(
                  leading: Icon(Icons.apps),
                  title: Text(package.name),
                  subtitle: Text(
                      '${package.version} · ${package.status == 'running' ? '运行中' : package.status}')),
              Text(package.description.replaceAll(RegExp(r'<[^>]*>'), '')),
              SizedBox(height: 20),
              if (sections.isEmpty) Text('当前支持版本、运行状态和相关工具。此程序的专用业务功能尚未接入。'),
              ListTile(
                  leading: Icon(Icons.folder_outlined),
                  title: Text('文件管理'),
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => Files()))),
              ListTile(
                  leading: Icon(Icons.terminal),
                  title: Text('SSH 终端'),
                  subtitle: Text('连接你配置的服务器'),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => SelectServer()))),
            ])
          ]),
        ));
  }
}

class ProgramDataView extends StatefulWidget {
  final ProgramSection section;
  final String packageId;
  const ProgramDataView(this.section, {this.packageId = '', Key key})
      : super(key: key);
  @override
  State<ProgramDataView> createState() => _ProgramDataViewState();
}

class _ProgramDataViewState extends State<ProgramDataView>
    with AutomaticKeepAliveClientMixin {
  bool loading = true, more = false, busy = false;
  String error = '', query = '';
  dynamic data;
  List<Map> rows = [];
  int offset = 0;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool next = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
      if (!next) loading = true;
    });
    try {
      final requestedOffset = next ? offset : 0;
      final result =
          await ProgramApi.call(widget.section, offset: requestedOffset);
      if (!mounted) return;
      if (result['success'] != true) {
        setState(() => error = ProgramApi.error(result));
      } else {
        final batch = widget.section.rows(result['data']);
        setState(() {
          data = ProgramSection.publicValue(result['data']);
          rows = next ? [...rows, ...batch] : batch;
          offset = requestedOffset + batch.length;
          final total = result['data'] is Map ? result['data']['total'] : null;
          more = widget.section.params.containsKey('offset') &&
              batch.isNotEmpty &&
              (total is num ? offset < total : batch.length >= 100);
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '连接失败，请重试');
    } finally {
      if (mounted)
        setState(() {
          loading = false;
          busy = false;
        });
    }
  }

  Future<void> action(
      String title, ProgramSection section, Map<String, dynamic> params) async {
    if (busy) return;
    final yes = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: Text(title),
                content: Text('此操作会更改 NAS 上的任务状态，是否继续？'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: Text('确认'))
                ]));
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      final result = await ProgramApi.call(section, params: params);
      if (!mounted) return;
      Util.toast(
          result['success'] == true ? '操作已提交' : ProgramApi.error(result));
    } catch (_) {
      Util.toast('连接失败，请刷新确认任务状态');
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) await load();
  }

  void open(ProgramSection section) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => Scaffold(
                appBar: AppBar(title: Text(section.title)),
                body: ProgramDataView(section, packageId: widget.packageId))));
  }

  Widget row(Map item) {
    final title =
        '${item['title'] ?? item['name'] ?? item['task_display_name'] ?? item['client_name'] ?? item['file_name'] ?? item['local_sync_path'] ?? item['s1'] ?? item['share'] ?? item['path'] ?? item['time'] ?? item['id'] ?? '详细信息'}';
    final subtitle = [
      item['status'] ??
          item['state'] ??
          item['sync_status'] ??
          item['last_bkp_result'] ??
          item['desc'],
      item['last_bkp_time'] ??
          item['client_ip'] ??
          item['user_name'] ??
          item['location']
    ].where((v) => v != null && '$v'.isNotEmpty).join(' · ');
    final taskId = item['task_id'] ?? item['id'];
    final cloudId = item['id'];
    final backupTask =
        widget.section.api == 'SYNO.Backup.Task' && taskId != null;
    final cloudConnection =
        widget.section.method == 'list_conn' && cloudId != null;
    return Card(
        child: Column(children: [
      ListTile(
          title: Text(title),
          subtitle: subtitle.isEmpty ? null : Text(subtitle),
          trailing: Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(title)),
                      body: SingleChildScrollView(
                          padding: EdgeInsets.all(16),
                          child: NativeProperties(item)))))),
      if (backupTask)
        Wrap(children: [
          TextButton(
              onPressed: () => open(ProgramSection(
                  '任务状态', 'SYNO.Backup.Task', 'status',
                  params: {'task_id': taskId})),
              child: Text('实时状态')),
          TextButton(
              onPressed: busy
                  ? null
                  : () => action(
                      '立即备份',
                      ProgramSection('', 'SYNO.Backup.Task', 'backup'),
                      {'task_id': taskId}),
              child: Text('立即备份')),
          TextButton(
              onPressed: busy
                  ? null
                  : () => action(
                      '取消备份',
                      ProgramSection('', 'SYNO.Backup.Task', 'cancel'),
                      {'task_id': taskId, 'task_state': 'backupable'}),
              child: Text('取消任务')),
        ]),
      if (cloudConnection)
        Wrap(children: [
          TextButton(
              onPressed: () => open(ProgramSection(
                  '同步任务', 'SYNO.CloudSync', 'list_sess',
                  listKey: 'sess', params: {'connection_id': cloudId})),
              child: Text('任务')),
          TextButton(
              onPressed: () => open(ProgramSection(
                  '连接设置', 'SYNO.CloudSync', 'get_connection_setting',
                  params: {'connection_id': cloudId})),
              child: Text('设置')),
          TextButton(
              onPressed: () => open(ProgramSection(
                      '同步日志', 'SYNO.CloudSync', 'get_log',
                      listKey: 'items',
                      params: {
                        'connection_id': cloudId,
                        'offset': 0,
                        'limit': 100,
                        'keyword': '',
                        'date_from': '',
                        'date_to': '',
                        'log_level': -1,
                        'action': -1
                      })),
              child: Text('日志')),
          TextButton(
              onPressed: busy
                  ? null
                  : () => action(
                      '暂停同步',
                      ProgramSection('', 'SYNO.CloudSync', 'pause'),
                      {'connection_id': cloudId}),
              child: Text('暂停')),
          TextButton(
              onPressed: busy
                  ? null
                  : () => action(
                      '恢复同步',
                      ProgramSection('', 'SYNO.CloudSync', 'resume'),
                      {'connection_id': cloudId}),
              child: Text('恢复')),
        ]),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (loading) return Center(child: CircularProgressIndicator());
    final shown = rows
        .where((r) => '${ProgramSection.publicValue(r)}'
            .toLowerCase()
            .contains(query.toLowerCase()))
        .toList();
    return RefreshIndicator(
        onRefresh: load,
        child: ListView(
            physics: AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(16),
            children: [
              if (widget.section.listKey != null)
                TextField(
                    onChanged: (v) => setState(() => query = v),
                    decoration: InputDecoration(
                        prefixIcon: Icon(Icons.search), hintText: '筛选已加载的项目')),
              if (error.isNotEmpty)
                ListTile(
                    title: Text(error),
                    trailing: IconButton(
                        icon: Icon(Icons.refresh), onPressed: () => load())),
              if (error.isEmpty &&
                  widget.section.listKey != null &&
                  rows.isEmpty)
                Padding(padding: EdgeInsets.all(24), child: Text('暂无记录')),
              if (widget.section.listKey == null && data != null)
                NativeProperties(data),
              ...shown.map(row),
              if (more)
                TextButton(
                    onPressed: busy ? null : () => load(next: true),
                    child: Text(busy ? '正在加载…' : '加载更多')),
            ]));
  }
}

/// Nested native rows; session and credential fields are filtered recursively.
class NativeProperties extends StatelessWidget {
  final dynamic value;
  const NativeProperties(this.value);
  static const labels = {
    'name': '名称',
    'version': '版本',
    'status': '状态',
    'state': '状态',
    'path': '路径',
    'size': '大小',
    'total': '总数',
    'enable_http': '启用 HTTP',
    'enable_https': '启用 HTTPS',
    'http_port': 'HTTP 端口',
    'https_port': 'HTTPS 端口',
    'enable_anonymous': '允许匿名访问',
    'last_bkp_time': '上次备份时间',
    'last_bkp_result': '上次备份结果',
    'source': '备份来源',
    'target': '目标',
    'description': '说明',
    'worker_count': '同步线程数',
    'user_name': '用户名',
    'unfinished_files': '未完成文件',
    'share': '共享文件夹',
    'location': '位置',
    'client_ip': '设备地址',
    'client_name': '设备名称',
    'client_version': '客户端版本',
  };
  @override
  Widget build(BuildContext context) {
    final safe = ProgramSection.publicValue(value);
    if (safe is Map)
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: safe.entries.map<Widget>((e) {
            final name = labels['${e.key}'] ?? '${e.key}';
            if (e.value is Map || e.value is List)
              return ExpansionTile(title: Text(name), children: [
                Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: NativeProperties(e.value))
              ]);
            return ListTile(
                title: Text(name),
                subtitle: SelectableText(e.value is bool
                    ? (e.value ? '是' : '否')
                    : '${e.value ?? '—'}'));
          }).toList());
    if (safe is List)
      return Column(children: [
        if (safe.isEmpty) ListTile(title: Text('暂无记录')),
        ...safe.map<Widget>((v) => NativeProperties(v))
      ]);
    return ListTile(title: SelectableText('${safe ?? '—'}'));
  }
}
