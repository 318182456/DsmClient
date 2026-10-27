import 'package:flutter/material.dart';
import 'package:dsm_client/util/torrent_client.dart';
import 'package:dsm_client/util/torrent_rss.dart';
import 'package:dsm_client/util/torrent_rss_store.dart';
import 'package:dsm_client/widgets/workspace.dart';

class TorrentRssPage extends StatefulWidget {
  final TorrentClient client;
  final String profile;
  const TorrentRssPage({this.client, this.profile});
  @override
  State<TorrentRssPage> createState() => _TorrentRssState();
}

class _TorrentRssState extends State<TorrentRssPage> {
  final reader = TorrentRssReader();
  List<Map> feeds = [], articles = [];
  Map current;
  bool busy = false;
  bool rssEnabled;
  String error = '', query = '';
  bool get local => widget.client.transmission;
  TorrentRssStore get store =>
      TorrentRssStore('${widget.profile}|${widget.client.base}');
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    reader.close();
    super.dispose();
  }

  Future<void> execute(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => error = '操作失败，请检查订阅地址、网络或服务权限。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load({bool refresh = false}) => execute(() async {
        if (!local && refresh)
          await widget.client.qb('rss/refreshItem', post: true, params: {
            'itemPath': current == null ? '' : '${current['path']}'
          });
        if (!local) {
          try {
            final prefs = await widget.client.qb('app/preferences');
            if (prefs is Map && prefs['rss_processing_enabled'] is bool)
              rssEnabled = prefs['rss_processing_enabled'];
          } catch (_) {}
        }
        final rows = local
            ? await store.read()
            : TorrentRssReader.flatten((await widget.client
                .qb('rss/items', params: {'withData': 'true'})) as Map);
        List<Map> items = [];
        Map selected;
        if (current != null) {
          final matches = rows.where((r) =>
              r[local ? 'id' : 'path'] == current[local ? 'id' : 'path']);
          if (matches.isNotEmpty) {
            selected = matches.first;
            items = local
                ? await reader.read('${selected['url']}')
                : (selected['articles'] as List ?? [])
                    .whereType<Map>()
                    .toList();
          }
        }
        if (mounted)
          setState(() {
            feeds = rows;
            current = selected;
            articles = items;
          });
      });
  Future<bool> confirm(String title, String message) async =>
      await showDialog<bool>(
          context: context,
          builder: (dialog) =>
              AlertDialog(title: Text(title), content: Text(message), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: Text('取消')),
                TextButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: Text('确认'))
              ])) ??
      false;
  Future<void> addFeed() async {
    final name = TextEditingController(), url = TextEditingController();
    String warning = '';
    bool hidden = true;
    final result = await showDialog<Map>(
        context: context,
        builder: (dialog) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                    title: Text('添加 RSS 订阅'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: name,
                          decoration: InputDecoration(labelText: '订阅名称')),
                      SizedBox(height: 16),
                      TextField(
                          controller: url,
                          obscureText: hidden,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                              labelText: '订阅地址',
                              suffixIcon: IconButton(
                                  icon: Icon(hidden
                                      ? Icons.visibility_off
                                      : Icons.visibility),
                                  onPressed: () =>
                                      update(() => hidden = !hidden)))),
                      if (warning.isNotEmpty) Text(warning),
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: Text('取消')),
                      TextButton(
                          onPressed: () {
                            try {
                              TorrentRssReader.validate(url.text);
                              if (name.text.trim().isEmpty ||
                                  name.text.contains('\\') ||
                                  name.text.contains('/'))
                                throw FormatException();
                              Navigator.pop(dialog, {
                                'name': name.text.trim(),
                                'url': url.text.trim()
                              });
                            } catch (_) {
                              update(() => warning = '请输入名称和有效订阅地址，名称不能包含斜线');
                            }
                          },
                          child: Text('添加'))
                    ])));
    Future.delayed(Duration(milliseconds: 400), () {
      name.dispose();
      url.dispose();
    });
    if (result == null || !mounted) return;
    await execute(() async {
      if (local) {
        final rows = await store.read();
        if (rows.any((r) => r['url'] == result['url']))
          throw StateError('duplicate');
        await store.save([
          ...rows,
          {...result, 'id': '${DateTime.now().microsecondsSinceEpoch}'}
        ]);
      } else
        await widget.client.qb('rss/addFeed',
            post: true, params: {'url': result['url'], 'path': result['name']});
    });
    final failure = error;
    if (mounted) {
      await load();
      if (failure.isNotEmpty && mounted) setState(() => error = failure);
    }
  }

  Future<void> remove(Map feed) async {
    if (!await confirm('移除订阅', '移除“${feed['name']}”？已有下载任务会保留。') || !mounted)
      return;
    await execute(() async {
      if (local) {
        final rows = await store.read();
        rows.removeWhere((r) => r['id'] == feed['id']);
        await store.save(rows);
      } else
        await widget.client.qb('rss/removeItem',
            post: true, params: {'path': '${feed['path']}'});
    });
    final failure = error;
    if (mounted) {
      await load();
      if (failure.isNotEmpty && mounted) setState(() => error = failure);
    }
  }

  Future<void> download(Map article) async {
    final torrent = '${article['torrentURL'] ?? ''}';
    final link = torrent.isNotEmpty ? torrent : '${article['link'] ?? ''}';
    if (link.isEmpty ||
        !await confirm('添加下载任务',
            '${article['title'] ?? '未命名文章'}\n将提交到 ${local ? 'Transmission' : 'qBittorrent'}。') ||
        !mounted) return;
    await execute(() async {
      await widget.client.add(link);
      if (!local && article['id'] != null) {
        try {
          await widget.client.qb('rss/markAsRead', post: true, params: {
            'itemPath': '${current['path']}',
            'articleId': '${article['id']}'
          });
        } catch (_) {
          if (mounted) setState(() => error = '任务已提交，但标记已读失败。');
        }
      }
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('下载程序已接受任务')));
    });
  }

  @override
  Widget build(BuildContext context) => WillPopScope(
      onWillPop: () async {
        if (current == null) return true;
        setState(() {
          current = null;
          articles = [];
          query = '';
        });
        return false;
      },
      child: Scaffold(
          appBar: AppBar(
              title: Text(current == null ? 'RSS 订阅' : '${current['name']}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              leading: current == null
                  ? null
                  : BackButton(
                      onPressed: () => setState(() {
                            current = null;
                            articles = [];
                            query = '';
                          })),
              actions: [
                IconButton(
                    tooltip: '刷新订阅',
                    icon: Icon(Icons.refresh),
                    onPressed: busy ? null : () => load(refresh: true))
              ]),
          floatingActionButton: current == null
              ? FloatingActionButton(
                  tooltip: '添加订阅',
                  onPressed: busy ? null : addFeed,
                  child: Icon(Icons.add))
              : null,
          body: Column(children: [
            if (busy) LinearProgressIndicator(minHeight: 2),
            Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    local
                        ? '订阅加密保存在本机，打开文章页或手动刷新时更新。点击文章并确认后添加下载。'
                        : '订阅保存在 qBittorrent 服务端。点击文章并确认后添加下载；服务端刷新可能需要稍候。',
                    style: Theme.of(context).textTheme.caption)),
            if (error.isNotEmpty)
              Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(error,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            if (!local && rssEnabled == false)
              TextButton.icon(
                  icon: Icon(Icons.rss_feed),
                  label: Text('启用 qBittorrent RSS'),
                  onPressed: busy
                      ? null
                      : () async {
                          if (!await confirm(
                                  '启用 RSS', '启用后 qBittorrent 会在服务端定期读取订阅。') ||
                              !mounted) return;
                          await execute(() async {
                            await widget.client.qb('app/setPreferences',
                                post: true,
                                params: {
                                  'json': '{"rss_processing_enabled":true}'
                                });
                          });
                          if (mounted) await load();
                        }),
            if (current != null)
              Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                      onChanged: (v) => setState(() => query = v),
                      decoration: InputDecoration(
                          prefixIcon: Icon(Icons.search), hintText: '搜索订阅文章'))),
            Expanded(
                child: ListView(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: current == null
                        ? [
                            if (feeds.isEmpty && !busy)
                              WorkspaceEmpty('暂无 RSS 订阅',
                                  icon: Icons.rss_feed, detail: '点击右下角添加订阅。'),
                            ...feeds.map((f) => Card(
                                child: ListTile(
                                    leading: Icon(Icons.rss_feed),
                                    title: Text('${f['name']}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: Text(f['hasError'] == true
                                        ? '订阅刷新失败'
                                        : f['isLoading'] == true
                                            ? '服务端正在刷新…'
                                            : local
                                                ? '本机订阅'
                                                : '服务端订阅'),
                                    trailing: IconButton(
                                        tooltip: '移除订阅',
                                        icon: Icon(Icons.delete_outline),
                                        onPressed:
                                            busy ? null : () => remove(f)),
                                    onTap: busy
                                        ? null
                                        : () {
                                            setState(() => current = f);
                                            load();
                                          }))),
                          ]
                        : [
                            if (articles.isEmpty && !busy)
                              WorkspaceEmpty('暂无订阅文章',
                                  icon: Icons.article_outlined,
                                  detail: '可稍后刷新，或检查服务端是否已启用 RSS 处理。'),
                            ...articles
                                .where((a) => '${a['title']}'
                                    .toLowerCase()
                                    .contains(query.toLowerCase()))
                                .map((a) => Card(
                                    child: ListTile(
                                        title: Text('${a['title'] ?? '未命名文章'}',
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis),
                                        subtitle: Text('${a['date'] ?? ''}'),
                                        trailing:
                                            Icon(Icons.add_circle_outline),
                                        onTap:
                                            busy ? null : () => download(a))))
                          ]))
          ])));
}
