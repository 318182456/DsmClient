import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dsm_client/models/torrent_presentation.dart';
import 'package:dsm_client/util/dsm_compatibility.dart';
import 'package:dsm_client/util/function.dart';
import 'package:dsm_client/util/service_credentials.dart';
import 'package:dsm_client/util/torrent_client.dart';
import 'package:dsm_client/widgets/workspace.dart';
import 'package:dsm_client/pages/docker/detail.dart';
import 'torrent_detail.dart';

class TorrentProgram extends StatefulWidget {
  final String name;
  final bool transmission;
  final TorrentClient Function(String, bool) clientFactory;
  const TorrentProgram(this.name,
      {this.transmission = false, this.clientFactory});
  @override
  State<TorrentProgram> createState() => _TorrentProgramState();
}

class _TorrentProgramState extends State<TorrentProgram>
    with WidgetsBindingObserver {
  final address = TextEditingController(),
      account = TextEditingController(),
      password = TextEditingController();
  TorrentClient client;
  List<Map> tasks = [];
  final selected = <String>{};
  bool busy = false,
      remember = true,
      restoring = false,
      automatic = true,
      foreground = true;
  String error = '', query = '', filter = 'all', sort = 'added';
  Timer refreshTimer, restoreTimer;
  int restoreGeneration = 0;
  String get backend => widget.transmission ? 'Transmission' : 'qBittorrent';
  String get profile =>
      '${DsmCompatibility.connectionKey(Util.baseUrl)}|${widget.name}';
  String get storageKey => 'torrent_url_${widget.transmission}_$profile';
  ServiceCredentials get vault => ServiceCredentials(
      scope: widget.transmission ? 'transmission' : 'qbittorrent');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    address.addListener(addressChanged);
    loadAddress();
  }

  Future<void> loadAddress() async {
    try {
      final saved = await Util.getStorage(storageKey);
      if (mounted && address.text.isEmpty && (saved ?? '').isNotEmpty)
        address.text = saved;
    } catch (_) {}
  }

  void addressChanged() {
    final generation = ++restoreGeneration;
    restoreTimer?.cancel();
    account.clear();
    password.clear();
    if (!mounted) return;
    setState(() => restoring = true);
    final url = address.text.trim();
    restoreTimer = Timer(Duration(milliseconds: 350), () async {
      Map record;
      try {
        record = await vault.read(profile, url);
      } catch (_) {}
      if (!mounted || generation != restoreGeneration) return;
      setState(() {
        restoring = false;
        if (record != null) {
          account.text = '${record['account'] ?? ''}';
          password.text = '${record['password'] ?? ''}';
          remember = true;
        }
      });
    });
  }

  void schedule() {
    refreshTimer?.cancel();
    if (automatic && foreground && client != null)
      refreshTimer = Timer.periodic(Duration(seconds: 5), (_) {
        if (mounted && !busy) refresh();
      });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    schedule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    refreshTimer?.cancel();
    restoreTimer?.cancel();
    restoreGeneration++;
    client?.close();
    address.removeListener(addressChanged);
    address.dispose();
    account.dispose();
    password.dispose();
    super.dispose();
  }

  String message(Object e) => e is FormatException
      ? e.message
      : e is HttpException
          ? e.message
          : e is StateError
              ? '${e.message}'
              : '连接失败，请检查程序地址、证书和网络';
  Future<void> connect() async {
    if (busy || restoring) return;
    setState(() {
      busy = true;
      error = '';
    });
    TorrentClient candidate;
    try {
      candidate =
          widget.clientFactory?.call(address.text, widget.transmission) ??
              TorrentClient(address.text, transmission: widget.transmission);
      await candidate.login(account.text.trim(), password.text);
      final list = await candidate.list();
      if (!mounted) {
        candidate.close();
        return;
      }
      String warning = '';
      try {
        await Util.setStorage(storageKey, address.text.trim());
        if (remember)
          await vault.save(profile, address.text, {
            'mode': 'local',
            'account': account.text.trim(),
            'password': password.text
          });
        else
          await vault.delete(profile, address.text);
      } catch (_) {
        warning = '已连接，但登录信息保存失败，下次需重新输入。';
      }
      if (!mounted) {
        candidate.close();
        return;
      }
      setState(() {
        client = candidate;
        tasks = list;
        error = warning;
        if (!remember) password.clear();
      });
      schedule();
    } catch (e) {
      candidate?.close();
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() async {
    if (busy || client == null) return;
    setState(() => busy = true);
    try {
      final rows = await client.list();
      if (mounted)
        setState(() {
          tasks = rows;
          error = '';
          selected.removeWhere((id) => !rows.any((t) => '${t['id']}' == id));
        });
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> forget() async {
    try {
      await vault.delete(profile, address.text);
      if (mounted)
        setState(() {
          account.clear();
          password.clear();
          remember = false;
        });
    } catch (_) {
      if (mounted) setState(() => error = '清除登录信息失败，请重试');
    }
  }

  static const actions = {
    'start': '开始',
    'stop': '暂停',
    'force': '强制开始',
    'verify': '重新校验',
    'reannounce': '更新 Tracker',
    'remove': '移除任务，保留文件',
    'remove-data': '移除并删除文件'
  };
  Future<void> control(String action, List<Map> rows) async {
    if (busy || rows.isEmpty) return;
    final yes = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: Text(actions[action]),
                content: Text(
                    '${rows.length == 1 ? rows.first['name'] : '已选 ${rows.length} 个任务'}${action == 'remove-data' ? '\n将永久删除服务器上已下载的文件。' : action == 'remove' ? '\n已下载的文件将保留。' : ''}'),
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
    String failure;
    try {
      await client.controlMany(action, rows.map((t) => t['id']).toList());
      if (mounted) setState(() => selected.clear());
    } catch (e) {
      failure = message(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) await refresh();
    if (mounted && failure != null) setState(() => error = failure);
  }

  Future<void> addLink() async {
    final text = TextEditingController();
    final value = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: Text('添加下载链接'),
                content: TextField(
                    controller: text,
                    maxLines: 3,
                    decoration: InputDecoration(hintText: '磁力链接或种子下载地址')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog),
                      child: Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, text.text.trim()),
                      child: Text('添加'))
                ]));
    Future.delayed(Duration(milliseconds: 400), text.dispose);
    if (!mounted || value == null || value.isEmpty) return;
    await mutate(() => client.add(value));
  }

  Future<void> addFile() async {
    final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['torrent'], withData: true);
    if (!mounted || picked == null) return;
    final file = picked.files.single;
    if (file.size > 8 * 1024 * 1024) {
      setState(() => error = '种子文件需小于 8 MB');
      return;
    }
    try {
      final bytes = file.bytes ?? await File(file.path).readAsBytes();
      if (mounted) await mutate(() => client.addFile(bytes));
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    }
  }

  Future<void> mutate(Future<void> Function() operation) async {
    if (busy) return;
    setState(() => busy = true);
    String failure;
    try {
      await operation();
    } catch (e) {
      failure = message(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) await refresh();
    if (mounted && failure != null) setState(() => error = failure);
  }

  Future<void> add() async {
    final mode = await showModalBottomSheet<String>(
        context: context,
        builder: (sheet) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: Icon(Icons.link),
                  title: Text('磁力链接或网址'),
                  onTap: () => Navigator.pop(sheet, 'link')),
              ListTile(
                  leading: Icon(Icons.insert_drive_file_outlined),
                  title: Text('本地 .torrent 文件'),
                  onTap: () => Navigator.pop(sheet, 'file'))
            ])));
    if (!mounted) return;
    if (mode == 'link') await addLink();
    if (mode == 'file') await addFile();
  }

  Widget notice() => Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Text(error,
          style: TextStyle(color: Theme.of(context).colorScheme.error)));
  Widget connection() => ListView(padding: EdgeInsets.all(20), children: [
        WorkspaceHeader(
            padding: EdgeInsets.fromLTRB(0, 12, 0, 20),
            title: '连接 $backend',
            subtitle: '管理 NAS 上的下载任务。'),
        Card(
            child: Padding(
                padding: EdgeInsets.all(18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                          controller: address,
                          enabled: !busy,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: InputDecoration(
                              labelText: '服务地址',
                              hintText: widget.transmission
                                  ? 'https://example.com/transmission/rpc'
                                  : 'https://example.com/qbittorrent',
                              prefixIcon: Icon(Icons.link))),
                      SizedBox(height: 16),
                      TextField(
                          controller: account,
                          enabled: !busy && !restoring,
                          autocorrect: false,
                          decoration: InputDecoration(
                              labelText: '程序账号',
                              prefixIcon: Icon(Icons.person_outline))),
                      SizedBox(height: 16),
                      TextField(
                          controller: password,
                          enabled: !busy && !restoring,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                              labelText: '程序密码',
                              prefixIcon: Icon(Icons.lock_outline))),
                      SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text('记住登录信息'),
                          subtitle: Text('加密保存在此设备',
                              style: Theme.of(context).textTheme.caption),
                          value: remember,
                          onChanged: busy || restoring
                              ? null
                              : (v) async {
                                  if (!v) {
                                    try {
                                      await vault.delete(profile, address.text);
                                    } catch (_) {
                                      if (mounted)
                                        setState(() => error = '清除登录信息失败');
                                      return;
                                    }
                                  }
                                  if (mounted) setState(() => remember = v);
                                }),
                      if (error.isNotEmpty) notice(),
                      ElevatedButton(
                          onPressed: busy || restoring ? null : connect,
                          child: Text(busy
                              ? '正在连接…'
                              : restoring
                                  ? '正在读取登录信息…'
                                  : '连接')),
                      TextButton(
                          onPressed: busy || restoring ? null : forget,
                          child: Text('清除已保存登录信息')),
                    ]))),
        Padding(
            padding: EdgeInsets.all(12),
            child: Text('使用下载程序自己的账号，与 DSM 登录独立。未启用认证的服务可留空账号和密码。',
                style: Theme.of(context).textTheme.caption)),
      ]);
  @override
  Widget build(BuildContext context) {
    final shown = TorrentPresentation.select(tasks,
        filter: filter,
        query: query,
        sort: sort,
        transmission: widget.transmission);
    final picked = tasks.where((t) => selected.contains('${t['id']}')).toList();
    return Scaffold(
        appBar: AppBar(
            title: Text(selected.isEmpty ? backend : '已选 ${selected.length} 项',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              if (selected.isNotEmpty) ...[
                IconButton(
                    tooltip: '全选当前结果',
                    icon: Icon(Icons.select_all),
                    onPressed: () => setState(
                        () => selected.addAll(shown.map((t) => '${t['id']}')))),
                PopupMenuButton<String>(
                    enabled: !busy,
                    onSelected: (action) => control(action, picked),
                    itemBuilder: (_) => actions.entries
                        .map((e) =>
                            PopupMenuItem(value: e.key, child: Text(e.value)))
                        .toList()),
                IconButton(
                    tooltip: '取消选择',
                    icon: Icon(Icons.close),
                    onPressed: () => setState(() => selected.clear())),
              ] else ...[
                if (client == null)
                  IconButton(
                      tooltip: '容器详情',
                      icon: Icon(Icons.view_in_ar),
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ContainerDetail(widget.name)))),
                if (client != null) ...[
                  IconButton(
                      tooltip: automatic ? '关闭自动刷新' : '开启自动刷新',
                      icon: Icon(
                          automatic ? Icons.update : Icons.update_disabled),
                      onPressed: () {
                        setState(() => automatic = !automatic);
                        schedule();
                      }),
                  IconButton(
                      tooltip: '刷新',
                      icon: Icon(Icons.refresh),
                      onPressed: busy ? null : refresh),
                  IconButton(
                      tooltip: '断开连接',
                      icon: Icon(Icons.logout),
                      onPressed: busy
                          ? null
                          : () {
                              refreshTimer?.cancel();
                              client.close();
                              setState(() {
                                client = null;
                                tasks = [];
                                error = '';
                              });
                            }),
                ],
              ],
            ]),
        floatingActionButton: client == null
            ? null
            : FloatingActionButton(
                tooltip: '添加任务',
                onPressed: busy ? null : add,
                child: Icon(Icons.add)),
        body: SafeArea(
            top: false,
            child: client == null
                ? connection()
                : Column(children: [
                    if (busy) LinearProgressIndicator(minHeight: 2),
                    TorrentTransferSummary(tasks: tasks),
                    Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Row(children: [
                          Expanded(
                              child: TextField(
                                  onChanged: (v) => setState(() => query = v),
                                  decoration: InputDecoration(
                                      prefixIcon: Icon(Icons.search),
                                      hintText: '搜索 ${tasks.length} 个任务'))),
                          PopupMenuButton<String>(
                              tooltip: '排序',
                              icon: Icon(Icons.sort),
                              onSelected: (v) => setState(() => sort = v),
                              itemBuilder: (_) => const {
                                    'added': '最近添加',
                                    'name': '名称',
                                    'progress': '进度',
                                    'speed': '下载速度'
                                  }
                                      .entries
                                      .map((e) => PopupMenuItem(
                                          value: e.key, child: Text(e.value)))
                                      .toList()),
                        ])),
                    SizedBox(
                        height: 48,
                        child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            children: [
                              for (final group
                                  in TorrentPresentation.labels.entries)
                                if (group.key != 'other')
                                  Padding(
                                      padding: EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                          label: Text(
                                              '${group.value} ${group.key == 'all' ? tasks.length : tasks.where((t) => TorrentPresentation.group(t, transmission: widget.transmission) == group.key).length}'),
                                          selected: filter == group.key,
                                          selectedColor: Theme.of(context)
                                              .colorScheme
                                              .primaryContainer,
                                          labelStyle: TextStyle(
                                              color: filter == group.key
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .onPrimaryContainer
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant),
                                          onSelected: (_) => setState(
                                              () => filter = group.key))),
                            ])),
                    if (error.isNotEmpty) notice(),
                    Expanded(
                        child: RefreshIndicator(
                            onRefresh: refresh,
                            child: ListView(
                                physics: AlwaysScrollableScrollPhysics(),
                                padding: EdgeInsets.fromLTRB(16, 12, 16, 96),
                                children: [
                                  if (shown.isEmpty && !busy)
                                    WorkspaceEmpty(
                                        tasks.isEmpty ? '还没有下载任务' : '没有匹配的任务',
                                        icon: Icons.download_outlined,
                                        detail: tasks.isEmpty
                                            ? '点击右下角添加种子或下载链接。'
                                            : null),
                                  ...shown.map((task) => TorrentTaskCard(task,
                                      transmission: widget.transmission,
                                      selected:
                                          selected.contains('${task['id']}'),
                                      selectionMode: selected.isNotEmpty,
                                      onTap: () {
                                        if (selected.isNotEmpty) {
                                          setState(() {
                                            if (!selected.add('${task['id']}'))
                                              selected.remove('${task['id']}');
                                          });
                                        } else
                                          Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (_) => TorrentDetail(
                                                      client: client,
                                                      task: task)));
                                      },
                                      onLongPress: () => setState(() {
                                            if (!selected.add('${task['id']}'))
                                              selected.remove('${task['id']}');
                                          }),
                                      onAction: busy
                                          ? null
                                          : (action) =>
                                              control(action, [task]))),
                                ]))),
                  ])));
  }
}

class TorrentTransferSummary extends StatelessWidget {
  final List<Map> tasks;
  const TorrentTransferSummary({this.tasks = const []});
  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
          child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(children: [
                for (final down in [true, false])
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(down ? '下载合计' : '上传合计',
                            style: Theme.of(context).textTheme.caption),
                        SizedBox(height: 4),
                        Text(
                            '${down ? '↓' : '↑'} ${Util.formatSize(tasks.fold<num>(0, (sum, t) => sum + TorrentPresentation.number(t[down ? 'downloadSpeed' : 'uploadSpeed'])))}/s',
                            style: Theme.of(context).textTheme.subtitle1),
                      ]))
              ]))));
}

class TorrentTaskCard extends StatelessWidget {
  final Map task;
  final bool transmission, selected, selectionMode;
  final VoidCallback onTap, onLongPress;
  final ValueChanged<String> onAction;
  const TorrentTaskCard(this.task,
      {this.transmission = false,
      this.selected = false,
      this.selectionMode = false,
      this.onTap,
      this.onLongPress,
      this.onAction});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = TorrentPresentation.group(task, transmission: transmission);
    final progress =
        TorrentPresentation.number(task['progress']).clamp(0, 1).toDouble();
    final color = group == 'error'
        ? theme.colorScheme.error
        : group == 'seeding'
            ? (theme.brightness == Brightness.dark
                ? Color(0xff7fdbb3)
                : Color(0xff126a48))
            : theme.colorScheme.primary;
    return Card(
        shape: selected
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: theme.colorScheme.primary, width: 1.5))
            : null,
        child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 8, 14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        if (selectionMode) ...[
                          Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: color),
                          SizedBox(width: 10)
                        ],
                        Expanded(
                            child: Text('${task['name']}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.subtitle1)),
                        PopupMenuButton<String>(
                            enabled: onAction != null,
                            tooltip: '任务操作',
                            onSelected: onAction,
                            itemBuilder: (_) => _TorrentProgramState
                                .actions.entries
                                .map((e) => PopupMenuItem(
                                    value: e.key, child: Text(e.value)))
                                .toList()),
                      ]),
                      Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Row(children: [
                            Expanded(
                                child: Text(TorrentPresentation.labels[group],
                                    style:
                                        TextStyle(color: color, fontSize: 13))),
                            Text('${(progress * 100).toStringAsFixed(1)}%',
                                style: theme.textTheme.caption)
                          ])),
                      SizedBox(height: 10),
                      Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                  value: progress,
                                  color: color,
                                  minHeight: 4))),
                      SizedBox(height: 10),
                      Wrap(spacing: 16, runSpacing: 4, children: [
                        Text(
                            '↓ ${Util.formatSize(TorrentPresentation.number(task['downloadSpeed']))}/s',
                            style: theme.textTheme.caption),
                        Text(
                            '↑ ${Util.formatSize(TorrentPresentation.number(task['uploadSpeed']))}/s',
                            style: theme.textTheme.caption),
                        Text(
                            Util.formatSize(
                                TorrentPresentation.number(task['size'])),
                            style: theme.textTheme.caption)
                      ]),
                    ]))));
  }
}
