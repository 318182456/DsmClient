import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dsm_client/models/qb_rss_rule.dart';
import 'package:dsm_client/util/torrent_client.dart';
import 'package:dsm_client/util/torrent_rss.dart';
import 'package:dsm_client/widgets/workspace.dart';

Future<bool> rssConfirm(
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

class QbRssRulesPage extends StatefulWidget {
  final TorrentClient client;
  final String feedUrl;
  const QbRssRulesPage(this.client, {this.feedUrl});
  @override
  State<QbRssRulesPage> createState() => _QbRssRulesState();
}

class _QbRssRulesState extends State<QbRssRulesPage> {
  Map rules = {}, categories = {};
  List<Map> feeds = [];
  List<String> tags = [];
  bool busy = false, autoEnabled = false, processing = false;
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
      final values = await Future.wait([
        widget.client.qb('rss/rules'),
        widget.client.qb('rss/items', params: {'withData': 'false'}),
        widget.client.qb('torrents/categories'),
        widget.client.qb('app/preferences'),
        widget.client.qb('torrents/tags')
      ]);
      if (mounted)
        setState(() {
          rules = values[0] as Map ?? {};
          feeds = TorrentRssReader.flatten(values[1] as Map ?? {});
          categories = values[2] as Map ?? {};
          final prefs = values[3] as Map ?? {};
          autoEnabled = prefs['rss_auto_downloading_enabled'] == true;
          processing = prefs['rss_processing_enabled'] == true;
          tags = (values[4] as List ?? []).map((v) => '$v').toList();
          error = '';
        });
    } catch (_) {
      if (mounted) setState(() => error = '无法读取 RSS 规则，请检查连接、qB 版本与权限');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> engine(bool enabled) async {
    if (!await rssConfirm(
            context,
            enabled ? '开启 RSS 自动下载' : '关闭 RSS 自动下载',
            enabled
                ? '服务器上所有已启用的 RSS 规则都会开始执行，符合条件的文章可能立即添加下载。'
                : '停止所有 RSS 规则自动添加任务；已有下载任务继续运行。') ||
        !mounted) return;
    await change(() async {
      await widget.client.qb('app/setPreferences', post: true, params: {
        'json': jsonEncode({
          'rss_auto_downloading_enabled': enabled,
          if (enabled) 'rss_processing_enabled': true
        })
      });
    });
  }

  Future<void> change(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    String failure;
    try {
      await action();
    } catch (_) {
      failure = '设置未成功，请检查连接或服务权限';
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) {
      await load();
      if (failure != null && mounted) setState(() => error = failure);
    }
  }

  Future<void> edit({String name, Map rule}) async {
    final result = await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => QbRssRuleEditor(widget.client,
                name: name,
                rule: rule ?? {},
                feeds: feeds,
                categories: categories,
                knownTags: tags,
                engineEnabled: autoEnabled && processing,
                presetFeed: widget.feedUrl)));
    if (!mounted) return;
    if (result == true || result == 'engine-failed') {
      await load();
      if (result == 'engine-failed' && mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('规则已保存，请在规则页重新开启自动下载总开关')));
    }
  }

  Future<void> toggle(String name, bool enabled) async {
    if (enabled &&
            !await rssConfirm(
                context, '启用自动下载规则', '启用“$name”后，符合条件的文章可能立即添加下载。') ||
        !mounted) return;
    await change(() async {
      final latest = await widget.client.qb('rss/rules') as Map;
      if (latest[name] is! Map) throw StateError('deleted');
      await widget.client.qb('rss/setRule', post: true, params: {
        'ruleName': name,
        'ruleDef': jsonEncode({...latest[name] as Map, 'enabled': enabled})
      });
    });
  }

  Future<void> remove(String name) async {
    if (!await rssConfirm(context, '删除自动下载规则', '删除“$name”？订阅和已有下载任务会保留。') ||
        !mounted) return;
    await change(() async {
      await widget.client
          .qb('rss/removeRule', post: true, params: {'ruleName': name});
    });
  }

  Future<void> matches(String name) async {
    setState(() => busy = true);
    try {
      final value = await widget.client
              .qb('rss/matchingArticles', params: {'ruleName': name}) as Map ??
          {};
      if (mounted)
        await showDialog(
            context: context,
            builder: (dialog) => AlertDialog(
                    title: Text('匹配文章 · $name'),
                    content: SizedBox(
                        width: double.maxFinite,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              if (value.isEmpty) Text('暂无匹配文章'),
                              for (final entry in value.entries) ...[
                                Text('${entry.key}',
                                    style:
                                        Theme.of(context).textTheme.subtitle1),
                                for (final title in entry.value as List ?? [])
                                  Padding(
                                      padding: EdgeInsets.only(top: 8),
                                      child: Text('$title'))
                              ]
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: Text('关闭'))
                    ]));
    } catch (_) {
      if (mounted) setState(() => error = '无法预览匹配文章');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = rules.entries
        .where((e) =>
            e.value is Map &&
            (widget.feedUrl == null ||
                QbRssRule.feeds(e.value).contains(widget.feedUrl)))
        .toList();
    return Scaffold(
        appBar: AppBar(title: Text('RSS 自动下载'), actions: [
          IconButton(
              tooltip: '刷新规则',
              icon: Icon(Icons.refresh),
              onPressed: busy ? null : load)
        ]),
        floatingActionButton: FloatingActionButton(
            tooltip: '新增规则',
            onPressed: busy ? null : () => edit(),
            child: Icon(Icons.add)),
        body: Column(children: [
          if (busy) LinearProgressIndicator(minHeight: 2),
          Expanded(
              child: ListView(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                Card(
                    child: SwitchListTile(
                        title: Text('服务端自动下载总开关'),
                        subtitle: Text(autoEnabled && processing
                            ? '关闭手机 App 后，qB 仍会执行启用的规则'
                            : '总开关未开启，规则不会自动添加任务'),
                        value: autoEnabled && processing,
                        onChanged: busy ? null : engine)),
                if (error.isNotEmpty)
                  Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(error,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
                if (shown.isEmpty && !busy)
                  WorkspaceEmpty('暂无自动下载规则',
                      detail: '添加规则并选择订阅，可设置标题匹配、分类及保存目录。', icon: Icons.rule),
                for (final entry in shown)
                  Card(
                      child: Column(children: [
                    SwitchListTile(
                        title: Text('${entry.key}'),
                        value: entry.value['enabled'] != false,
                        onChanged:
                            busy ? null : (v) => toggle('${entry.key}', v),
                        subtitle: Text(
                            '分类：${QbRssRule.category(entry.value).isEmpty ? '未分类' : QbRssRule.category(entry.value)} · ${QbRssRule.stopped(entry.value) == true ? '暂停添加' : '自动添加'}')),
                    Wrap(children: [
                      TextButton(
                          onPressed: busy
                              ? null
                              : () =>
                                  edit(name: '${entry.key}', rule: entry.value),
                          child: Text('编辑规则')),
                      TextButton(
                          onPressed:
                              busy ? null : () => matches('${entry.key}'),
                          child: Text('匹配文章')),
                      TextButton(
                          onPressed: busy ? null : () => remove('${entry.key}'),
                          child: Text('删除规则'))
                    ])
                  ])),
              ]))
        ]));
  }
}

class QbRssRuleEditor extends StatefulWidget {
  final TorrentClient client;
  final String name, presetFeed;
  final Map rule, categories;
  final List<Map> feeds;
  final List<String> knownTags;
  final bool engineEnabled;
  const QbRssRuleEditor(this.client,
      {this.name,
      this.rule = const {},
      this.feeds = const [],
      this.categories = const {},
      this.knownTags = const [],
      this.engineEnabled = false,
      this.presetFeed});
  @override
  State<QbRssRuleEditor> createState() => _QbRssRuleEditorState();
}

class _QbRssRuleEditorState extends State<QbRssRuleEditor> {
  TextEditingController name,
      include,
      exclude,
      category,
      tags,
      path,
      episode,
      days;
  bool enabled = true,
      regex = false,
      automaticPath = false,
      busy = false,
      enableEngine = false;
  String behavior = 'default', error = '';
  Set<String> selected = {};
  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    name = TextEditingController(text: widget.name ?? '');
    include = TextEditingController(text: '${r['mustContain'] ?? ''}');
    exclude = TextEditingController(text: '${r['mustNotContain'] ?? ''}');
    category = TextEditingController(text: QbRssRule.category(r));
    tags = TextEditingController(text: QbRssRule.tags(r).join(', '));
    path = TextEditingController(text: QbRssRule.path(r));
    episode = TextEditingController(text: '${r['episodeFilter'] ?? ''}');
    days = TextEditingController(text: '${r['ignoreDays'] ?? 0}');
    enabled = r['enabled'] != false;
    regex = r['useRegex'] == true;
    automaticPath = QbRssRule.params(r)['use_auto_tmm'] == true;
    final stopped = QbRssRule.stopped(r);
    behavior = stopped == null
        ? 'default'
        : stopped
            ? 'paused'
            : 'start';
    selected = QbRssRule.feeds(r).toSet();
    if (widget.name == null && widget.presetFeed != null)
      selected.add(widget.presetFeed);
  }

  @override
  void dispose() {
    for (final c in [
      name,
      include,
      exclude,
      category,
      tags,
      path,
      episode,
      days
    ]) c.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    Map draft;
    try {
      if (name.text.trim().isEmpty) throw FormatException('请输入规则名称');
      final ignore = int.tryParse(days.text);
      if (ignore == null) throw FormatException('忽略天数需为整数');
      draft = QbRssRule.build(widget.rule,
          enabled: enabled,
          regex: regex,
          include: include.text,
          exclude: exclude.text,
          episode: episode.text,
          ignoreDays: ignore,
          feeds: selected.toList(),
          category: category.text,
          tags: tags.text.split(','),
          savePath: path.text,
          automaticPath: automaticPath,
          stopped: behavior == 'default' ? null : behavior == 'paused');
    } on FormatException catch (e) {
      setState(() => error = e.message);
      return;
    }
    final createCategory = category.text.trim().isNotEmpty &&
        !widget.categories.containsKey(category.text.trim());
    if (!await rssConfirm(context, '保存自动下载规则',
            '规则：${name.text.trim()}\n关联 ${selected.length} 个订阅\n分类：${category.text.trim().isEmpty ? '未分类' : category.text.trim()}${createCategory ? '（将创建分类）' : ''}\n${enabled ? '规则启用后，匹配的现有及后续文章可能立即添加任务。' : '规则保存为停用。'}${enableEngine ? '\n同时开启总开关，服务器所有启用的 RSS 规则都会开始执行。' : ''}') ||
        !mounted) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final latest = await widget.client.qb('rss/rules') as Map ?? {};
      if (widget.name == null && latest.containsKey(name.text.trim()))
        throw FormatException('规则名称已存在，请使用其他名称');
      if (widget.name != null && latest[widget.name] is! Map)
        throw FormatException('该规则已被删除，请返回刷新');
      if (createCategory) {
        final currentCategories =
            await widget.client.qb('torrents/categories') as Map ?? {};
        if (!currentCategories.containsKey(category.text.trim()))
          await widget.client
              .qb('torrents/createCategory', post: true, params: {
            'category': category.text.trim(),
            'savePath': automaticPath ? '' : path.text.trim()
          });
      }
      final current = widget.name == null
          ? <String, dynamic>{}
          : latest[widget.name] as Map;
      draft = QbRssRule.build(current,
          enabled: enabled,
          regex: regex,
          include: include.text,
          exclude: exclude.text,
          episode: episode.text,
          ignoreDays: int.parse(days.text),
          feeds: selected.toList(),
          category: category.text,
          tags: tags.text.split(','),
          savePath: path.text,
          automaticPath: automaticPath,
          stopped: behavior == 'default' ? null : behavior == 'paused');
      await widget.client.qb('rss/setRule',
          post: true,
          params: {'ruleName': name.text.trim(), 'ruleDef': jsonEncode(draft)});
      if (enableEngine) {
        try {
          await widget.client.qb('app/setPreferences', post: true, params: {
            'json': jsonEncode({
              'rss_processing_enabled': true,
              'rss_auto_downloading_enabled': true
            })
          });
        } catch (_) {
          if (mounted) Navigator.pop(context, 'engine-failed');
          return;
        }
      }
      if (mounted) Navigator.pop(context, true);
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = '规则保存失败，请检查服务权限及填写内容。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(TextEditingController controller, String title,
          {String hint,
          Widget suffix,
          bool enabled = true,
          TextInputType keyboard}) =>
      Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: TextField(
              key: ValueKey('rss-rule-field:$title'),
              controller: controller,
              enabled: enabled && !busy,
              keyboardType: keyboard,
              decoration: InputDecoration(
                  labelText: title, hintText: hint, suffixIcon: suffix)));
  @override
  Widget build(BuildContext context) {
    final choices = {
      for (final f in widget.feeds) '${f['url']}': '${f['name']}'
    };
    for (final url in selected) choices.putIfAbsent(url, () => '未找到的订阅');
    return Scaffold(
        appBar:
            AppBar(title: Text(widget.name == null ? '新增自动下载规则' : '编辑自动下载规则')),
        bottomNavigationBar: SafeArea(
            child: Padding(
                padding: EdgeInsets.all(16),
                child: ElevatedButton(
                    onPressed: busy ? null : save,
                    child: Text(busy ? '正在保存…' : '保存规则')))),
        body: ListView(padding: EdgeInsets.all(20), children: [
          field(name, '规则名称', enabled: widget.name == null),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('启用规则'),
              value: enabled,
              onChanged: busy ? null : (v) => setState(() => enabled = v)),
          field(include, '标题包含', hint: '留空匹配全部；支持 qB 通配符及 | 分组'),
          field(exclude, '标题排除'),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('使用正则表达式'),
              value: regex,
              onChanged: busy ? null : (v) => setState(() => regex = v)),
          field(episode, '剧集过滤（可选）', hint: '例如 1x1-12;'),
          field(days, '忽略天数', keyboard: TextInputType.number),
          Text('关联订阅', style: Theme.of(context).textTheme.subtitle1),
          if (choices.isEmpty)
            Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('请先添加 RSS 订阅')),
          for (final item in choices.entries)
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.value),
                subtitle: Text(Uri.tryParse(item.key)?.host ?? ''),
                value: selected.contains(item.key),
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                          if (v == true)
                            selected.add(item.key);
                          else
                            selected.remove(item.key);
                        })),
          SizedBox(height: 16),
          field(category, '下载分类',
              hint: '可选择现有分类或输入新分类',
              suffix: PopupMenuButton<String>(
                  enabled: !busy,
                  tooltip: '选择现有分类',
                  icon: Icon(Icons.folder_outlined),
                  onSelected: (v) => setState(() => category.text = v),
                  itemBuilder: (_) => [
                        PopupMenuItem(value: '', child: Text('未分类')),
                        ...widget.categories.keys.map((v) =>
                            PopupMenuItem(value: '$v', child: Text('$v')))
                      ])),
          field(tags, '下载标签', hint: '多个标签用逗号分隔'),
          if (widget.knownTags.isNotEmpty)
            Wrap(
                spacing: 8,
                children: widget.knownTags
                    .take(12)
                    .map((v) => ActionChip(
                        label: Text(v),
                        onPressed: busy
                            ? null
                            : () {
                                final current = tags.text
                                    .split(',')
                                    .map((v) => v.trim())
                                    .where((v) => v.isNotEmpty)
                                    .toSet();
                                current.add(v);
                                setState(() => tags.text = current.join(', '));
                              }))
                    .toList()),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('按分类自动管理目录'),
              value: automaticPath,
              onChanged:
                  busy ? null : (v) => setState(() => automaticPath = v)),
          field(path, '保存目录', hint: '服务端路径，留空使用默认位置', enabled: !automaticPath),
          DropdownButtonFormField<String>(
              value: behavior,
              decoration: InputDecoration(labelText: '添加后的状态'),
              items: [
                DropdownMenuItem(value: 'default', child: Text('沿用 qB 默认设置')),
                DropdownMenuItem(value: 'start', child: Text('立即开始下载')),
                DropdownMenuItem(value: 'paused', child: Text('暂停添加'))
              ],
              onChanged: busy ? null : (v) => setState(() => behavior = v)),
          if (!widget.engineEnabled)
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('同时开启服务端自动下载总开关'),
                subtitle: Text('会开始执行服务器上所有已启用的 RSS 规则'),
                value: enableEngine,
                onChanged:
                    busy ? null : (v) => setState(() => enableEngine = v)),
          if (error.isNotEmpty)
            Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(error,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
        ]));
  }
}
