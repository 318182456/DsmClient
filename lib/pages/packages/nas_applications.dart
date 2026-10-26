import 'dart:convert';

import 'package:dsm_client/models/nas_package.dart';
import 'package:dsm_client/pages/common/browser.dart';
import 'package:dsm_client/pages/docker/detail.dart';
import 'package:dsm_client/pages/docker/docker.dart';
import 'package:dsm_client/pages/file/file.dart';
import 'package:dsm_client/pages/photos/photos.dart';
import 'package:dsm_client/pages/storage_manager/storage_manager.dart';
import 'package:dsm_client/util/dsm_compatibility.dart';
import 'package:dsm_client/util/function.dart';
import 'package:dsm_client/widgets/neu_back_button.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

class NasApplications extends StatefulWidget {
  final List desktopApps;
  const NasApplications({this.desktopApps = const [], Key key})
      : super(key: key);

  @override
  State<NasApplications> createState() => _NasApplicationsState();
}

class _NasApplicationsState extends State<NasApplications> {
  List<NasPackage> packages = [];
  List<Map> containers = [];
  Map<String, String> links = {};
  String query = '';
  String packageError = '';
  String containerError = '';
  bool loading = true;

  String get linkKey =>
      'nas_app_links_${Uri.encodeComponent(DsmCompatibility.connectionKey(Util.baseUrl))}';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    try {
      final stored = await Util.getStorage(linkKey);
      if ((stored ?? '').isNotEmpty) {
        links = Map<String, String>.from(jsonDecode(stored));
      }
    } catch (_) {
      links = {};
    }
    final results = await Future.wait([
      _safe(Api.nasPackages()),
      _safe(Api.nasContainers()),
    ]);
    if (!mounted) return;
    setState(() {
      final packageResult = results[0] ?? {};
      final containerResult = results[1] ?? {};
      packageError = _error(packageResult, '套件');
      containerError = _error(containerResult, '容器');
      packages = ((packageResult['data'] ?? {})['packages'] as List ?? [])
          .whereType<Map>()
          .map((value) => NasPackage.fromJson(value))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      containers = ((containerResult['data'] ?? {})['containers'] as List ?? [])
          .whereType<Map>()
          .toList()
        ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
      loading = false;
    });
  }

  Future<Map> _safe(Future<Map> request) async {
    try {
      return await request;
    } catch (_) {
      return {
        'success': false,
        'error': {'code': '连接异常'}
      };
    }
  }

  String _error(Map result, String kind) {
    if (result['success'] == true) return '';
    final code = (result['error'] ?? {})['code'];
    if (code == 102) return '此设备未提供$kind服务';
    if (code == 105) return '当前账号无权查看$kind列表';
    return '$kind列表加载失败${code == null ? '' : '（$code）'}';
  }

  bool _matches(String name) =>
      name.toLowerCase().contains(query.toLowerCase());

  String _status(String value) {
    if (value == 'running') return '运行中';
    if (value == 'stopped' || value == 'stop' || value == 'exited')
      return '已停止';
    return value == 'unknown' ? '状态未知' : value;
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _openDsm(String appId, String title) {
    final base = Uri.parse(Util.baseUrl);
    final uri = base.replace(
      path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}/',
      queryParameters: {'launchApp': appId},
      fragment: '',
    );
    _open(Browser(url: uri.toString(), title: title, useNasSession: true));
  }

  Widget _native(NasPackage package) {
    switch (package.id) {
      case 'FileStation':
        return Files();
      case 'ContainerManager':
        return Docker(title: 'Container Manager');
      case 'Docker':
        return Docker();
      case 'SynologyPhotos':
        return Photos();
      case 'StorageManager':
        return StorageManager();
      default:
        return null;
    }
  }

  Future<void> _editLink(String key, String title) async {
    final controller = TextEditingController(text: links[key] ?? '');
    final value = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text('$title 网页地址'),
              content: TextField(
                controller: controller,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                    hintText: 'https://example.com',
                    helperText: '使用已配置的访问地址，留空可删除'),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text('取消')),
                TextButton(
                    onPressed: () {
                      final value = controller.text.trim();
                      final uri = Uri.tryParse(value);
                      if (value.isNotEmpty &&
                          (uri == null ||
                              !['http', 'https'].contains(uri.scheme) ||
                              uri.host.isEmpty ||
                              uri.userInfo.isNotEmpty)) {
                        Util.toast('请输入有效的 HTTP/HTTPS 地址，地址中不要包含账号密码');
                        return;
                      }
                      Navigator.pop(dialogContext, value);
                    },
                    child: Text('保存')),
              ],
            ));
    controller.dispose();
    if (value == null || !mounted) return;
    setState(() {
      if (value.isEmpty) {
        links.remove(key);
      } else {
        links[key] = value;
      }
    });
    await Util.setStorage(linkKey, jsonEncode(links));
  }

  void _package(NasPackage package) {
    final native = _native(package);
    final apps = package.launchApps(widget.desktopApps);
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (sheet) => SafeArea(
                child: SingleChildScrollView(
                    child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(package.name,
                      style: Theme.of(context).textTheme.headline6),
                  SizedBox(height: 8),
                  Text('${package.version} · ${_status(package.status)}'),
                  SizedBox(height: 16),
                  Text(package.description.replaceAll(RegExp(r'<[^>]*>'), '')),
                  if (native != null)
                    ListTile(
                      leading: Icon(Icons.phone_android),
                      title: Text('在 DsmClient 中打开'),
                      onTap: () {
                        Navigator.pop(sheet);
                        _open(native);
                      },
                    ),
                  ...apps.map((app) => ListTile(
                        leading: Icon(Icons.open_in_browser),
                        title: Text(apps.length == 1
                            ? '打开 DSM 套件界面'
                            : (app == 'SYNO.SDS.Drive.Application'
                                ? '打开 Drive 文件'
                                : app == 'SYNO.SDS.CSTN.Instance'
                                    ? '打开 Drive 管理控制台'
                                    : app ==
                                            'SYNO.SDS.SynologyDriveShareSync.Instance'
                                        ? '打开 Drive ShareSync'
                                        : '打开 ${package.name}')),
                        onTap: () {
                          Navigator.pop(sheet);
                          _openDsm(app, package.name);
                        },
                      )),
                  if (apps.isEmpty && native == null)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('此套件未提供可用的独立桌面入口，可在套件中心查看与管理。'),
                    ),
                  ListTile(
                      leading: Icon(Icons.apps),
                      title: Text('打开 DSM 套件中心'),
                      onTap: () {
                        Navigator.pop(sheet);
                        _openDsm('SYNO.SDS.PkgManApp.Instance', '套件中心');
                      }),
                ],
              ),
            ))));
  }

  Widget _empty(String error) => ListView(children: [
        Padding(
          padding: EdgeInsets.all(32),
          child: Text(error.isNotEmpty ? error : '没有匹配的应用'),
        )
      ]);

  @override
  Widget build(BuildContext context) {
    final shownPackages =
        packages.where((item) => _matches('${item.name} ${item.id}')).toList();
    final shownContainers = containers
        .where((item) => _matches('${item['name']} ${item['image']}'))
        .toList();
    return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            leading: AppBackButton(context),
            title: Text('NAS 应用'),
            actions: [
              IconButton(
                  icon: Icon(Icons.refresh), onPressed: loading ? null : load)
            ],
            bottom: TabBar(tabs: [
              Tab(text: '套件 (${packages.length})'),
              Tab(text: '容器 (${containers.length})')
            ]),
          ),
          body: Column(children: [
            Padding(
                padding: EdgeInsets.all(16),
                child: TextField(
                  onChanged: (value) => setState(() => query = value),
                  decoration: InputDecoration(
                      prefixIcon: Icon(Icons.search), hintText: '搜索应用、套件或容器'),
                )),
            Expanded(
                child: loading
                    ? Center(child: CircularProgressIndicator())
                    : TabBarView(children: [
                        RefreshIndicator(
                            onRefresh: load,
                            child: shownPackages.isEmpty
                                ? _empty(packageError)
                                : ListView.builder(
                                    itemCount: shownPackages.length,
                                    itemBuilder: (_, index) {
                                      final item = shownPackages[index];
                                      return ListTile(
                                          leading: Icon(_native(item) != null
                                              ? Icons.apps
                                              : Icons.inventory_2_outlined),
                                          title: Text(item.name),
                                          subtitle: Text(
                                              '${item.version} · ${_status(item.status)}'),
                                          trailing: Icon(Icons.chevron_right),
                                          onTap: () => _package(item));
                                    })),
                        RefreshIndicator(
                            onRefresh: load,
                            child: shownContainers.isEmpty
                                ? _empty(containerError)
                                : ListView.builder(
                                    itemCount: shownContainers.length,
                                    itemBuilder: (_, index) {
                                      final item = shownContainers[index];
                                      final key = 'container:${item['name']}';
                                      return Card(
                                          margin: EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 6),
                                          child: Column(children: [
                                            ListTile(
                                                leading: Icon(Icons.view_in_ar),
                                                title: Text('${item['name']}'),
                                                subtitle: Text(_status(
                                                    '${item['status'] ?? item['state'] ?? 'unknown'}')),
                                                trailing:
                                                    Icon(Icons.chevron_right),
                                                onTap: () => _open(
                                                    ContainerDetail(
                                                        '${item['name']}'))),
                                            ButtonBar(children: [
                                              if (links.containsKey(key))
                                                TextButton.icon(
                                                    icon: Icon(
                                                        Icons.open_in_browser),
                                                    label: Text('打开网页'),
                                                    onPressed: () =>
                                                        launchUrlString(
                                                            links[key],
                                                            mode: LaunchMode
                                                                .externalApplication)),
                                              TextButton(
                                                  onPressed: () => _editLink(
                                                      key, '${item['name']}'),
                                                  child: Text(
                                                      links.containsKey(key)
                                                          ? '修改网页地址'
                                                          : '设置网页地址')),
                                            ]),
                                          ]));
                                    })),
                      ])),
          ]),
        ));
  }
}
