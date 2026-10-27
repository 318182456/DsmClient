import 'package:dsm_client/models/nas_package.dart';
import 'package:dsm_client/models/program_capabilities.dart';
import 'package:dsm_client/widgets/nas_app_icon.dart';
import 'package:dsm_client/pages/packages/program_page.dart';
import 'package:dsm_client/pages/control_panel/control_panel.dart';
import 'package:dsm_client/pages/docker/workspace.dart';
import 'package:dsm_client/pages/download_station/download_station.dart';
import 'package:dsm_client/pages/file/file.dart';
import 'package:dsm_client/pages/log_center/log_center.dart';
import 'package:dsm_client/pages/moments/moments.dart';
import 'package:dsm_client/pages/packages/packages.dart';
import 'package:dsm_client/pages/packages/program_launcher.dart';
import 'package:dsm_client/pages/photos/photos.dart';
import 'package:dsm_client/pages/resource_monitor/resource_monitor.dart';
import 'package:dsm_client/pages/security_scan/security_scan.dart';
import 'package:dsm_client/pages/storage_manager/storage_manager.dart';
import 'package:dsm_client/pages/virtual_machine/virtual_machine.dart';
import 'package:dsm_client/util/function.dart';
import 'package:flutter/material.dart';
import 'package:dsm_client/util/program_pins.dart';
import 'package:dsm_client/util/program_catalog_cache.dart';
import 'package:dsm_client/widgets/service_app_icon.dart';
import 'package:dsm_client/pages/packages/drive_console.dart';

class ApplicationList extends StatefulWidget {
  final List applications;
  final Map system;
  final List volumes, disks;
  final Map appNotify;
  final Future<Map> Function() packageLoader, containerLoader;
  final bool pinnedOnly, selectForHome;
  final bool useCatalogCache;
  const ApplicationList(
      this.applications, this.system, this.volumes, this.disks, this.appNotify,
      {Key key,
      this.packageLoader,
      this.containerLoader,
      this.pinnedOnly = false,
      this.useCatalogCache,
      this.selectForHome = false})
      : super(key: key);
  @override
  State<ApplicationList> createState() => _ApplicationListState();
}

class _MenuApp {
  final String id, title, asset;
  final IconData icon;
  final Widget Function() page;
  final NasPackage package;
  final List<String> iconApps;
  final String caption;
  final String service, nasIcon;
  _MenuApp(this.id, this.title, this.icon, this.page,
      {this.asset,
      this.package,
      this.iconApps,
      this.caption,
      this.service,
      this.nasIcon});
}

class _ApplicationListState extends State<ApplicationList> {
  List<NasPackage> packages = [];
  List<Map> containers = [];
  String query = '', error = '', connection;
  bool loading = true;
  int generation = 0;
  List<String> pins = [];
  bool catalogLoaded = false;
  bool refreshing = false;
  bool get cacheEnabled =>
      widget.useCatalogCache ??
      (widget.packageLoader == null && widget.containerLoader == null);
  bool pinsLoaded = false, saving = false;
  String selectionScope;
  @override
  void initState() {
    super.initState();
    connection = '${Util.baseUrl}|${Util.sid}|${Util.account}';
    selectionScope = ProgramPins.key;
    if (!widget.selectForHome) ProgramPins.changed.addListener(readPins);
    readPins();
    if (!widget.pinnedOnly) load();
  }

  @override
  void dispose() {
    if (!widget.selectForHome) ProgramPins.changed.removeListener(readPins);
    super.dispose();
  }

  Future<void> readPins() async {
    try {
      final scope = ProgramPins.key;
      final value = await ProgramPins.read(scope);
      if (!mounted || scope != ProgramPins.key) return;
      setState(() {
        pins = value;
        pinsLoaded = true;
        if (widget.pinnedOnly && pins.isEmpty) loading = false;
      });
      if (widget.pinnedOnly && pins.isNotEmpty && !catalogLoaded) load();
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  void openHomePicker() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
            appBar: AppBar(title: Text('选择常用程序')),
            body: ApplicationList(widget.applications, widget.system,
                widget.volumes, widget.disks, widget.appNotify,
                selectForHome: true,
                packageLoader: widget.packageLoader,
                containerLoader: widget.containerLoader,
                useCatalogCache: widget.useCatalogCache))));
  }

  Future<void> saveHomeSelection() async {
    if (saving || !pinsLoaded) return;
    setState(() => saving = true);
    try {
      await ProgramPins.replace(pins, scope: selectionScope);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted)
        setState(() {
          saving = false;
          error = '快捷方式保存失败，请确认 NAS 账号后重试';
        });
    }
  }

  Future<void> pinMenu(_MenuApp app) async {
    final pinned = pins.contains(app.id);
    final action = await showModalBottomSheet<String>(
        context: context,
        builder: (sheet) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(title: Text(app.title), subtitle: Text('控制台首页快捷方式')),
              ListTile(
                  leading: Icon(pinned ? Icons.star_border : Icons.star),
                  title: Text(pinned ? '从首页移除' : '添加到首页'),
                  onTap: () => Navigator.pop(sheet, 'toggle')),
              if (widget.pinnedOnly) ...[
                ListTile(
                    leading: Icon(Icons.arrow_back),
                    title: Text('向前移动'),
                    onTap: () => Navigator.pop(sheet, 'previous')),
                ListTile(
                    leading: Icon(Icons.arrow_forward),
                    title: Text('向后移动'),
                    onTap: () => Navigator.pop(sheet, 'next')),
              ]
            ])));
    if (action == null || !mounted) return;
    try {
      if (action == 'toggle')
        await ProgramPins.toggle(app.id);
      else
        await ProgramPins.move(app.id, action == 'previous' ? -1 : 1);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(action == 'toggle'
                ? (pinned ? '已从首页移除' : '已添加到首页')
                : '顺序已更新')));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('快捷方式保存失败，请重试')));
    }
  }

  Widget appIcon(_MenuApp app) => app.service != null
      ? ServiceAppIcon(app.service, nasIcon: app.nasIcon)
      : app.package != null
          ? NasAppIcon(app.package,
              appIds: app.iconApps, fallbackAsset: app.asset)
          : app.asset != null
              ? Image.asset(app.asset,
                  width: 40,
                  height: 40,
                  errorBuilder: (_, __, ___) => Icon(app.icon, size: 40))
              : Icon(app.icon, size: 40);
  Widget pinnedHome() {
    final catalog = {for (final app in entries) app.id: app};
    final apps =
        pins.where(catalog.containsKey).map((id) => catalog[id]).toList();
    return Card(
        margin: EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Padding(
            padding: EdgeInsets.all(12),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text('常用程序',
                            style: Theme.of(context).textTheme.subtitle1)),
                    TextButton(onPressed: openHomePicker, child: Text('添加'))
                  ]),
                  if (loading) LinearProgressIndicator(minHeight: 2),
                  if (apps.isEmpty && !loading)
                    Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('点击“添加”选择常用程序。',
                            style: Theme.of(context).textTheme.caption)),
                  if (apps.isNotEmpty)
                    SizedBox(
                        height: 130 * MediaQuery.of(context).textScaleFactor,
                        child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: apps
                                .map((app) => SizedBox(
                                    width: 112,
                                    child: InkWell(
                                        key: ValueKey(
                                            'pinned-program:${app.id}'),
                                        onLongPress: () => pinMenu(app),
                                        onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) => app.page(),
                                                settings: RouteSettings(
                                                    name: app.id))),
                                        child: Padding(
                                            padding: EdgeInsets.all(8),
                                            child: Column(children: [
                                              SizedBox(
                                                  height: 44,
                                                  child: appIcon(app)),
                                              SizedBox(height: 10),
                                              Text(app.title,
                                                  maxLines: 2,
                                                  textAlign: TextAlign.center,
                                                  overflow:
                                                      TextOverflow.ellipsis)
                                            ])))))
                                .toList())),
                ])));
  }

  @override
  void didUpdateWidget(ApplicationList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (connection != '${Util.baseUrl}|${Util.sid}|${Util.account}') {
      connection = '${Util.baseUrl}|${Util.sid}|${Util.account}';
      catalogLoaded = false;
      packages = [];
      containers = [];
      refreshing = false;
      pins = [];
      readPins();
      if (!widget.pinnedOnly) load();
    }
  }

  Future<Map> safe(Future<Map> request) async {
    try {
      return await request;
    } catch (_) {
      return {'success': false};
    }
  }

  Future<void> load({bool force = false}) async {
    final current = ++generation;
    final scope = ProgramCatalogCache.scope;
    connection = '${Util.baseUrl}|${Util.sid}|${Util.account}';
    if (cacheEnabled && !force) {
      final cached = await ProgramCatalogCache.read(scope);
      if (!mounted ||
          generation != current ||
          scope != ProgramCatalogCache.scope) return;
      if (cached != null)
        setState(() {
          packages = (cached['packages'] as List)
              .whereType<Map>()
              .map((p) => NasPackage.fromJson(p))
              .toList();
          containers = (cached['containers'] as List).whereType<Map>().toList();
          catalogLoaded = true;
          loading = false;
        });
      if (cached != null && ProgramCatalogCache.fresh(cached)) return;
    }
    setState(() {
      loading = !catalogLoaded;
      refreshing = catalogLoaded;
      error = '';
    });
    final result = await Future.wait([
      safe((widget.packageLoader ?? Api.nasPackages)()),
      safe((widget.containerLoader ?? Api.nasContainers)()),
    ]);
    if (!mounted ||
        generation != current ||
        connection != '${Util.baseUrl}|${Util.sid}|${Util.account}' ||
        scope != ProgramCatalogCache.scope) return;
    setState(() {
      if (result[0]['success'] == true)
        packages = ((result[0]['data'] ?? {})['packages'] as List ?? [])
            .whereType<Map>()
            .map((p) => NasPackage.fromJson(p))
            .toList()
          ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (result[1]['success'] == true)
        containers = ((result[1]['data'] ?? {})['containers'] as List ?? [])
            .whereType<Map>()
            .toList()
          ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
      if (result[0]['success'] != true) error = '套件列表加载失败';
      if (result[1]['success'] != true &&
          (result[1]['error'] ?? {})['code'] != 102)
        error += '${error.isEmpty ? '' : '；'}容器列表加载失败';
      loading = false;
      refreshing = false;
      catalogLoaded = true;
    });
    if (cacheEnabled &&
        result[0]['success'] == true &&
        (result[1]['success'] == true ||
            (result[1]['error'] ?? {})['code'] == 102))
      await ProgramCatalogCache.save(scope, packages, containers);
  }

  List<_MenuApp> get entries {
    final result = <_MenuApp>[];
    final installed = packages.map((p) => p.id).toSet();
    final desktop = (widget.applications ?? []).toSet();
    void core(String id, String title, String asset, Widget Function() page) {
      if (desktop.contains(id))
        result.add(_MenuApp(id, title, Icons.apps, page,
            asset: 'assets/applications/${Util.version}/$asset.png'));
    }

    core(
        'SYNO.SDS.PkgManApp.Instance',
        '套件中心',
        'package_center',
        () => Packages(
            (widget.system ?? {})['firmware_ver'] ?? 'DSM 7.4.1-90080'));
    core(
        'SYNO.SDS.AdminCenter.Application',
        '控制面板',
        'control_panel',
        () => ControlPanel(
            widget.system,
            widget.volumes,
            widget.disks,
            (widget.appNotify ?? {})['SYNO.SDS.AdminCenter.Application'] == null
                ? null
                : widget.appNotify['SYNO.SDS.AdminCenter.Application']['fn']));
    core('SYNO.SDS.StorageManager.Instance', '存储空间管理员', 'storage_manager',
        () => StorageManager());
    core('SYNO.SDS.ResourceMonitor.Instance', '资源监控', 'resource_monitor',
        () => ResourceMonitor());
    core('SYNO.SDS.SecurityScan.Instance', '安全顾问', 'security_scan',
        () => SecurityScan());
    if (desktop.contains('SYNO.SDS.LogCenter.BuiltIn') ||
        desktop.contains('SYNO.SDS.LogCenter.Instance'))
      result.add(_MenuApp(
          'LogCenter', '日志中心', Icons.list_alt, () => LogCenter(),
          asset: 'assets/applications/${Util.version}/log_center.png'));
    for (final package in packages) {
      if (ProgramCapabilities.isDependency(package.id)) continue;
      if (!ProgramCapabilities.hasWorkspace(package.id) &&
          package.launchApps(widget.applications ?? []).isEmpty) continue;
      if (package.id == 'StorageManager' &&
          desktop.contains('SYNO.SDS.StorageManager.Instance')) continue;
      result.add(_MenuApp('package:${package.id}', package.name,
          programIcon(package.id), () => nativeProgram(package),
          package: package,
          asset: {
            'SMBService':
                'assets/control_panel/${Util.version}/file_services.png',
            'ContainerManager': 'assets/applications/container_manager.png',
            'Docker': 'assets/applications/docker.png',
            'StorageManager':
                'assets/applications/${Util.version}/storage_manager.png',
            'Virtualization':
                'assets/applications/${Util.version}/virtual_machine.png',
            'DownloadStation': 'assets/applications/download_station.png'
          }[package.id],
          caption:
              ProgramCapabilities.hasWorkspace(package.id) ? null : '套件管理'));
      if (package.id == 'SynologyDrive')
        result.add(_MenuApp('package:SynologyDrive:console', 'Drive 控制台',
            Icons.cloud, () => DriveConsole(package),
            package: package, iconApps: ['SYNO.SDS.CSTN.Instance']));
    }
    if (!installed.contains('FileStation'))
      result.add(_MenuApp(
          'FileStation', 'File Station', Icons.folder, () => Files(),
          package: NasPackage.fromJson(
              {'id': 'FileStation', 'name': 'File Station'})));
    if (!installed.contains('SynologyPhotos') &&
        desktop.contains('SYNO.Foto.AppInstance'))
      result.add(_MenuApp(
          'Photos', 'Synology Photos', Icons.photo_library, () => Photos(),
          asset: 'assets/applications/7/synology_photos.png'));
    if (desktop.contains('SYNO.Photo.AppInstance'))
      result.add(_MenuApp('Moments', 'Moments', Icons.photo, () => Moments(),
          asset: 'assets/applications/6/moments.png'));
    if (desktop.contains('SYNO.SDS.DownloadStation.Application') &&
        !installed.contains('DownloadStation'))
      result.add(_MenuApp('DownloadStation', 'Download Station', Icons.download,
          () => DownloadStation(),
          asset: 'assets/applications/download_station.png'));
    if (desktop.contains('SYNO.SDS.Virtualization.Application') &&
        !installed.contains('Virtualization'))
      result.add(_MenuApp('Virtualization', 'Virtual Machine Manager',
          Icons.computer, () => VirtualMachine(),
          asset: 'assets/applications/${Util.version}/virtual_machine.png'));
    if (!installed.contains('ContainerManager') &&
        !installed.contains('Docker') &&
        (desktop.contains('SYNO.SDS.ContainerManager.Application') ||
            desktop.contains('SYNO.SDS.Docker.Application')))
      result.add(_MenuApp('ContainerManager', 'Container Manager',
          Icons.view_in_ar, () => DockerWorkspace(),
          asset: 'assets/applications/container_manager.png'));
    for (final container in containers) {
      final name = '${container['name']}';
      if (!ProgramCapabilities.hasContainerWorkspace(
          name, '${container['image'] ?? ''}')) continue;
      final managers =
          packages.where((p) => p.id == 'ContainerManager' || p.id == 'Docker');
      result.add(_MenuApp('container:$name', name, Icons.view_in_ar_outlined,
          () => nativeContainer(name, image: '${container['image'] ?? ''}'),
          service: ServiceAppIcon.identify(name, '${container['image'] ?? ''}'),
          nasIcon: container['icon'] is String ? container['icon'] : null,
          package: managers.isEmpty ? null : managers.first,
          asset: 'assets/applications/container_manager.png'));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pinnedOnly) return pinnedHome();
    final shown = entries
        .where((a) =>
            '${a.title} ${a.id}'.toLowerCase().contains(query.toLowerCase()))
        .toList();
    final panelWidth =
        MediaQuery.of(context).size.width * (widget.selectForHome ? 1 : .8);
    return Container(
        width: panelWidth,
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
            child: Column(children: [
          if (widget.selectForHome)
            Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text('点击卡片勾选程序，保存后显示在控制台首页。',
                    style: Theme.of(context).textTheme.caption)),
          Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 12, 16),
              child: Row(children: [
                Expanded(
                    child: TextField(
                        onChanged: (v) => setState(() => query = v),
                        decoration: InputDecoration(
                            prefixIcon: Icon(Icons.search), hintText: '搜索程序'))),
                IconButton(
                    icon: Icon(Icons.refresh),
                    onPressed:
                        loading || refreshing ? null : () => load(force: true)),
                if (widget.selectForHome)
                  TextButton(
                      onPressed:
                          saving ? null : () => setState(() => pins = []),
                      child: Text('清空')),
              ])),
          if (loading || refreshing) LinearProgressIndicator(),
          if (error.isNotEmpty)
            Padding(padding: EdgeInsets.all(12), child: Text('$error，点击刷新重试')),
          Expanded(
              child: ListView(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: [
                Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    children: shown
                        .map((app) => Semantics(
                            key: ValueKey('program-card:${app.id}'),
                            button: true,
                            selected: widget.selectForHome
                                ? pins.contains(app.id)
                                : null,
                            label: app.title,
                            child: GestureDetector(
                                onLongPress: widget.selectForHome
                                    ? null
                                    : () => pinMenu(app),
                                onTap: () {
                                  if (widget.selectForHome) {
                                    if (!pinsLoaded || saving) return;
                                    setState(() {
                                      if (pins.contains(app.id))
                                        pins.remove(app.id);
                                      else
                                        pins.add(app.id);
                                    });
                                    return;
                                  }
                                  final navigator = Navigator.of(context);
                                  navigator.pop();
                                  navigator.push(MaterialPageRoute(
                                      builder: (_) => app.page(),
                                      settings: RouteSettings(name: app.id)));
                                },
                                child: Container(
                                  width: (panelWidth - 60) / 2,
                                  padding: EdgeInsets.symmetric(
                                      vertical: 20, horizontal: 8),
                                  decoration: BoxDecoration(
                                      border: Border.all(
                                          color: widget.selectForHome &&
                                                  pins.contains(app.id)
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                              : Theme.of(context).dividerColor),
                                      color: Theme.of(context).cardColor,
                                      borderRadius: BorderRadius.circular(20)),
                                  child: Column(children: [
                                    SizedBox(
                                        height: 48,
                                        child: Center(
                                            child: app.service != null
                                                ? ServiceAppIcon(app.service,
                                                    nasIcon: app.nasIcon)
                                                : app.package != null
                                                    ? NasAppIcon(app.package,
                                                        appIds: app.iconApps,
                                                        key: ValueKey(
                                                            'icon:${Util.baseUrl}|${Util.sid}|${app.package.id}|${app.iconApps}'),
                                                        fallbackAsset:
                                                            app.asset)
                                                    : app.asset == null
                                                        ? Icon(app.icon,
                                                            size: 45,
                                                            color: Theme.of(
                                                                    context)
                                                                .primaryColor)
                                                        : Image.asset(app.asset,
                                                            height: 45,
                                                            width: 45,
                                                            errorBuilder: (_,
                                                                    __, ___) =>
                                                                Icon(app.icon,
                                                                    size:
                                                                        45)))),
                                    SizedBox(height: 10),
                                    SizedBox(
                                        height: 2 *
                                            (Theme.of(context)
                                                    .textTheme
                                                    .bodyText2
                                                    .fontSize ??
                                                15) *
                                            1.45 *
                                            MediaQuery.of(context)
                                                .textScaleFactor,
                                        child: Align(
                                            alignment: Alignment.topCenter,
                                            child: Text(app.title,
                                                maxLines: 2,
                                                textAlign: TextAlign.center,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyText2))),
                                    SizedBox(
                                        height: 20 *
                                            MediaQuery.of(context)
                                                .textScaleFactor,
                                        child: widget.selectForHome
                                            ? Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                    Icon(
                                                        pins.contains(app.id)
                                                            ? Icons.check_circle
                                                            : Icons
                                                                .radio_button_unchecked,
                                                        size: 16,
                                                        color: pins.contains(
                                                                app.id)
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .primary
                                                            : Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant),
                                                    SizedBox(width: 4),
                                                    Text(
                                                        pins.contains(app.id)
                                                            ? '已选择'
                                                            : '点击选择',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .caption),
                                                  ])
                                            : Text(
                                                app.caption ??
                                                    (app.id.startsWith(
                                                            'container:')
                                                        ? '容器'
                                                        : ''),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .caption)),
                                  ]),
                                ))))
                        .toList()),
                if (shown.isEmpty && !loading)
                  Padding(padding: EdgeInsets.all(24), child: Text('没有匹配的程序')),
              ])),
          if (widget.selectForHome)
            Padding(
                padding: EdgeInsets.all(20),
                child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                        key: ValueKey('save-home-programs'),
                        onPressed: loading || !pinsLoaded || saving
                            ? null
                            : saveHomeSelection,
                        child: Text(saving ? '正在保存…' : '保存（${pins.length}）')))),
        ])));
  }
}
