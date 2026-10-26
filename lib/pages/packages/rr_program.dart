import 'package:dsm_client/models/rr_protocol.dart';
import 'package:dsm_client/util/rr_api.dart';
import 'package:flutter/material.dart';
import 'program_page.dart';

Future<bool> confirmRr(BuildContext context, String operation) async =>
  await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
    title: Text(operation), content: Text('此操作会修改 NAS 的 RR 引导分区，可能影响下次启动。请确认已备份引导配置后继续。本客户端不会发送重启请求。'),
    actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text('取消')),
      TextButton(onPressed: () => Navigator.pop(dialog, true), child: Text('确认执行'))])) == true;

class RrProgram extends StatelessWidget {
  @override Widget build(BuildContext context) => DefaultTabController(length: 6, child: Scaffold(
    appBar: AppBar(title: Text('RR Manager'), bottom: TabBar(isScrollable: true, tabs: [
      Tab(text: '概览'), Tab(text: '引导配置'), Tab(text: 'Addons'), Tab(text: 'Modules'), Tab(text: '更新'), Tab(text: '日志'),
    ])), body: TabBarView(children: [RrReadPanel('overview'), RrConfigPanel(),
      RrItemsPanel('addons'), RrItemsPanel('modules'), RrUpdatesPanel(), RrReadPanel('log')])));
}

String rrError(Object e) => e is StateError ? '${e.message}' : '连接 RR Manager 失败，请重试';

class RrReadPanel extends StatefulWidget {
  final String action;
  const RrReadPanel(this.action);
  @override State<RrReadPanel> createState() => _RrReadPanelState();
}
class _RrReadPanelState extends State<RrReadPanel> {
  Map value;
  String error = '';
  bool busy = false;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    if (busy) return;
    setState(() { busy = true; error = ''; });
    try { final r = await RrApi.call(widget.action); if (mounted) setState(() => value = r); }
    catch (e) { if (mounted) setState(() => error = rrError(e)); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => RefreshIndicator(onRefresh: load, child: ListView(
    physics: AlwaysScrollableScrollPhysics(), padding: EdgeInsets.all(16), children: [
      if (busy) LinearProgressIndicator(),
      Row(children: [Expanded(child: Text(widget.action == 'overview' ? '引导、硬件与更新状态' : 'RR 更新日志')),
        IconButton(icon: Icon(Icons.refresh), onPressed: busy ? null : load)]),
      if (error.isNotEmpty) Text(error),
      if (value != null) widget.action == 'log' ? SelectableText('${value['log'] ?? '暂无日志'}') : NativeProperties(value),
    ]));
}

class RrConfigPanel extends StatefulWidget {
  @override State<RrConfigPanel> createState() => _RrConfigPanelState();
}
class _RrConfigPanelState extends State<RrConfigPanel> with AutomaticKeepAliveClientMixin {
  final editor = TextEditingController();
  String original, error = '', message = '';
  bool busy = false;
  @override bool get wantKeepAlive => true;
  @override void initState() { super.initState(); load(); }
  @override void dispose() { editor.dispose(); super.dispose(); }
  Future<void> load() async {
    if (busy) return;
    if (original != null && editor.text != original) {
      final discard = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
        title: Text('重新加载配置？'), content: Text('当前未保存的编辑将被丢弃。'),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text('取消')),
          TextButton(onPressed: () => Navigator.pop(dialog, true), child: Text('重新加载'))]));
      if (discard != true || !mounted) return;
    }
    setState(() { busy = true; error = ''; message = ''; });
    try { final r = await RrApi.call('read', params: {'file': 'user-config'});
      if (mounted) setState(() { original = '${r['content'] ?? ''}'; editor.text = original; }); }
    catch (e) { if (mounted) setState(() => error = rrError(e)); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> save() async {
    if (busy || original == null || editor.text.trim().isEmpty) return;
    if (!await confirmRr(context, '保存 user-config.yml') || !mounted) return;
    setState(() { busy = true; error = ''; });
    try {
      final latest = await RrApi.call('read', params: {'file': 'user-config'});
      if (latest['content'] != original) throw StateError('配置已被其他会话修改，请重新加载后再保存');
      final content = editor.text;
      final r = await RrApi.call('write', write: true, params: {'file': 'user-config', 'content': content});
      if (mounted) setState(() { original = content; message = '${r['message'] ?? '已保存，需要重启后生效'}'; });
    } catch (e) { if (mounted) setState(() => error = rrError(e)); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      if (busy) LinearProgressIndicator(),
      ButtonBar(children: [TextButton(onPressed: busy ? null : load, child: Text('重新加载')),
        ElevatedButton(onPressed: busy || original == null ? null : save, child: Text('保存配置'))]),
      if (error.isNotEmpty) Padding(padding: EdgeInsets.all(12), child: Text(error)),
      if (message.isNotEmpty) Padding(padding: EdgeInsets.all(12), child: Text(message)),
      Expanded(child: Padding(padding: EdgeInsets.all(16), child: TextField(controller: editor,
        readOnly: busy || original == null, maxLines: null, expands: true, textAlignVertical: TextAlignVertical.top,
        autocorrect: false, enableSuggestions: false, style: TextStyle(fontFamily: 'monospace'),
        decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'user-config.yml')))),
    ]);
  }
}

class RrItemsPanel extends StatefulWidget {
  final String action;
  const RrItemsPanel(this.action);
  @override State<RrItemsPanel> createState() => _RrItemsPanelState();
}
class _RrItemsPanelState extends State<RrItemsPanel> with AutomaticKeepAliveClientMixin {
  List<Map> items = [];
  Set<String> selected = {};
  bool busy = false, loaded = false;
  String error = '', filter = '', message = '';
  @override bool get wantKeepAlive => true;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    if (busy) return;
    setState(() { busy = true; error = ''; });
    try { final r = await RrApi.call(widget.action);
      if (mounted) setState(() {
        items = (r['items'] as List ?? []).whereType<Map>().toList();
        selected = items.where((i) => i['installed'] == true || RrProtocol.systemItem(i)).map((i) => '${i['name']}').toSet();
        loaded = true;
      });
    } catch (e) { if (mounted) setState(() => error = rrError(e)); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> save() async {
    if (busy || !loaded || !await confirmRr(context, '保存 ${widget.action} 选择') || !mounted) return;
    setState(() { busy = true; error = ''; });
    try { final r = await RrApi.call('save-${widget.action}', write: true,
      params: {'items': RrProtocol.selection(items, selected)});
      if (mounted) setState(() => message = '${r['message'] ?? '已保存，需要重启后生效'}');
    } catch (e) { if (mounted) setState(() => error = rrError(e)); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) {
    super.build(context);
    final shown = items.where((i) => '${i['name']} ${i['description']}'.toLowerCase().contains(filter.toLowerCase()));
    return Column(children: [
      if (busy) LinearProgressIndicator(),
      Padding(padding: EdgeInsets.all(16), child: TextField(onChanged: (v) => setState(() => filter = v),
        decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜索 ${widget.action}'))),
      ButtonBar(children: [TextButton(onPressed: busy ? null : load, child: Text('重新加载')),
        ElevatedButton(onPressed: busy || !loaded ? null : save, child: Text('保存选择'))]),
      if (error.isNotEmpty) Padding(padding: EdgeInsets.all(12), child: Text(error)),
      if (message.isNotEmpty) Padding(padding: EdgeInsets.all(12), child: Text(message)),
      Expanded(child: ListView(children: [
        if (loaded && items.isEmpty) ListTile(title: Text('暂无可用项目')),
        ...shown.map((i) => CheckboxListTile(title: Text('${i['name']}'), subtitle: Text('${i['description'] ?? ''}'),
          value: selected.contains('${i['name']}'), onChanged: busy || RrProtocol.systemItem(i) ? null : (v) => setState(() {
            if (v == true) selected.add('${i['name']}'); else selected.remove('${i['name']}');
          }))),
      ])),
    ]);
  }
}

class RrUpdatesPanel extends StatefulWidget {
  @override State<RrUpdatesPanel> createState() => _RrUpdatesPanelState();
}
class _RrUpdatesPanelState extends State<RrUpdatesPanel> with AutomaticKeepAliveClientMixin {
  Map release;
  String kind = 'rr', error = '', message = '';
  bool busy = false;
  @override bool get wantKeepAlive => true;
  Future<void> check() async {
    setState(() { busy = true; error = ''; release = null; });
    try { final r = await RrApi.call('$kind-release'); if (mounted) setState(() => release = r); }
    catch (e) { if (mounted) setState(() => error = rrError(e)); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> start({bool local = false}) async {
    String path;
    if (local) {
      final text = TextEditingController();
      path = await showDialog<String>(context: context, builder: (dialog) => AlertDialog(
        title: Text('NAS 上的更新包路径'), content: TextField(controller: text,
          decoration: InputDecoration(hintText: '/volume1/downloads/update.zip')),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: Text('取消')),
          TextButton(onPressed: () => Navigator.pop(dialog, text.text.trim()), child: Text('继续'))]));
      Future.delayed(Duration(milliseconds: 400), text.dispose);
      if (path == null || !mounted) return;
      if (!path.startsWith('/')) { setState(() => error = '请输入 NAS 上的绝对路径'); return; }
    }
    if (!await confirmRr(context, '更新 ${kind == 'rr' ? 'RR 引导' : 'RR Manager 套件'}') || !mounted) return;
    setState(() { busy = true; error = ''; });
    try { final r = await RrApi.call('start-$kind-update-${local ? 'local' : 'online'}', write: true,
      params: {if (local) 'path': path});
      if (mounted) setState(() => message = '${r['message'] ?? '更新任务已提交，请查看日志'}');
    } catch (e) { if (mounted) setState(() => error = rrError(e)); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) {
    super.build(context);
    return ListView(padding: EdgeInsets.all(16), children: [
      if (busy) LinearProgressIndicator(),
      DropdownButtonFormField<String>(value: kind, items: [DropdownMenuItem(value: 'rr', child: Text('RR 引导')),
        DropdownMenuItem(value: 'rrm', child: Text('RR Manager 套件'))], onChanged: busy ? null : (v) => setState(() {kind = v; release = null;})),
      TextButton(onPressed: busy ? null : check, child: Text('检查在线版本')),
      if (error.isNotEmpty) Text(error), if (message.isNotEmpty) Text(message),
      if (release != null) NativeProperties(release),
      ElevatedButton(onPressed: busy || release == null ? null : () => start(), child: Text('执行在线更新')),
      TextButton(onPressed: busy ? null : () => start(local: true), child: Text('使用 NAS 本地更新包')),
    ]);
  }
}
