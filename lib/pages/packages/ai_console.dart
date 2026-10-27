import 'package:flutter/material.dart';
import 'package:dsm_client/util/drive_admin_api.dart';
import 'package:dsm_client/util/ai_console_api.dart';
import 'package:dsm_client/widgets/workspace.dart';
import 'package:dsm_client/widgets/adaptive_tab_bar.dart';
import 'drive_console.dart';
import 'program_page.dart';

class AiConsolePage extends StatefulWidget {
  final DriveAdminApi api;
  const AiConsolePage(this.api);
  @override
  State<AiConsolePage> createState() => _AiConsoleState();
}

class _AiConsoleState extends State<AiConsolePage> {
  AiConsoleApi api;
  bool busy = false;
  String error = '';
  List<Map> providers = [], policies = [];
  @override
  void initState() {
    super.initState();
    api = AiConsoleApi(widget.api);
    load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final data = await Future.wait([api.providers(), api.policies()]);
      if (mounted)
        setState(() {
          providers = data[0];
          policies = data[1];
          error = '';
        });
    } catch (e) {
      if (mounted) setState(() => error = driveError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> providerAction(Map provider, String action) async {
    final id = provider['id'];
    if (busy || id is! int) return;
    String name;
    if (action == 'rename') {
      name = await askDriveText(context, '重命名 API 集成', '集成名称',
          initial: '${provider['name'] ?? ''}');
      if (name == null || !mounted) return;
    }
    if (!await confirmDrive(
            context,
            action == 'rename' ? '重命名集成' : '删除 API 集成',
            action == 'rename'
                ? '将此集成重命名为“$name”？'
                : '删除“${provider['name']}”后，使用此集成的应用可能无法继续调用 AI 服务。是否继续？') ||
        !mounted) return;
    setState(() => busy = true);
    String failure;
    try {
      if (action == 'rename')
        await api.rename(id, name);
      else
        await api.remove(id);
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

  Future<void> policy(Map row) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => AiPolicyEditor(api, row, providers)));
    if (mounted) load();
  }

  static String appName(dynamic ns) =>
      const {
        'Spreadsheet': 'Synology Office',
        'MailClient': '邮件服务',
        'AIConsole': 'AI Console'
      }['$ns'] ??
      '$ns';
  Widget page(List<Widget> children) =>
      ListView(padding: EdgeInsets.all(16), children: children);
  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: 3,
      child: Scaffold(
          appBar: AppBar(
              title: Text('AI 助理'),
              actions: [
                IconButton(
                    tooltip: '刷新 AI Console',
                    icon: Icon(Icons.refresh),
                    onPressed: busy ? null : load)
              ],
              bottom: AdaptiveTabBar(tabs: [
                Tab(text: 'API 集成'),
                Tab(text: '应用策略'),
                Tab(text: '请求日志')
              ])),
          body: Column(children: [
            if (busy) LinearProgressIndicator(minHeight: 2),
            if (error.isNotEmpty)
              Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(error,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            Expanded(
                child: TabBarView(children: [
              page([
                Text('当前 NAS 已配置的 AI 服务',
                    style: Theme.of(context).textTheme.titleLarge),
                SizedBox(height: 12),
                if (providers.isEmpty && !busy && error.isEmpty)
                  WorkspaceEmpty('尚未配置 API 集成',
                      detail: '请先在 NAS 的 AI Console 配置服务商及密钥。'),
                for (final p in providers)
                  Card(
                      child: ListTile(
                          title: Text('${p['name'] ?? 'AI 服务'}'),
                          subtitle: Text(
                              '${p['chat_completion_model'] ?? p['type'] ?? ''}'),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => Scaffold(
                                      appBar:
                                          AppBar(title: Text('${p['name']}')),
                                      body: SingleChildScrollView(
                                          padding: EdgeInsets.all(16),
                                          child: NativeProperties(p,
                                              contextName: 'ai'))))),
                          trailing: PopupMenuButton<String>(
                              tooltip: '集成操作',
                              enabled: !busy,
                              onSelected: (v) => providerAction(p, v),
                              itemBuilder: (_) => [
                                    PopupMenuItem(
                                        value: 'rename', child: Text('重命名')),
                                    PopupMenuItem(
                                        value: 'delete', child: Text('删除'))
                                  ]))),
              ]),
              page([
                if (policies.isEmpty && !busy && error.isEmpty)
                  WorkspaceEmpty('暂无应用策略'),
                for (final p in policies)
                  Card(
                      child: ListTile(
                          title: Text(appName(p['ns'])),
                          subtitle: Text(const {
                                0: '已停用',
                                1: '所有用户可用',
                                2: '使用已配置的例外名单'
                              }[p['enable_policy']] ??
                              '未知策略'),
                          trailing: Icon(Icons.tune),
                          onTap: busy ? null : () => policy(p))),
              ]),
              AiLogsPage(api),
            ]))
          ])));
}

class AiPolicyEditor extends StatefulWidget {
  final AiConsoleApi api;
  final Map policy;
  final List<Map> providers;
  const AiPolicyEditor(this.api, this.policy, this.providers);
  @override
  State<AiPolicyEditor> createState() => _AiPolicyState();
}

class _AiPolicyState extends State<AiPolicyEditor> {
  int enabled, provider;
  bool busy = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    enabled = widget.policy['enable_policy'] as int ?? 0;
    provider = widget.policy['provider_id'] as int;
  }

  Future<void> save() async {
    if (busy) return;
    if (!await confirmDrive(context, '保存 AI 应用策略',
            '将修改此应用使用的 AI 集成与用户访问范围。启用后，应用可能向所选服务商发送用户请求并产生服务商费用。是否继续？') ||
        !mounted) return;
    setState(() => busy = true);
    try {
      await widget.api.policy('${widget.policy['ns']}', enabled, provider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = driveError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('AI 应用策略')),
      body: ListView(padding: EdgeInsets.all(20), children: [
        Text('${widget.policy['ns']}',
            style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height: 20),
        DropdownButtonFormField<int>(
            value: const {0, 1, 2}.contains(enabled) ? enabled : 0,
            decoration: InputDecoration(labelText: '可使用的用户范围'),
            items: [
              DropdownMenuItem(value: 0, child: Text('停用')),
              DropdownMenuItem(value: 1, child: Text('所有用户')),
              if (widget.policy['enable_policy'] == 2)
                DropdownMenuItem(value: 2, child: Text('沿用已配置的例外名单'))
            ],
            onChanged: busy ? null : (v) => setState(() => enabled = v)),
        SizedBox(height: 20),
        DropdownButtonFormField<int>(
            value: widget.providers.any((p) => p['id'] == provider)
                ? provider
                : null,
            decoration: InputDecoration(labelText: 'API 集成'),
            isExpanded: true,
            items: [
              for (final p in widget.providers)
                if (p['id'] is int)
                  DropdownMenuItem(
                      value: p['id'] as int,
                      child: Text('${p['name']}',
                          maxLines: 1, overflow: TextOverflow.ellipsis))
            ],
            onChanged: busy ? null : (v) => setState(() => provider = v)),
        SizedBox(height: 20),
        if (widget.policy['enable_policy'] == 2)
          ExpansionTile(
              title: Text('当前访问范围详情'),
              children: [NativeProperties(widget.policy, contextName: 'ai')]),
        if (error.isNotEmpty)
          Text(error,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ElevatedButton(onPressed: busy ? null : save, child: Text('保存策略')),
      ]));
}

class AiLogsPage extends StatefulWidget {
  final AiConsoleApi api;
  const AiLogsPage(this.api);
  @override
  State<AiLogsPage> createState() => _AiLogsState();
}

class _AiLogsState extends State<AiLogsPage> {
  List<Map> rows = [];
  bool busy = false, more = false;
  String error = '', query = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool next = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final data =
          await widget.api.logs(offset: next ? rows.length : 0, query: query);
      if (mounted)
        setState(() {
          rows = next ? [...rows, ...data] : data;
          more = data.length == 100;
          error = '';
        });
    } catch (e) {
      if (mounted) setState(() => error = driveError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> settings() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => AiLogSettings(widget.api)));
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        if (busy) LinearProgressIndicator(minHeight: 2),
        Padding(
            padding: EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                  child: TextField(
                      onChanged: (v) => query = v,
                      onSubmitted: (_) => load(),
                      decoration: InputDecoration(
                          labelText: '搜索 AI 请求日志',
                          suffixIcon: IconButton(
                              tooltip: '搜索 AI 日志',
                              icon: Icon(Icons.search),
                              onPressed: busy ? null : () => load())))),
              IconButton(
                  tooltip: '日志保留设置',
                  icon: Icon(Icons.settings_outlined),
                  onPressed: settings)
            ])),
        Expanded(
            child: RefreshIndicator(
                onRefresh: () => load(),
                child: ListView(
                    padding: EdgeInsets.all(16),
                    physics: AlwaysScrollableScrollPhysics(),
                    children: [
                      if (error.isNotEmpty)
                        Text(error,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      if (rows.isEmpty && !busy && error.isEmpty)
                        WorkspaceEmpty('暂无 AI 请求日志'),
                      for (final row in rows)
                        Card(
                            child: ListTile(
                                title: Text(
                                    '${row['model'] ?? row['action'] ?? 'AI 请求'}'),
                                subtitle: Text(
                                    '${row['username'] ?? ''} · ${row['created_at'] ?? ''}'),
                                onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => Scaffold(
                                            appBar:
                                                AppBar(title: Text('AI 请求详情')),
                                            body: SingleChildScrollView(
                                                padding: EdgeInsets.all(16),
                                                child: NativeProperties(row,
                                                    contextName: 'ai'))))))),
                      if (more)
                        TextButton(
                            onPressed: busy ? null : () => load(next: true),
                            child: Text('加载更多')),
                    ]))),
      ]);
}

class AiLogSettings extends StatefulWidget {
  final AiConsoleApi api;
  const AiLogSettings(this.api);
  @override
  State<AiLogSettings> createState() => _AiLogSettingsState();
}

class _AiLogSettingsState extends State<AiLogSettings> {
  bool busy = false, loaded = false, saveContent = false;
  String error = '';
  final days = TextEditingController(), size = TextEditingController();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    days.dispose();
    size.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final data = await widget.api.logSettings();
      if (mounted)
        setState(() {
          days.text = '${data['retention_days'] ?? ''}';
          size.text = '${data['max_size'] ?? ''}';
          saveContent = data['save_content_output'] == true;
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
    if (busy || !loaded) return;
    if (!await confirmDrive(context, '保存 AI 日志设置',
            '缩短保留期限或减少数量可能清理已有日志。记录输出内容会将 AI 回复保存在 NAS 日志中。是否继续？') ||
        !mounted) return;
    setState(() => busy = true);
    try {
      int optional(TextEditingController c) {
        if (c.text.trim().isEmpty) return null;
        final v = int.tryParse(c.text);
        if (v == null) throw FormatException('请输入整数或留空表示不限');
        return v;
      }

      await widget.api.saveLogSettings({
        'retention_days': optional(days),
        'max_size': optional(size),
        'save_content_output': saveContent
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = driveError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('AI 日志保留设置')),
      body: ListView(padding: EdgeInsets.all(20), children: [
        if (busy) LinearProgressIndicator(minHeight: 2),
        TextField(
            controller: days,
            enabled: !busy,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: '保留天数（1 至 9999，留空不限）')),
        SizedBox(height: 20),
        TextField(
            controller: size,
            enabled: !busy,
            keyboardType: TextInputType.number,
            decoration:
                InputDecoration(labelText: '最多记录数（1000 至 10000000，留空不限）')),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('保存 AI 输出内容'),
            value: saveContent,
            onChanged: busy ? null : (v) => setState(() => saveContent = v)),
        if (error.isNotEmpty)
          Text(error,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ElevatedButton(
            onPressed: busy || !loaded ? null : save, child: Text('保存设置'))
      ]));
}
