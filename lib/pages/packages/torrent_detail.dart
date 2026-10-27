import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dsm_client/util/torrent_client.dart';
import 'package:dsm_client/util/function.dart';
import 'package:dsm_client/models/torrent_presentation.dart';
import 'package:dsm_client/widgets/adaptive_tab_bar.dart';
import 'package:dsm_client/widgets/workspace.dart';
import 'program_page.dart';

class TorrentDetail extends StatefulWidget {
  final TorrentClient client;
  final Map task;
  const TorrentDetail({this.client, this.task});
  @override
  State<TorrentDetail> createState() => _TorrentDetailState();
}

class _TorrentDetailState extends State<TorrentDetail> {
  Map data = {};
  bool busy = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  String message(Object e) => e is HttpException
      ? e.message
      : e is FormatException
          ? e.message
          : '操作失败，请检查程序权限和连接';
  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = await widget.client.details(widget.task['id']);
      if (mounted)
        setState(() {
          data = result;
          error = '';
        });
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> mutate(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    String failure;
    try {
      await action();
    } catch (e) {
      failure = message(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) await load();
    if (mounted && failure != null) setState(() => error = failure);
  }

  Future<void> priority(Map file, int index) async {
    final value = await showModalBottomSheet<int>(
        context: context,
        builder: (sheet) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('${file['name']}',
                      maxLines: 2, overflow: TextOverflow.ellipsis)),
              for (final entry in <int, String>{
                0: '不下载',
                1: '正常优先级',
                6: '高优先级',
                if (!widget.client.transmission) 7: '最高优先级'
              }.entries)
                ListTile(
                    title: Text(entry.value),
                    onTap: () => Navigator.pop(sheet, entry.key)),
            ])));
    if (value != null && mounted)
      await mutate(
          () => widget.client.filePriority(widget.task['id'], index, value));
  }

  Future<void> tracker() async {
    final text = TextEditingController();
    String errorText = '';
    final value = await showDialog<String>(
        context: context,
        builder: (dialog) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                    title: Text('添加 Tracker'),
                    content: TextField(
                        controller: text,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                            labelText: 'Tracker 地址',
                            errorText: errorText.isEmpty ? null : errorText)),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: Text('取消')),
                      TextButton(
                          onPressed: () {
                            final uri = Uri.tryParse(text.text.trim());
                            if (uri == null ||
                                !['http', 'https', 'udp']
                                    .contains(uri.scheme) ||
                                uri.host.isEmpty) {
                              update(() => errorText = '请输入 HTTP/HTTPS/UDP 地址');
                              return;
                            }
                            Navigator.pop(dialog, text.text.trim());
                          },
                          child: Text('添加'))
                    ])));
    Future.delayed(Duration(milliseconds: 400), text.dispose);
    if (value != null && mounted)
      await mutate(() => widget.client.addTracker(widget.task['id'], value));
  }

  Future<void> limits() async {
    final properties = data['properties'] as Map ?? {};
    final down = TextEditingController(
        text: widget.client.transmission
            ? '${properties['downloadLimited'] == false ? 0 : properties['downloadLimit'] ?? 0}'
            : '${(TorrentPresentation.number(properties['dl_limit']) / 1024).clamp(0, 10485760).round()}');
    final up = TextEditingController(
        text: widget.client.transmission
            ? '${properties['uploadLimited'] == false ? 0 : properties['uploadLimit'] ?? 0}'
            : '${(TorrentPresentation.number(properties['up_limit']) / 1024).clamp(0, 10485760).round()}');
    String errorText = '';
    final result = await showDialog<List<int>>(
        context: context,
        builder: (dialog) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                    title: Text('任务限速'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                          '单位 ${widget.client.transmission ? 'KB/s' : 'KiB/s'}，0 表示不限速。'),
                      SizedBox(height: 16),
                      TextField(
                          controller: down,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: '下载限速')),
                      SizedBox(height: 16),
                      TextField(
                          controller: up,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: '上传限速')),
                      if (errorText.isNotEmpty)
                        Text(errorText,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: Text('取消')),
                      TextButton(
                          onPressed: () {
                            final d = int.tryParse(down.text),
                                u = int.tryParse(up.text);
                            if (d == null ||
                                u == null ||
                                d < 0 ||
                                u < 0 ||
                                d > 10485760 ||
                                u > 10485760) {
                              update(() => errorText = '请输入范围内的非负整数');
                              return;
                            }
                            Navigator.pop(dialog, [d, u]);
                          },
                          child: Text('保存'))
                    ])));
    Future.delayed(Duration(milliseconds: 400), () {
      down.dispose();
      up.dispose();
    });
    if (result != null && mounted)
      await mutate(
          () => widget.client.limits(widget.task['id'], result[0], result[1]));
  }

  Widget list(List<Widget> children) => RefreshIndicator(
      onRefresh: load,
      child: ListView(
          physics: AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(16),
          children: children));
  @override
  Widget build(BuildContext context) {
    final files = (data['files'] as List ?? []).whereType<Map>().toList();
    final trackers = (data['trackers'] as List ?? []).whereType<Map>().toList();
    final peers = (data['peers'] as List ?? []).whereType<Map>().toList();
    return DefaultTabController(
        length: 4,
        child: Scaffold(
            appBar: AppBar(
                title: Text('${widget.task['name']}'),
                actions: [
                  IconButton(
                      tooltip: '任务限速',
                      onPressed: busy ? null : limits,
                      icon: Icon(Icons.speed)),
                  IconButton(
                      tooltip: '刷新详情',
                      onPressed: busy ? null : load,
                      icon: Icon(Icons.refresh)),
                ],
                bottom: AdaptiveTabBar(tabs: [
                  Tab(text: '概览'),
                  Tab(text: '文件'),
                  Tab(text: 'Tracker'),
                  Tab(text: '连接')
                ])),
            body: Column(children: [
              if (busy) LinearProgressIndicator(minHeight: 2),
              if (error.isNotEmpty)
                Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(error,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              Expanded(
                  child: TabBarView(children: [
                list([
                  Card(
                      child: NativeProperties(
                          data['properties'] ?? widget.task['raw'] ?? {}))
                ]),
                list([
                  if (files.isEmpty && !busy)
                    WorkspaceEmpty('暂无文件信息', icon: Icons.folder_open),
                  for (var i = 0; i < files.length; i++)
                    Card(
                        child: ListTile(
                            title: Text('${files[i]['name']}',
                                maxLines: 3, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                '${(TorrentPresentation.number(files[i]['progress']) * 100).toStringAsFixed(1)}% · ${const {
                                      0: '不下载',
                                      1: '正常',
                                      6: '高',
                                      7: '最高'
                                    }[files[i]['priority']] ?? '正常'}'),
                            trailing: IconButton(
                                tooltip: '文件优先级',
                                onPressed: busy
                                    ? null
                                    : () => priority(
                                        files[i],
                                        (files[i]['index'] as num ?? i)
                                            .toInt()),
                                icon: Icon(Icons.tune))))
                ]),
                list([
                  Wrap(spacing: 8, children: [
                    TextButton.icon(
                        onPressed: busy ? null : tracker,
                        icon: Icon(Icons.add),
                        label: Text('添加 Tracker')),
                    TextButton.icon(
                        onPressed: busy
                            ? null
                            : () => mutate(() => widget.client
                                .control('reannounce', widget.task['id'])),
                        icon: Icon(Icons.refresh),
                        label: Text('重新通告'))
                  ]),
                  if (trackers.isEmpty && !busy)
                    WorkspaceEmpty('暂无 Tracker', icon: Icons.public),
                  ...trackers.map((t) => Card(
                      child: ListTile(
                          title: Text(
                              '${t['url'] ?? t['announce'] ?? 'Tracker'}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${t['msg'] ?? t['lastAnnounceResult'] ?? t['status'] ?? ''}'),
                          onTap: () => showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                  title: Text('Tracker 信息'),
                                  content: SingleChildScrollView(
                                      child: NativeProperties(t))))))),
                ]),
                list([
                  if (peers.isEmpty && !busy)
                    WorkspaceEmpty('暂无连接的 Peer', icon: Icons.people_outline),
                  ...peers.map((p) => Card(
                      child: ListTile(
                          title: Text('${p['ip'] ?? p['address'] ?? 'Peer'}'),
                          subtitle: Text(
                              '${p['client'] ?? p['clientName'] ?? ''}\n'
                              '↓ ${Util.formatSize(TorrentPresentation.number(p['dl_speed'] ?? p['rateToClient']))}/s · ↑ ${Util.formatSize(TorrentPresentation.number(p['up_speed'] ?? p['rateToPeer']))}/s')))),
                ]),
              ])),
            ])));
  }
}
