import 'package:dsm_client/widgets/adaptive_tab_bar.dart';
import 'package:dsm_client/models/program_section.dart';
import 'package:dsm_client/util/function.dart';
import 'package:dsm_client/util/program_api.dart';
import 'package:flutter/material.dart';
import 'program_page.dart';

class SnapshotProgram extends StatefulWidget {
  @override
  State<SnapshotProgram> createState() => _SnapshotProgramState();
}

class _SnapshotProgramState extends State<SnapshotProgram> {
  List<String> shares = [];
  String selected, error = '';
  bool loading = true, busy = false;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final result = await Api.shareCore(additional: ['support_snapshot']);
      if (!mounted) return;
      if (result['success'] != true) {
        setState(() => error = ProgramApi.error(result));
        return;
      }
      final all =
          ((result['data'] ?? {})['shares'] as List ?? []).whereType<Map>();
      setState(() {
        shares = all
            .where((s) => (s['additional'] ?? {})['support_snapshot'] != false)
            .map((s) => '${s['name']}')
            .toList();
        if (!shares.contains(selected))
          selected = shares.isEmpty ? null : shares.first;
      });
    } catch (_) {
      if (mounted) setState(() => error = '共享文件夹加载失败');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> create() async {
    if (selected == null || busy) return;
    final text = TextEditingController();
    final share = selected;
    final description = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: Text('为 $share 拍摄快照'),
                content: TextField(
                    controller: text,
                    decoration: InputDecoration(labelText: '快照说明（可选）')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog),
                      child: Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, text.text.trim()),
                      child: Text('创建'))
                ]));
    Future.delayed(Duration(milliseconds: 400), text.dispose);
    if (description == null || !mounted) return;
    setState(() => busy = true);
    try {
      final result = await ProgramApi.call(
          ProgramSection('', 'SYNO.Core.Share.Snapshot', 'create'),
          params: {
            'name': share,
            'snapinfo': {'desc': description, 'lock': false}
          });
      if (mounted) {
        Util.toast(
            result['success'] == true ? '快照创建已提交' : ProgramApi.error(result));
        setState(() => revision++);
      }
    } catch (_) {
      if (mounted) Util.toast('连接失败，请刷新确认快照状态');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: 2,
      child: Scaffold(
          appBar: AppBar(
              title: Text('Snapshot Replication'),
              bottom: AdaptiveTabBar(
                  tabs: [Tab(text: '共享文件夹快照'), Tab(text: '复制任务')]),
              actions: [
                IconButton(
                    icon: Icon(Icons.refresh),
                    onPressed: loading || busy ? null : load)
              ]),
          body: TabBarView(children: [
            Column(children: [
              if (busy) LinearProgressIndicator(),
              if (error.isNotEmpty)
                Padding(padding: EdgeInsets.all(16), child: Text(error)),
              if (loading) LinearProgressIndicator(),
              if (!loading)
                Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(children: [
                      Expanded(
                          child: DropdownButton<String>(
                              value: selected,
                              isExpanded: true,
                              hint: Text('无支持快照的共享文件夹'),
                              items: shares
                                  .map((s) => DropdownMenuItem(
                                      value: s, child: Text(s)))
                                  .toList(),
                              onChanged: busy
                                  ? null
                                  : (v) => setState(() => selected = v))),
                      IconButton(
                          icon: Icon(Icons.add_a_photo_outlined),
                          tooltip: '创建快照',
                          onPressed: selected == null || busy ? null : create),
                    ])),
              if (selected != null)
                Expanded(
                    child: ProgramDataView(
                        ProgramSection('快照', 'SYNO.Core.Share.Snapshot', 'list',
                            version: 2,
                            listKey: 'snapshots',
                            params: {
                              'name': selected,
                              'filter': {'attr': []},
                              'additional': [
                                'desc',
                                'lock',
                                'worm_lock',
                                'schedule_snapshot'
                              ],
                              'offset': 0,
                              'limit': 100
                            }),
                        key: ValueKey('$selected:$revision'),
                        packageId: 'SnapshotReplication')),
            ]),
            ProgramDataView(ProgramSection('复制任务', 'SYNO.DR.Plan', 'list',
                listKey: 'plans', params: {'additional': []})),
          ])));
}
