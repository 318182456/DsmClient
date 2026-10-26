import 'dart:io';
import 'package:dsm_client/pages/docker/detail.dart';
import 'package:dsm_client/util/function.dart';
import 'package:dsm_client/util/torrent_client.dart';
import 'package:flutter/material.dart';
import 'program_page.dart';

class TorrentProgram extends StatefulWidget {
  final String name;
  final bool transmission;
  const TorrentProgram(this.name, {this.transmission = false});
  @override
  State<TorrentProgram> createState() => _TorrentProgramState();
}

class _TorrentProgramState extends State<TorrentProgram> {
  final address = TextEditingController(),
      account = TextEditingController(),
      password = TextEditingController();
  TorrentClient client;
  List<Map> tasks = [];
  bool busy = false;
  String error = '', query = '';
  @override
  void dispose() {
    client?.close();
    address.dispose();
    account.dispose();
    password.dispose();
    super.dispose();
  }

  String message(Object e) => e is FormatException
      ? e.message
      : e is HttpException
          ? e.message
          : '连接失败，请检查程序地址、证书和网络后重试';

  Future<void> connect() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    TorrentClient candidate;
    try {
      candidate =
          TorrentClient(address.text, transmission: widget.transmission);
      await candidate.login(account.text.trim(), password.text);
      final list = await candidate.list();
      if (!mounted) {
        candidate.close();
        return;
      }
      setState(() {
        client = candidate;
        tasks = list;
        password.clear();
      });
    } catch (e) {
      candidate?.close();
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() async {
    if (busy || client == null) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final list = await client.list();
      if (mounted) setState(() => tasks = list);
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> control(String action, Map task) async {
    final labels = {
      'start': '开始任务',
      'stop': '暂停任务',
      'verify': '重新校验',
      'remove': '移除任务'
    };
    final yes = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: Text(labels[action]),
                content: Text(
                    '${task['name']}${action == 'remove' ? '\n保留已下载的文件。' : ''}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: Text('确认'))
                ]));
    if (yes != true || !mounted || busy) return;
    setState(() => busy = true);
    try {
      await client.control(action, task['id']);
      if (mounted) Util.toast('操作已提交');
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) await refresh();
  }

  Future<void> add() async {
    final text = TextEditingController();
    final value = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: Text('添加下载任务'),
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
    if (!mounted || value == null || value.isEmpty || busy) return;
    setState(() => busy = true);
    try {
      await client.add(value);
      if (mounted) Util.toast('任务已添加');
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) await refresh();
  }

  Future<void> details(Map task) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final data = await client.details(task['id']);
      if (mounted)
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => Scaffold(
                    appBar: AppBar(title: Text('${task['name']}')),
                    body:
                        SingleChildScrollView(child: NativeProperties(data)))));
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = tasks
        .where(
            (t) => '${t['name']}'.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Scaffold(
        appBar: AppBar(title: Text(widget.name), actions: [
          IconButton(
              icon: Icon(Icons.view_in_ar),
              tooltip: '容器详情',
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ContainerDetail(widget.name)))),
          if (client != null)
            IconButton(
                icon: Icon(Icons.refresh), onPressed: busy ? null : refresh),
          if (client != null)
            IconButton(
                icon: Icon(Icons.logout),
                tooltip: '断开连接',
                onPressed: busy
                    ? null
                    : () {
                        client.close();
                        setState(() {
                          client = null;
                          tasks = [];
                          error = '';
                        });
                      }),
        ]),
        floatingActionButton: client == null
            ? null
            : FloatingActionButton(
                onPressed: busy ? null : add,
                tooltip: '添加任务',
                child: Icon(Icons.add)),
        body: client == null
            ? ListView(padding: EdgeInsets.all(20), children: [
                Text(
                    widget.transmission
                        ? '连接 Transmission RPC'
                        : '连接 qBittorrent API',
                    style: Theme.of(context).textTheme.headline6),
                SizedBox(height: 12),
                Text('使用此程序自己的地址和账号。密码仅用于当前连接，关闭页面后清除。'),
                TextField(
                    controller: address,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(
                        labelText: '服务地址',
                        hintText: widget.transmission
                            ? 'https://example.com/transmission/rpc'
                            : 'https://example.com/qbittorrent')),
                TextField(
                    controller: account,
                    autocorrect: false,
                    decoration: InputDecoration(labelText: '程序账号')),
                TextField(
                    controller: password,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(labelText: '程序密码')),
                if (error.isNotEmpty)
                  Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(error)),
                SizedBox(height: 20),
                ElevatedButton(
                    onPressed: busy ? null : connect,
                    child: Text(busy ? '正在连接…' : '连接')),
              ])
            : Column(children: [
                if (busy) LinearProgressIndicator(),
                Padding(
                    padding: EdgeInsets.all(16),
                    child: TextField(
                        onChanged: (v) => setState(() => query = v),
                        decoration: InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: '搜索任务（${tasks.length}）'))),
                if (error.isNotEmpty)
                  Padding(padding: EdgeInsets.all(12), child: Text(error)),
                Expanded(
                    child: RefreshIndicator(
                        onRefresh: refresh,
                        child: ListView(
                            physics: AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.only(bottom: 90),
                            children: [
                              if (tasks.isEmpty)
                                ListTile(title: Text('暂无下载任务')),
                              ...shown.map((t) {
                                final progress = (t['progress'] as num ?? 0)
                                    .toDouble()
                                    .clamp(0.0, 1.0)
                                    .toDouble();
                                return Card(
                                    margin: EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 6),
                                    child: Column(children: [
                                      ListTile(
                                          title: Text('${t['name']}'),
                                          subtitle: Text(
                                              '${(progress * 100).toStringAsFixed(1)}% · ${t['state']}\n'
                                              '↓ ${Util.formatSize(t['downloadSpeed'] as num ?? 0)}/s  ↑ ${Util.formatSize(t['uploadSpeed'] as num ?? 0)}/s'),
                                          onTap: () => details(t),
                                          trailing: PopupMenuButton<String>(
                                              enabled: !busy,
                                              onSelected: (v) => control(v, t),
                                              itemBuilder: (_) => [
                                                    PopupMenuItem(
                                                        value: 'start',
                                                        child: Text('开始')),
                                                    PopupMenuItem(
                                                        value: 'stop',
                                                        child: Text('暂停')),
                                                    PopupMenuItem(
                                                        value: 'verify',
                                                        child: Text('校验')),
                                                    PopupMenuItem(
                                                        value: 'remove',
                                                        child:
                                                            Text('移除任务，保留文件'))
                                                  ])),
                                      LinearProgressIndicator(value: progress),
                                    ]));
                              })
                            ]))),
              ]));
  }
}
