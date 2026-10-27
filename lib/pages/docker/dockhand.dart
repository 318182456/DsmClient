import 'dart:async';
import 'package:dsm_client/util/dockhand_credentials.dart';
import 'package:dsm_client/widgets/workspace.dart';
import 'package:dsm_client/util/dockhand_client.dart';
import 'package:dsm_client/models/docker_connection.dart';
import 'package:dsm_client/util/function.dart';
import 'package:dsm_client/pages/packages/program_page.dart';
import 'package:flutter/material.dart';
import 'package:dsm_client/widgets/docker_stats.dart';
import 'package:dsm_client/util/service_sessions.dart';
import 'package:dsm_client/util/service_session_pool.dart';
import 'package:dsm_client/util/service_auth_error.dart';

class DockhandProgram extends StatefulWidget {
  final String profile;
  final VoidCallback onChooseBackend;
  final DockhandCredentials credentials;
  final DockhandClient Function(String) clientFactory;
  const DockhandProgram(
      {this.profile,
      this.clientFactory,
      this.onChooseBackend,
      this.credentials = const DockhandCredentials()});
  @override
  State<DockhandProgram> createState() => _DockhandProgramState();
}

class _DockhandProgramState extends State<DockhandProgram>
    with WidgetsBindingObserver {
  final address = TextEditingController(),
      account = TextEditingController(),
      password = TextEditingController();
  final token = TextEditingController(), otp = TextEditingController();
  DockhandClient client;
  ServiceSessionLease<DockhandClient> session;
  String sessionNamespace;
  bool recoveryUsed = false;
  void closeConnection({bool invalidate = false}) {
    if (session != null) {
      if (invalidate)
        session.invalidate();
      else
        session.release();
      session = null;
    } else
      client?.close();
  }

  String authMode = 'local',
      env,
      resource = 'containers',
      error = '',
      search = '';
  bool busy = false, mfa = false, remember = true, credentialsLoading = false;
  int credentialGeneration = 0;
  String initialConnectionUrl;
  Timer credentialTimer;
  Timer statsTimer;
  bool statsLoading = false, foreground = true;
  int statsGeneration = 0;
  Map<String, Map> statistics = {};
  String statsError = '';
  DateTime statsUpdated;
  List<Map> environments = [];
  dynamic data;
  @override
  void initState() {
    super.initState();
    sessionNamespace = ServiceSessions.namespace;
    WidgetsBinding.instance.addObserver(this);
    address.addListener(addressChanged);
    loadAddress();
  }

  Future<void> loadAddress() async {
    try {
      final value = await Util.getStorage('dockhand_url_${widget.profile}');
      if ((value ?? '').isNotEmpty) {
        if (mounted && address.text.isEmpty) {
          initialConnectionUrl = value.trim();
          address.text = value;
        }
      } else {
        final details = await Api.dockerDetail('dockhand', 'get');
        final inferred = DockerConnection.dockhandAddress(
            Util.baseUrl, (details['data'] ?? {})['profile'] as Map ?? {});
        if (mounted && address.text.isEmpty) address.text = inferred;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    statsTimer?.cancel();
    statsGeneration++;
    credentialGeneration++;
    credentialTimer?.cancel();
    address.removeListener(addressChanged);
    closeConnection();
    address.dispose();
    account.dispose();
    password.dispose();
    token.dispose();
    otp.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    scheduleStats();
    if (foreground) loadStatistics();
  }

  void scheduleStats() {
    statsTimer?.cancel();
    if (foreground && client != null && env != null && resource == 'containers')
      statsTimer =
          Timer.periodic(Duration(seconds: 10), (_) => loadStatistics());
  }

  void clearStats() {
    statsGeneration++;
    statsLoading = false;
    statistics = {};
    statsUpdated = null;
    statsError = '';
  }

  Future<void> loadStatistics() async {
    if (!mounted ||
        !foreground ||
        statsLoading ||
        client == null ||
        env == null ||
        resource != 'containers') return;
    final generation = ++statsGeneration;
    final source = client, environment = env;
    setState(() => statsLoading = true);
    bool reconnect = false;
    try {
      final rows = await source.statistics(environment);
      if (mounted &&
          generation == statsGeneration &&
          source == client &&
          environment == env)
        setState(() {
          statistics = {
            for (final row in rows)
              if (row['id'] != null) '${row['id']}': row
          };
          statsError = '';
          statsUpdated = DateTime.now();
        });
    } catch (e) {
      if (e is ServiceAuthException &&
          !recoveryUsed &&
          session != null &&
          mounted &&
          generation == statsGeneration) {
        closeConnection(invalidate: true);
        setState(() {
          client = null;
          clearStats();
        });
        reconnect = true;
        recoveryUsed = true;
      }
      if (mounted && generation == statsGeneration)
        setState(() => statsError = message(e));
    } finally {
      if (mounted && generation == statsGeneration)
        setState(() => statsLoading = false);
    }
    if (reconnect && mounted) await connect(automaticRecovery: true);
  }

  void addressChanged() {
    final generation = ++credentialGeneration;
    credentialTimer?.cancel();
    account.clear();
    password.clear();
    token.clear();
    otp.clear();
    if (!mounted) return;
    setState(() {
      authMode = 'local';
      mfa = false;
      credentialsLoading = true;
    });
    final service = address.text.trim();
    credentialTimer =
        Timer(Duration(milliseconds: initialConnectionUrl == service ? 0 : 350),
            () async {
      Map saved;
      try {
        saved = await widget.credentials.read(widget.profile, service);
      } catch (_) {}
      if (!mounted || generation != credentialGeneration) return;
      final reconnect = saved != null && initialConnectionUrl == service;
      initialConnectionUrl = null;
      setState(() {
        credentialsLoading = false;
        if (saved != null) {
          authMode = saved['mode'];
          account.text = '${saved['account'] ?? ''}';
          password.text = '${saved['password'] ?? ''}';
          token.text = '${saved['token'] ?? ''}';
          remember = true;
        }
      });
      if (reconnect) await connect();
    });
  }

  Future<void> forgetCredentials() async {
    try {
      await widget.credentials.delete(widget.profile, address.text.trim());
      if (mounted)
        setState(() {
          account.clear();
          password.clear();
          token.clear();
          otp.clear();
          remember = false;
          error = '';
        });
    } catch (_) {
      if (mounted) setState(() => error = '无法清除登录信息，请重试');
    }
  }

  String message(Object e) => e is ServiceAuthException
      ? e.message
      : e is StateError
          ? '${e.message}'
          : e is FormatException
              ? e.message
              : 'Dockhand 连接失败，请检查服务地址、证书及网络';
  Future<void> connect({bool automaticRecovery = false}) async {
    if (busy ||
        credentialsLoading ||
        sessionNamespace != ServiceSessions.namespace) return;
    if (!automaticRecovery) recoveryUsed = false;
    setState(() {
      busy = true;
      error = '';
    });
    DockhandClient candidate;
    ServiceSessionLease<DockhandClient> acquired;
    String credentialWarning = '';
    try {
      if (authMode == 'local' &&
          (account.text.trim().isEmpty || password.text.isEmpty))
        throw StateError('请输入 Dockhand 本地账号和密码');
      if (authMode == 'token' && token.text.trim().isEmpty)
        throw StateError('请输入 Dockhand API Token');
      List<Map> list;
      if (remember && authMode != 'none' && widget.clientFactory == null) {
        acquired = await ServiceSessions.dockhand(widget.profile, address.text,
            authMode, account.text.trim(), password.text, token.text.trim(),
            otp: otp.text.trim());
        candidate = acquired.client;
        list = List<Map>.from(acquired.data as List ?? []);
      } else {
        candidate = widget.clientFactory?.call(address.text) ??
            DockhandClient(address.text);
        await candidate.login(
            user: authMode == 'local' ? account.text.trim() : '',
            password: password.text,
            mfa: otp.text.trim(),
            token: authMode == 'token' ? token.text : '');
        list = await candidate.environments();
      }
      if (!mounted || sessionNamespace != ServiceSessions.namespace) {
        if (acquired != null)
          acquired.release();
        else
          candidate.close();
        return;
      }
      String storageWarning = '';
      try {
        if (remember && authMode != 'none') {
          await widget.credentials.save(widget.profile, address.text.trim(), {
            'mode': authMode,
            'account': account.text.trim(),
            'password': password.text,
            'token': token.text.trim(),
          });
        } else {
          await widget.credentials.delete(widget.profile, address.text.trim());
        }
      } catch (_) {
        storageWarning = '已连接，但登录信息保存失败。下次需重新输入。';
      }
      credentialWarning = storageWarning;
      if (!mounted || sessionNamespace != ServiceSessions.namespace) {
        if (acquired != null)
          acquired.release();
        else
          candidate.close();
        return;
      }
      final saved = await Util.getStorage('dockhand_env_${widget.profile}');
      if (!mounted) {
        if (acquired != null)
          acquired.release();
        else
          candidate.close();
        return;
      }
      setState(() {
        client = candidate;
        session = acquired;
        environments = list;
        env = list.isEmpty
            ? null
            : (list.any((e) => '${e['id']}' == saved)
                ? saved
                : '${list.first['id']}');
        otp.clear();
        if (!remember) {
          password.clear();
          token.clear();
        }
        error = storageWarning;
      });
      try {
        await Util.setStorage(
            'dockhand_url_${widget.profile}', address.text.trim());
      } catch (_) {}
    } on DockhandMfaRequired {
      if (acquired != null)
        acquired.invalidate();
      else
        candidate?.close();
      if (mounted)
        setState(() {
          mfa = true;
          error = '请输入 Dockhand 两步验证码后再次连接';
        });
    } catch (e) {
      if (acquired != null)
        acquired.invalidate();
      else
        candidate?.close();
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && client != null && env != null) await load();
    if (mounted && credentialWarning.isNotEmpty)
      setState(() => error = credentialWarning);
  }

  Future<void> load() async {
    if (busy || env == null) return;
    setState(() {
      busy = true;
      error = '';
      data = null;
    });
    bool reconnect = false;
    try {
      final value = await client.resource(resource, env);
      if (mounted) setState(() => data = value);
    } catch (e) {
      if (e is ServiceAuthException &&
          session != null &&
          mounted &&
          !recoveryUsed) {
        closeConnection(invalidate: true);
        setState(() {
          client = null;
          clearStats();
        });
        reconnect = true;
        recoveryUsed = true;
      }
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (reconnect && mounted) {
      await connect(automaticRecovery: true);
      return;
    }
    if (mounted && client != null) {
      scheduleStats();
      await loadStatistics();
    }
  }

  Future<void> control(Map item, String action) async {
    if (busy) return;
    final title = const {
      'start': '启动',
      'stop': '停止',
      'restart': '重启',
      'pause': '暂停',
      'unpause': '恢复'
    }[action];
    final yes = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: Text(
                    '$title${resource == 'stacks' ? ' Compose 项目' : '容器'}'),
                content: Text(
                    '${item['name'] ?? item['id']}\n环境：${environments.firstWhere((e) => '${e['id']}' == env)['name']}'),
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
    String actionError;
    try {
      await client.control(
          '${resource == 'stacks' ? item['name'] : item['id']}', action, env,
          stack: resource == 'stacks');
    } catch (e) {
      actionError = message(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) await load();
    if (mounted && actionError != null) setState(() => error = actionError);
  }

  Future<void> detail(Map item, String view) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final value = await client.container('${item['id']}', view, env);
      if (mounted)
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => Scaffold(
                    appBar: AppBar(title: Text('${item['name']} · $view')),
                    body: SingleChildScrollView(
                        padding: EdgeInsets.all(16),
                        child: view == 'logs' && value is Map
                            ? SelectableText('${value['logs'] ?? ''}')
                            : view == 'stats' && value is Map
                                ? Card(
                                    child: Padding(
                                        padding: EdgeInsets.all(18),
                                        child: DockerStatsPanel(value)))
                                : NativeProperties(value)))));
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  static const resources = {
    'containers': '容器',
    'images': '镜像',
    'stacks': 'Compose 项目',
    'networks': '网络',
    'volumes': '卷'
  };
  static const resourceIcons = {
    'containers': Icons.view_in_ar_outlined,
    'images': Icons.layers_outlined,
    'stacks': Icons.account_tree_outlined,
    'networks': Icons.lan_outlined,
    'volumes': Icons.storage_outlined
  };
  Widget errorNotice() => Container(
      margin: EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline,
            color: Theme.of(context).colorScheme.onErrorContainer),
        SizedBox(width: 10),
        Expanded(
            child: Text(error,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer))),
      ]));
  Widget connectionForm() =>
      ListView(padding: EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
        WorkspaceHeader(
            padding: EdgeInsets.fromLTRB(0, 16, 0, 20),
            title: '连接你的容器环境',
            subtitle: '使用 Dockhand 管理 NAS 上的服务。'),
        Card(
            child: Padding(
                padding: EdgeInsets.all(18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('服务地址',
                          style: Theme.of(context).textTheme.subtitle1),
                      SizedBox(height: 12),
                      TextField(
                          controller: address,
                          enabled: !busy,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: InputDecoration(
                              labelText: 'Dockhand 地址',
                              hintText: 'https://dockhand.example.com',
                              prefixIcon: Icon(Icons.link))),
                      SizedBox(height: 20),
                      Text('登录方式',
                          style: Theme.of(context).textTheme.subtitle1),
                      SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                          value: authMode,
                          isExpanded: true,
                          items: [
                            DropdownMenuItem(
                                value: 'local', child: Text('账号与密码')),
                            DropdownMenuItem(
                                value: 'token', child: Text('API Token')),
                            DropdownMenuItem(
                                value: 'none', child: Text('服务未启用认证'))
                          ],
                          onChanged: busy || credentialsLoading
                              ? null
                              : (v) => setState(() {
                                    authMode = v;
                                    mfa = false;
                                  })),
                      SizedBox(height: 16),
                      if (authMode == 'local') ...[
                        TextField(
                            controller: account,
                            enabled: !busy && !credentialsLoading,
                            autofillHints: [AutofillHints.username],
                            decoration: InputDecoration(
                                labelText: 'Dockhand 账号',
                                prefixIcon: Icon(Icons.person_outline))),
                        SizedBox(height: 14),
                        TextField(
                            controller: password,
                            enabled: !busy && !credentialsLoading,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: [AutofillHints.password],
                            decoration: InputDecoration(
                                labelText: '密码',
                                prefixIcon: Icon(Icons.lock_outline))),
                        if (mfa) ...[
                          SizedBox(height: 14),
                          TextField(
                              controller: otp,
                              enabled: !busy,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                  labelText: '两步验证码',
                                  prefixIcon:
                                      Icon(Icons.verified_user_outlined)))
                        ],
                      ],
                      if (authMode == 'token')
                        TextField(
                            controller: token,
                            enabled: !busy && !credentialsLoading,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                                labelText: 'API Token',
                                prefixIcon: Icon(Icons.key_outlined))),
                      if (authMode != 'none')
                        SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: Text('记住登录信息'),
                            subtitle: Text('加密保存在此设备，验证码不会保存'),
                            value: remember,
                            onChanged: busy || credentialsLoading
                                ? null
                                : (v) async {
                                    if (!v) {
                                      try {
                                        await widget.credentials.delete(
                                            widget.profile,
                                            address.text.trim());
                                        if (mounted)
                                          setState(() => remember = false);
                                      } catch (_) {
                                        if (mounted)
                                          setState(
                                              () => error = '无法清除已保存登录信息，请重试');
                                      }
                                    } else {
                                      setState(() => remember = true);
                                    }
                                  }),
                      SizedBox(height: 8),
                      ElevatedButton.icon(
                          onPressed:
                              busy || credentialsLoading ? null : connect,
                          icon: busy || credentialsLoading
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : Icon(Icons.arrow_forward),
                          label: Text(busy
                              ? '正在连接…'
                              : credentialsLoading
                                  ? '正在读取登录信息…'
                                  : '连接 Dockhand')),
                      TextButton(
                          onPressed: busy || credentialsLoading
                              ? null
                              : forgetCredentials,
                          child: Text('清除已保存登录信息')),
                    ]))),
        if (error.isNotEmpty) errorNotice(),
        Padding(
            padding: EdgeInsets.all(12),
            child: Text('登录信息按 NAS 和服务地址分别保存。Dockhand 使用自己的账号，与 DSM 登录独立。',
                style: Theme.of(context).textTheme.caption)),
      ]);
  Widget resourceCard(Map item) {
    final theme = Theme.of(context);
    final state = '${item['state'] ?? item['status'] ?? ''}';
    final running = state.toLowerCase() == 'running';
    final title =
        '${item['name'] ?? item['Name'] ?? item['RepoTags'] ?? item['Id'] ?? item['id'] ?? '详细信息'}';
    final statusColor = running
        ? (theme.brightness == Brightness.dark
            ? Color(0xff7fdbb3)
            : Color(0xff126a48))
        : theme.colorScheme.onSurfaceVariant;
    return Card(
        child: Padding(
            padding: EdgeInsets.all(4),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                      leading: Container(
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12)),
                          child: Icon(resourceIcons[resource],
                              color: theme.colorScheme.onPrimaryContainer)),
                      title: Text(title,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (state.isNotEmpty)
                              Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Text(running ? '● 运行中' : state,
                                      style: TextStyle(
                                          color: statusColor, fontSize: 13))),
                            if (item['image'] != null)
                              Text('${item['image']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.caption),
                          ]),
                      trailing: Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => Scaffold(
                                  appBar: AppBar(title: Text(title)),
                                  body: SingleChildScrollView(
                                      padding: EdgeInsets.all(16),
                                      child: Card(
                                          child: NativeProperties(item))))))),
                  if (resource == 'containers')
                    Padding(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: statistics['${item['id']}'] != null
                            ? DockerStatsPanel(statistics['${item['id']}'],
                                compact: true)
                            : Text(
                                running
                                    ? (statsLoading ? '正在采样资源…' : '暂无资源采样')
                                    : '容器未运行',
                                style: theme.textTheme.caption)),
                  if (resource == 'containers')
                    Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Wrap(children: [
                          for (final view in [
                            'inspect',
                            'logs',
                            'stats',
                            'top'
                          ])
                            TextButton(
                                onPressed:
                                    busy ? null : () => detail(item, view),
                                child: Text(const {
                                  'inspect': '配置',
                                  'logs': '日志',
                                  'stats': '资源',
                                  'top': '进程'
                                }[view])),
                        ])),
                  if (resource == 'containers' || resource == 'stacks') ...[
                    Divider(height: 1, indent: 12, endIndent: 12),
                    Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Wrap(children: [
                          for (final action in ['start', 'stop', 'restart'])
                            TextButton.icon(
                                onPressed:
                                    busy ? null : () => control(item, action),
                                icon: Icon(
                                    const {
                                      'start': Icons.play_arrow_rounded,
                                      'stop': Icons.stop_rounded,
                                      'restart': Icons.restart_alt
                                    }[action],
                                    size: 18),
                                label: Text(const {
                                  'start': '启动',
                                  'stop': '停止',
                                  'restart': '重启'
                                }[action])),
                        ])),
                  ],
                ])));
  }

  Widget dashboard() {
    final visible = data is List
        ? (data as List)
            .whereType<Map>()
            .where((i) => '$i'.toLowerCase().contains(search.toLowerCase()))
            .toList()
        : <Map>[];
    return Column(children: [
      if (busy) LinearProgressIndicator(minHeight: 2),
      Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: DropdownButtonFormField<String>(
              value: env,
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: '当前 Docker 环境',
                  prefixIcon: Icon(Icons.dns_outlined)),
              items: environments
                  .map((e) => DropdownMenuItem(
                      value: '${e['id']}',
                      child: Text('${e['name']}',
                          overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: busy
                  ? null
                  : (v) async {
                      setState(() {
                        env = v;
                        clearStats();
                      });
                      await Util.setStorage(
                          'dockhand_env_${widget.profile}', v);
                      if (mounted) load();
                    })),
      SizedBox(
          height: 48,
          child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final entry in resources.entries)
                  Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                          label: Text(entry.value),
                          selectedColor:
                              Theme.of(context).colorScheme.primaryContainer,
                          labelStyle: TextStyle(
                              color: resource == entry.key
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                          selected: resource == entry.key,
                          onSelected: busy
                              ? null
                              : (_) {
                                  setState(() => resource = entry.key);
                                  load();
                                })),
              ])),
      Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: TextField(
              onChanged: (v) => setState(() => search = v),
              decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索${resources[resource]}',
                  suffixIcon: IconButton(
                      tooltip: '刷新',
                      icon: Icon(Icons.refresh),
                      onPressed: busy || env == null ? null : load)))),
      if (error.isNotEmpty) errorNotice(),
      Expanded(
          child: RefreshIndicator(
              onRefresh: load,
              child: ListView(
                  physics: AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    if (resource == 'containers' && env != null)
                      Card(
                          child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(children: [
                                      Expanded(
                                          child: Text('容器资源合计',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .subtitle1)),
                                      IconButton(
                                          tooltip: '刷新资源',
                                          icon: Icon(Icons.refresh),
                                          onPressed: statsLoading
                                              ? null
                                              : loadStatistics)
                                    ]),
                                    if (statistics.isNotEmpty)
                                      DockerStatsPanel(DockerStatsPanel.totals(
                                          statistics.values))
                                    else
                                      Text(
                                          statsLoading
                                              ? '正在采样资源…'
                                              : '暂无运行中的容器采样',
                                          style: Theme.of(context)
                                              .textTheme
                                              .caption),
                                    SizedBox(height: 12),
                                    Text(
                                        '前台每 10 秒刷新 · 网络和磁盘 I/O 为累计量${statsUpdated == null ? '' : ' · ${statsUpdated.hour.toString().padLeft(2, '0')}:${statsUpdated.minute.toString().padLeft(2, '0')}:${statsUpdated.second.toString().padLeft(2, '0')} 更新'}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .caption),
                                    if (statsError.isNotEmpty)
                                      Text('资源采样失败，当前显示上次结果：$statsError',
                                          style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error)),
                                  ]))),
                    if (env == null)
                      WorkspaceEmpty('还没有 Docker 环境',
                          detail: '在 Dockhand 中添加可访问的 Docker 环境后刷新。'),
                    if (env != null &&
                        !busy &&
                        error.isEmpty &&
                        visible.isEmpty)
                      WorkspaceEmpty(
                          search.isEmpty
                              ? '暂无${resources[resource]}'
                              : '没有匹配的项目',
                          icon: resourceIcons[resource]),
                    if (data != null && data is! List)
                      Card(child: NativeProperties(data)),
                    ...visible.map(resourceCard),
                  ]))),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('Dockhand'), actions: [
        if (client != null)
          IconButton(
              icon: Icon(Icons.logout),
              tooltip: '断开 Dockhand',
              onPressed: busy
                  ? null
                  : () {
                      statsTimer?.cancel();
                      closeConnection(invalidate: true);
                      setState(() {
                        clearStats();
                        client = null;
                        data = null;
                        error = '';
                      });
                      if (remember) addressChanged();
                    }),
        if (widget.onChooseBackend != null)
          IconButton(
              icon: Icon(Icons.tune),
              tooltip: '选择容器管理方式',
              onPressed: busy ? null : widget.onChooseBackend),
      ]),
      body: SafeArea(
          top: false, child: client == null ? connectionForm() : dashboard()));
}
