import 'package:flutter/material.dart';
import 'package:dsm_client/util/drive_admin_api.dart';
import 'package:dsm_client/widgets/workspace.dart';
import 'package:dsm_client/models/display_text.dart';
import 'drive_console.dart';
import 'program_page.dart';

class DriveRecordsPage extends StatefulWidget {
  final DriveAdminApi api;
  final String kind;
  const DriveRecordsPage(this.api, {this.kind = 'clients'});
  @override
  State<DriveRecordsPage> createState() => _DriveRecordsState();
}

class _DriveRecordsState extends State<DriveRecordsPage> {
  List<Map> rows = [];
  bool busy = false, more = false;
  String error = '', query = '';
  int offset = 0, logType = -1;
  String get title => const {
        'clients': '客户端列表',
        'logs': '同步日志',
        'shares': '团队文件夹'
      }[widget.kind];
  String get apiName => const {
        'clients': 'SYNO.SynologyDrive.Connection',
        'logs': 'SYNO.SynologyDrive.Log',
        'shares': 'SYNO.SynologyDrive.Share'
      }[widget.kind];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool next = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final data = await widget.api.list(apiName,
          offset: next ? offset : 0, keyword: query, logType: logType);
      final batch = (data['items'] as List ?? []).whereType<Map>().toList();
      if (mounted)
        setState(() {
          rows = next ? [...rows, ...batch] : batch;
          offset = rows.length;
          more = batch.isNotEmpty &&
              (data['total'] is num
                  ? offset < data['total']
                  : batch.length == 100);
          error = '';
        });
    } catch (e) {
      if (mounted) setState(() => error = driveError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> disconnect(Map row) async {
    if (busy) return;
    if (!await confirmDrive(context, '断开客户端',
            '将断开“${row['client_name'] ?? '此设备'}”的 Drive 会话。设备可重新登录连接，本操作不删除设备上的本地文件。') ||
        !mounted) return;
    setState(() => busy = true);
    try {
      await widget.api.disconnect('${row['client_session_id'] ?? ''}');
    } catch (e) {
      if (mounted) setState(() => error = driveError(e));
      return;
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) await load();
  }

  void details(Map row, String title) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => Scaffold(
              appBar: AppBar(title: Text(title)),
              body: SingleChildScrollView(
                  padding: EdgeInsets.all(16), child: NativeProperties(row)))));
  Widget row(Map item) {
    if (widget.kind == 'shares') {
      final name = '${item['share_name'] ?? ''}',
          enabled = item['share_enable'] == true;
      return Card(
          child: ListTile(
              leading: Icon(Icons.folder_shared_outlined),
              title: Text(name),
              subtitle: Text(
                  '${enabled ? '已启用' : '未启用'} · ${item['rotate_cnt'] ?? 0} 个历史版本'),
              trailing: Icon(Icons.tune),
              onTap: busy
                  ? null
                  : () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  DriveShareEditor(widget.api, name)));
                      if (mounted) load();
                    }));
    }
    final name = widget.kind == 'clients'
        ? '${item['client_name'] ?? '客户端'}'
        : const {
              0: '服务设置',
              1: '权限设置',
              2: '团队文件夹设置',
              3: '客户端断开',
              4: '恢复版本',
              5: '永久删除文件',
              6: '删除文件',
              7: '版本设置',
              12: '客户端连接',
              13: '新增文件',
              14: '移除文件',
              15: '修改文件',
              16: '版本轮换',
              17: '重命名文件',
              18: '复制文件',
              23: '下载文件',
              24: '预览文件',
              47: '清空回收站',
              48: '共享标签变更',
              68: '锁定文件',
              69: '解锁文件',
              70: '管理员解锁'
            }[item['type']] ??
            '同步记录（${item['type'] ?? '—'}）';
    final text = widget.kind == 'clients'
        ? '${DisplayText.status(item['client_type'] ?? '')} · ${DisplayText.status(item['client_status'] ?? '')}\n${item['client_ip'] ?? ''} · 上次连接：${date(item['last_auth_time'])}'
        : '${item['user_name'] ?? item['username'] ?? ''} · ${date(item['time'] ?? item['timestamp'])}\n${item['s1'] ?? item['file_name'] ?? item['path'] ?? ''}';
    return Card(
        child: ListTile(
            title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(text),
            onTap: () => details(item, name),
            trailing: widget.kind == 'clients'
                ? IconButton(
                    tooltip: '断开客户端',
                    onPressed: busy || item['client_session_id'] == null
                        ? null
                        : () => disconnect(item),
                    icon: Icon(Icons.link_off))
                : Icon(Icons.chevron_right)));
  }

  static String date(dynamic value) {
    final number = value is num ? value : num.tryParse('$value');
    if (number == null) return '${value ?? '—'}';
    if (number <= 0 || number > 8640000000000) return '—';
    return DateTime.fromMillisecondsSinceEpoch((number * 1000).toInt())
        .toLocal()
        .toString()
        .split('.')
        .first;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(title), actions: [
        IconButton(
            tooltip: '刷新列表',
            icon: Icon(Icons.refresh),
            onPressed: busy ? null : () => load())
      ]),
      body: Column(children: [
        if (busy) LinearProgressIndicator(minHeight: 2),
        if (widget.kind == 'logs')
          Padding(
              padding: EdgeInsets.all(16),
              child: Column(children: [
                TextField(
                    onChanged: (v) => query = v,
                    onSubmitted: (_) => load(),
                    decoration: InputDecoration(
                        labelText: '搜索日志',
                        suffixIcon: IconButton(
                            tooltip: '搜索日志',
                            icon: Icon(Icons.search),
                            onPressed: busy ? null : () => load()))),
                SizedBox(height: 12),
                DropdownButtonFormField<int>(
                    value: logType,
                    decoration: InputDecoration(labelText: '日志类型'),
                    items: [
                      for (final e in const {
                        -1: '全部',
                        12: '客户端连接',
                        3: '客户端断开',
                        13: '新增文件',
                        15: '修改文件',
                        17: '重命名',
                        16: '版本轮换',
                        7: '版本设置'
                      }.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value))
                    ],
                    onChanged: busy
                        ? null
                        : (v) {
                            setState(() => logType = v);
                            load();
                          }),
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
                        WorkspaceEmpty('暂无记录', detail: '当前账号可见的记录会显示在这里。'),
                      ...rows.map(row),
                      if (more)
                        TextButton(
                            onPressed: busy ? null : () => load(next: true),
                            child: Text('加载更多')),
                    ])))
      ]));
}

class DriveShareEditor extends StatefulWidget {
  final DriveAdminApi api;
  final String name;
  const DriveShareEditor(this.api, this.name);
  @override
  State<DriveShareEditor> createState() => _DriveShareState();
}

class _DriveShareState extends State<DriveShareEditor> {
  bool busy = false,
      loaded = false,
      enabled = false,
      disableDownload = false,
      watermark = false,
      repeat = false;
  String policy = 'smart', error = '';
  Map original = {};
  final count = TextEditingController(),
      days = TextEditingController(),
      watermarkText = TextEditingController(),
      font = TextEditingController(),
      color = TextEditingController(),
      opacity = TextEditingController(),
      angle = TextEditingController(),
      fontSize = TextEditingController();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    for (final c in [
      count,
      days,
      watermarkText,
      font,
      color,
      opacity,
      angle,
      fontSize
    ]) c.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final r = await widget.api.share(widget.name);
      if (mounted)
        setState(() {
          original = r;
          loaded = true;
          enabled = r['share_enable'] == true;
          disableDownload = r['disable_download'] == true;
          watermark = r['enable_watermark'] == true;
          repeat = r['watermark_is_repeat'] == true;
          policy = const {'fifo', 'smart'}.contains(r['rotate_policy'])
              ? r['rotate_policy']
              : 'smart';
          count.text = '${num.tryParse('${r['rotate_cnt']}') ?? 0}';
          days.text = '${num.tryParse('${r['rotate_days']}') ?? 0}';
          watermarkText.text = '${r['watermark_text'] ?? ''}';
          font.text = '${r['watermark_font'] ?? ''}';
          color.text = '${r['watermark_font_color'] ?? '#808080'}';
          opacity.text = '${r['watermark_opacity_percent'] ?? 30}';
          angle.text = '${r['watermark_rotate_degree'] ?? 0}';
          fontSize.text = '${r['watermark_font_px_size'] ?? 24}';
          error = '';
        });
    } catch (e) {
      if (mounted) setState(() => error = driveError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(TextEditingController c, String title, {bool numeric = false}) =>
      Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: TextField(
              key: ValueKey('drive-share:$title'),
              controller: c,
              enabled: !busy,
              keyboardType: numeric ? TextInputType.number : null,
              decoration: InputDecoration(labelText: title)));
  Future<void> save() async {
    if (busy || !loaded) return;
    Map<String, dynamic> values;
    try {
      int integer(TextEditingController c, int min, int max, String label) {
        final value = int.tryParse(c.text);
        if (value == null || value < min || value > max)
          throw FormatException('$label：请输入 $min 至 $max 的整数');
        return value;
      }

      values = {
        'share_enable': enabled,
        'rotate_cnt': integer(count, 0, 32, '版本数量'),
        'rotate_days': integer(days, 0, 36500, '保留天数'),
        'rotate_policy': policy,
        'disable_download': disableDownload,
        'enable_watermark': watermark
      };
      if (watermark) {
        if (watermarkText.text.trim().isEmpty) throw FormatException('请输入水印内容');
        values.addAll({
          'watermark_text': watermarkText.text,
          'watermark_font': font.text,
          'watermark_font_color': color.text,
          'watermark_font_px_size': integer(fontSize, 1, 200, '字号'),
          'watermark_opacity_percent': integer(opacity, 0, 100, '水印不透明度'),
          'watermark_rotate_degree': integer(angle, 0, 359, '旋转角度'),
          'watermark_is_repeat': repeat
        });
      }
      values.removeWhere((key, value) => original[key] == value);
      if (values.isEmpty) {
        Navigator.pop(context);
        return;
      }
    } catch (e) {
      setState(() => error = driveError(e));
      return;
    }
    if (!await confirmDrive(context, '保存团队文件夹设置',
            '将修改“${widget.name}”的同步、版本或文件保护设置。停用同步或减少版本数量、保留天数可能清理历史版本，是否继续？') ||
        !mounted) return;
    setState(() => busy = true);
    try {
      await widget.api.saveShare(widget.name, values);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = driveError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      bottomNavigationBar: SafeArea(
          child: Padding(
              padding: EdgeInsets.all(16),
              child: ElevatedButton(
                  onPressed: busy || !loaded ? null : save,
                  child: Text('保存设置')))),
      body: ListView(padding: EdgeInsets.all(20), children: [
        if (busy) LinearProgressIndicator(minHeight: 2),
        if (error.isNotEmpty)
          Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(error,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
        if (!loaded && !busy) TextButton(onPressed: load, child: Text('重新加载')),
        if (loaded) ...[
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('启用同步'),
              subtitle: const {'home', 'homes'}.contains(widget.name)
                  ? Text('个人空间由 DSM 家目录服务管理')
                  : null,
              value: enabled,
              onChanged: busy || const {'home', 'homes'}.contains(widget.name)
                  ? null
                  : (v) => setState(() => enabled = v)),
          field(count, '版本数量（0 表示不保留版本）', numeric: true),
          field(days, '版本保留天数（0 表示不限）', numeric: true),
          DropdownButtonFormField<String>(
              value: policy,
              decoration: InputDecoration(labelText: '版本保留策略'),
              items: [
                DropdownMenuItem(value: 'fifo', child: Text('先入先出')),
                DropdownMenuItem(value: 'smart', child: Text('智能版本控制'))
              ],
              onChanged: busy ? null : (v) => setState(() => policy = v)),
          SizedBox(height: 16),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('禁止下载和复制文件'),
              subtitle: Text('高级文件保护设置可能要求先激活高级功能'),
              value: disableDownload,
              onChanged:
                  busy ? null : (v) => setState(() => disableDownload = v)),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('启用水印'),
              value: watermark,
              onChanged: busy ? null : (v) => setState(() => watermark = v)),
          if (watermark) ...[
            field(watermarkText, '水印内容'),
            field(font, '水印字体'),
            field(fontSize, '水印字号', numeric: true),
            field(color, '水印颜色'),
            field(opacity, '不透明度（0 至 100）', numeric: true),
            field(angle, '旋转角度（0 至 359）', numeric: true),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('重复水印'),
                value: repeat,
                onChanged: busy ? null : (v) => setState(() => repeat = v))
          ],
        ]
      ]));
}

class DriveActivationPage extends StatefulWidget {
  final DriveAdminApi api;
  const DriveActivationPage(this.api);
  @override
  State<DriveActivationPage> createState() => _DriveActivationState();
}

class _DriveActivationState extends State<DriveActivationPage> {
  Map data = {};
  String error = '';
  bool busy = false;
  final code = TextEditingController();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final d = await widget.api.activation();
      if (mounted)
        setState(() {
          data = d;
          error = '';
        });
    } catch (e) {
      if (mounted) setState(() => error = driveError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> activate() async {
    if (busy) return;
    if (!await confirmDrive(context, '激活高级功能', '使用输入的合法激活码向当前 NAS 提交激活请求？') ||
        !mounted) return;
    setState(() => busy = true);
    try {
      await widget.api.activate(code.text);
      code.clear();
    } catch (e) {
      if (mounted) setState(() => error = driveError(e));
      return;
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('高级功能'), actions: [
        IconButton(
            tooltip: '刷新激活状态',
            icon: Icon(Icons.refresh),
            onPressed: busy ? null : load)
      ]),
      body: ListView(padding: EdgeInsets.all(20), children: [
        if (busy) LinearProgressIndicator(minHeight: 2),
        Text(data['activated'] == true ? '高级功能已激活' : '高级功能未激活',
            style: Theme.of(context).textTheme.headline6),
        SizedBox(height: 16),
        NativeProperties(data),
        if (data['activated'] != true) ...[
          TextField(
              controller: code,
              obscureText: true,
              enabled: !busy,
              decoration: InputDecoration(labelText: '高级功能激活码')),
          SizedBox(height: 16),
          ElevatedButton(onPressed: busy ? null : activate, child: Text('提交激活'))
        ],
        if (error.isNotEmpty)
          Text(error,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]));
}

class DriveSettingsPage extends StatefulWidget {
  final DriveAdminApi api;
  const DriveSettingsPage(this.api);
  @override
  State<DriveSettingsPage> createState() => _DriveSettingsState();
}

class _DriveSettingsState extends State<DriveSettingsPage> {
  Map settings = {}, config = {}, originalSettings = {}, originalConfig = {};
  bool busy = false;
  String error = '';
  static const labels = {
    'default_enable_full_content_indexing': '默认建立全文索引',
    'enable_c2share_offload': '启用混合云共享卸载',
    'enable_normal_user_sharing': '允许普通用户共享',
    'enable_public_sharing': '允许公开共享',
    'file_request_enabled': '启用文件请求',
    'file_request_force_password': '文件请求必须设置密码',
    'force_https_sharing_link': '共享链接强制使用 HTTPS',
    'sharing_force_password': '共享链接必须设置密码',
    'enable_non_admin_user_sync': '允许非管理员同步',
    'enable_vmtouch': '启用文件缓存',
    'use_del_by_cnt': '按日志数量保留记录',
    'use_del_by_span': '按日志天数保留记录',
    'file_request_link_by_email': '允许通过邮件发送文件请求',
    'sharing_link_by_email': '允许通过邮件发送共享链接',
    'enable_sharing_link_customization': '自定义共享链接'
  };
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final values =
          await Future.wait([widget.api.settings(), widget.api.config()]);
      if (mounted)
        setState(() {
          settings = Map.from(values[0]);
          config = Map.from(values[1]);
          config['db_volume'] = config['volume_select'];
          originalSettings = Map.from(settings);
          originalConfig = Map.from(config);
          error = '';
        });
    } catch (e) {
      if (mounted) setState(() => error = driveError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    final a = <String, dynamic>{
          for (final k in DriveAdminApi.settingBools)
            if (settings[k] is bool && settings[k] != originalSettings[k])
              k: settings[k],
          if (settings['sharing_level'] != originalSettings['sharing_level'])
            'sharing_level': settings['sharing_level']
        },
        b = <String, dynamic>{
          for (final k in DriveAdminApi.configFields)
            if (config[k] != null && config[k] != originalConfig[k])
              k: config[k]
        };
    if (busy || a.isEmpty && b.isEmpty) return;
    if (!await confirmDrive(context, '保存 Drive 设置',
            '将更新当前 NAS 的 Drive 全局设置，可能影响所有用户的同步、索引和共享权限。移动数据库可能暂时中断服务，缩短日志保留策略可能清理旧记录。是否继续？') ||
        !mounted) return;
    setState(() => busy = true);
    String failure;
    try {
      if (a.isNotEmpty) await widget.api.saveSettings(a);
      if (b.isNotEmpty) await widget.api.saveSettings(b, serverConfig: true);
    } catch (e) {
      failure = driveError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) {
      await load();
      if (failure != null && mounted)
        setState(() => error = '部分设置可能已保存，请核对当前值：$failure');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('Drive 设置'), actions: [
        IconButton(
            tooltip: '刷新设置',
            icon: Icon(Icons.refresh),
            onPressed: busy ? null : load)
      ]),
      bottomNavigationBar: SafeArea(
          child: Padding(
              padding: EdgeInsets.all(16),
              child: ElevatedButton(
                  onPressed: busy ? null : save, child: Text('保存更改')))),
      body: ListView(padding: EdgeInsets.all(16), children: [
        if (busy) LinearProgressIndicator(minHeight: 2),
        if (error.isNotEmpty)
          Text(error,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if ((config['volume_list'] as List ?? [])
            .whereType<Map>()
            .any((v) => v['mount_point'] == config['db_volume']))
          Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: DropdownButtonFormField<String>(
                  value: config['db_volume'],
                  isExpanded: true,
                  decoration: InputDecoration(labelText: '数据库位置'),
                  items: [
                    for (final v in (config['volume_list'] as List ?? [])
                        .whereType<Map>())
                      DropdownMenuItem(
                          value: '${v['mount_point']}',
                          child: Text('${v['display'] ?? v['mount_point']}'))
                  ],
                  onChanged: busy || config['support_moving_repository'] != true
                      ? null
                      : (v) => setState(() => config['db_volume'] = v))),
        if (const {'disallow', 'internal', 'public'}
            .contains(settings['sharing_level']))
          Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: DropdownButtonFormField<String>(
                  value: settings['sharing_level'],
                  decoration: InputDecoration(labelText: '共享权限'),
                  items: [
                    DropdownMenuItem(value: 'disallow', child: Text('禁止共享')),
                    DropdownMenuItem(value: 'internal', child: Text('仅内部共享')),
                    DropdownMenuItem(value: 'public', child: Text('允许公开共享'))
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => settings['sharing_level'] = v))),
        for (final group in [settings, config])
          for (final k in group.keys)
            if (labels.containsKey(k) &&
                group[k] is bool &&
                (identical(group, settings)
                        ? DriveAdminApi.settingBools
                        : DriveAdminApi.configBools)
                    .contains(k))
              Card(
                  child: SwitchListTile(
                      title: Text(labels[k]),
                      value: group[k],
                      onChanged:
                          busy ? null : (v) => setState(() => group[k] = v))),
        for (final key in const ['del_cnt', 'del_span'])
          if (config[key] is num)
            Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: DropdownButtonFormField<int>(
                    value: (config[key] as num).toInt(),
                    decoration: InputDecoration(
                        labelText: key == 'del_cnt' ? '日志数量上限' : '日志保留时间'),
                    items: [
                      for (final value in {
                        ...(key == 'del_cnt'
                            ? DriveAdminApi.logCounts
                            : DriveAdminApi.logSpans),
                        (config[key] as num).toInt()
                      })
                        DropdownMenuItem(
                            value: value,
                            child: Text(key == 'del_cnt'
                                ? '$value 条'
                                : '${value ~/ 86400} 天'))
                    ],
                    onChanged:
                        busy ? null : (v) => setState(() => config[key] = v))),
        ExpansionTile(
            title: Text('完整配置详情'),
            children: [NativeProperties(settings), NativeProperties(config)]),
      ]));
}
