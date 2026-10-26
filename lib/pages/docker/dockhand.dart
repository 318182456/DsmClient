import 'package:dsm_client/util/dockhand_client.dart';
import 'package:dsm_client/models/docker_connection.dart';
import 'package:dsm_client/util/function.dart';
import 'package:dsm_client/pages/packages/program_page.dart';
import 'package:flutter/material.dart';

class DockhandProgram extends StatefulWidget {
  final String profile;
  final VoidCallback onChooseBackend;
  const DockhandProgram({this.profile, this.onChooseBackend});
  @override State<DockhandProgram> createState() => _DockhandProgramState();
}
class _DockhandProgramState extends State<DockhandProgram> {
  final address = TextEditingController(), account = TextEditingController(), password = TextEditingController();
  final token = TextEditingController(), otp = TextEditingController();
  DockhandClient client;
  String authMode = 'local', env, resource = 'containers', error = '', search = '';
  bool busy = false, mfa = false;
  List<Map> environments = [];
  dynamic data;
  @override void initState() { super.initState(); loadAddress(); }
  Future<void> loadAddress() async {
    try {
      final value = await Util.getStorage('dockhand_url_${widget.profile}');
      if ((value ?? '').isNotEmpty) {
        if (mounted && address.text.isEmpty) address.text = value;
      } else {
        final details = await Api.dockerDetail('dockhand', 'get');
        final inferred = DockerConnection.dockhandAddress(Util.baseUrl, (details['data'] ?? {})['profile'] as Map ?? {});
        if (mounted && address.text.isEmpty) address.text = inferred;
      }
    } catch (_) {}
  }
  @override void dispose() {
    client?.close(); address.dispose(); account.dispose(); password.dispose(); token.dispose(); otp.dispose(); super.dispose();
  }
  String message(Object e) => e is StateError ? '${e.message}' : e is FormatException ? e.message
    : 'Dockhand 连接失败，请检查服务地址、证书及网络';
  Future<void> connect() async {
    if (busy) return;
    setState(() { busy = true; error = ''; });
    DockhandClient candidate;
    try {
      candidate = DockhandClient(address.text);
      if (authMode == 'local' && (account.text.trim().isEmpty || password.text.isEmpty)) throw StateError('请输入 Dockhand 本地账号和密码');
      if (authMode == 'token' && token.text.trim().isEmpty) throw StateError('请输入 Dockhand API Token');
      await candidate.login(user: authMode == 'local' ? account.text.trim() : '',
        password: password.text, mfa: otp.text.trim(), token: authMode == 'token' ? token.text : '');
      final list = await candidate.environments();
      if (!mounted) { candidate.close(); return; }
      final saved = await Util.getStorage('dockhand_env_${widget.profile}');
      if (!mounted) { candidate.close(); return; }
      setState(() {
        client = candidate; environments = list;
        env = list.isEmpty ? null : (list.any((e) => '${e['id']}' == saved) ? saved : '${list.first['id']}');
        password.clear(); token.clear(); otp.clear();
      });
      try { await Util.setStorage('dockhand_url_${widget.profile}', address.text.trim()); } catch (_) {}
    } on DockhandMfaRequired {
      candidate?.close(); if (mounted) setState(() { mfa = true; error = '请输入 Dockhand 两步验证码后再次连接'; });
    } catch (e) { candidate?.close(); if (mounted) setState(() => error = message(e)); }
    finally { if (mounted) setState(() => busy = false); }
    if (mounted && client != null && env != null) await load();
  }
  Future<void> load() async {
    if (busy || env == null) return;
    setState(() { busy = true; error = ''; data = null; });
    try { final value = await client.resource(resource, env); if (mounted) setState(() => data = value); }
    catch (e) { if (mounted) setState(() => error = message(e)); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> control(Map item, String action) async {
    if (busy) return;
    final title = const {'start': '启动', 'stop': '停止', 'restart': '重启', 'pause': '暂停', 'unpause': '恢复'}[action];
    final yes = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
      title: Text('$title${resource == 'stacks' ? ' Compose 项目' : '容器'}'),
      content: Text('${item['name'] ?? item['id']}\n环境：${environments.firstWhere((e) => '${e['id']}' == env)['name']}'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text('取消')),
        TextButton(onPressed: () => Navigator.pop(dialog, true), child: Text('确认'))]));
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    String actionError;
    try { await client.control('${resource == 'stacks' ? item['name'] : item['id']}', action, env, stack: resource == 'stacks'); }
    catch (e) { actionError = message(e); }
    finally { if (mounted) setState(() => busy = false); }
    if (mounted) await load();
    if (mounted && actionError != null) setState(() => error = actionError);
  }
  Future<void> detail(Map item, String view) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final value = await client.container('${item['id']}', view, env);
      if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
        appBar: AppBar(title: Text('${item['name']} · $view')),
        body: SingleChildScrollView(padding: EdgeInsets.all(16), child: view == 'logs' && value is Map
          ? SelectableText('${value['logs'] ?? ''}') : NativeProperties(value)))));
    } catch (e) { if (mounted) setState(() => error = message(e)); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Dockhand'), actions: [
      if (client != null) IconButton(icon: Icon(Icons.logout), tooltip: '断开 Dockhand', onPressed: busy ? null : () {
        client.close(); setState(() { client = null; data = null; error = ''; });
      }),
      if (widget.onChooseBackend != null) IconButton(icon: Icon(Icons.tune), tooltip: '选择容器管理方式', onPressed: busy ? null : widget.onChooseBackend),
    ]), body: client == null ? ListView(padding: EdgeInsets.all(20), children: [
      Text('连接 Dockhand', style: Theme.of(context).textTheme.headline6),
      Text('使用 Dockhand 自己的地址与账号。仅保存服务地址和环境选择，密码和 Token 只用于当前页面会话。'),
      TextField(controller: address, keyboardType: TextInputType.url,
        decoration: InputDecoration(labelText: 'Dockhand 地址', hintText: 'https://dockhand.example.com')),
      DropdownButtonFormField<String>(value: authMode, items: [
        DropdownMenuItem(value: 'local', child: Text('本地账号')), DropdownMenuItem(value: 'token', child: Text('API Token')),
        DropdownMenuItem(value: 'none', child: Text('服务未启用认证'))], onChanged: busy ? null : (v) => setState(() => authMode = v)),
      if (authMode == 'local') ...[
        TextField(controller: account, decoration: InputDecoration(labelText: 'Dockhand 账号')),
        TextField(controller: password, obscureText: true, autocorrect: false, enableSuggestions: false,
          decoration: InputDecoration(labelText: 'Dockhand 密码')),
        if (mfa) TextField(controller: otp, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: '两步验证码')),
      ],
      if (authMode == 'token') TextField(controller: token, obscureText: true, autocorrect: false, enableSuggestions: false,
        decoration: InputDecoration(labelText: 'Dockhand API Token')),
      if (error.isNotEmpty) Padding(padding: EdgeInsets.all(12), child: Text(error)),
      ElevatedButton(onPressed: busy ? null : connect, child: Text(busy ? '正在连接…' : '连接')),
    ]) : Column(children: [
      if (busy) LinearProgressIndicator(),
      Padding(padding: EdgeInsets.all(16), child: Column(children: [
        DropdownButtonFormField<String>(value: env, decoration: InputDecoration(labelText: 'Docker 环境'),
          items: environments.map((e) => DropdownMenuItem(value: '${e['id']}', child: Text('${e['name']}'))).toList(),
          onChanged: busy ? null : (v) async { setState(() => env = v);
            await Util.setStorage('dockhand_env_${widget.profile}', v); if (mounted) load(); }),
        Row(children: [Expanded(child: DropdownButton<String>(value: resource, isExpanded: true,
          items: const {'containers':'容器','images':'镜像','stacks':'Compose 项目','networks':'网络','volumes':'卷'}.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: busy ? null : (v) { setState(() => resource = v); load(); })),
          IconButton(icon: Icon(Icons.refresh), onPressed: busy || env == null ? null : load)]),
        TextField(onChanged: (v) => setState(() => search = v), decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: '筛选项目')),
      ])),
      if (error.isNotEmpty) Padding(padding: EdgeInsets.all(12), child: Text(error)),
      Expanded(child: RefreshIndicator(onRefresh: load, child: ListView(physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(12), children: [
          if (env == null) ListTile(title: Text('Dockhand 中暂无可访问的 Docker 环境')),
          if (data is List && (data as List).isEmpty) ListTile(title: Text('暂无项目')),
          if (data != null && data is! List) NativeProperties(data),
          if (data is List) ...(data as List).whereType<Map>().where((i) => '$i'.toLowerCase().contains(search.toLowerCase())).map((item) => Card(
            child: Column(children: [ListTile(title: Text('${item['name'] ?? item['Name'] ?? item['RepoTags'] ?? item['Id'] ?? item['id'] ?? '详细信息'}'),
              subtitle: Text('${item['state'] ?? item['status'] ?? item['image'] ?? ''}'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text('详细信息')),
                body: SingleChildScrollView(child: NativeProperties(item)))))),
              if (resource == 'containers') Wrap(children: [for (final view in ['inspect','logs','stats','top'])
                TextButton(onPressed: busy ? null : () => detail(item, view), child: Text(const {'inspect':'配置','logs':'日志','stats':'资源','top':'进程'}[view]))]),
              if (resource == 'containers' || resource == 'stacks') Wrap(children: [
                for (final action in ['start','stop','restart']) TextButton(onPressed: busy ? null : () => control(item, action),
                  child: Text(const {'start':'启动','stop':'停止','restart':'重启'}[action])),
              ]),
            ]))),
        ]))),
    ]));
}
