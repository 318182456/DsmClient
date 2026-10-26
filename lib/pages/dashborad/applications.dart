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
import 'package:neumorphic/neumorphic.dart';

class ApplicationList extends StatefulWidget {
  final List applications;
  final Map system;
  final List volumes, disks;
  final Map appNotify;
  final Future<Map> Function() packageLoader, containerLoader;
  const ApplicationList(
      this.applications, this.system, this.volumes, this.disks, this.appNotify,
      {Key key, this.packageLoader, this.containerLoader})
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
  _MenuApp(this.id, this.title, this.icon, this.page, {this.asset, this.package, this.iconApps, this.caption});
}

class _ApplicationListState extends State<ApplicationList> {
  List<NasPackage> packages = [];
  List<Map> containers = [];
  String query = '', error = '', connection;
  bool loading = true;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(ApplicationList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (connection != '${Util.baseUrl}|${Util.sid}') load();
  }

  Future<Map> safe(Future<Map> request) async {
    try {
      return await request;
    } catch (_) {
      return {'success': false};
    }
  }

  Future<void> load() async {
    final current = ++generation;
    connection = '${Util.baseUrl}|${Util.sid}';
    setState(() {
      loading = true;
      error = '';
      packages = [];
      containers = [];
    });
    final result = await Future.wait([
      safe((widget.packageLoader ?? Api.nasPackages)()),
      safe((widget.containerLoader ?? Api.nasContainers)()),
    ]);
    if (!mounted ||
        generation != current ||
        connection != '${Util.baseUrl}|${Util.sid}') return;
    setState(() {
      packages = ((result[0]['data'] ?? {})['packages'] as List ?? [])
          .whereType<Map>()
          .map((p) => NasPackage.fromJson(p))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      containers = ((result[1]['data'] ?? {})['containers'] as List ?? [])
          .whereType<Map>()
          .toList()
        ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
      if (result[0]['success'] != true) error = '套件列表加载失败';
      if (result[1]['success'] != true &&
          (result[1]['error'] ?? {})['code'] != 102)
        error += '${error.isEmpty ? '' : '；'}容器列表加载失败';
      loading = false;
    });
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
      if (!ProgramCapabilities.hasWorkspace(package.id) && package.launchApps(widget.applications ?? []).isEmpty) continue;
      if (package.id == 'StorageManager' &&
          desktop.contains('SYNO.SDS.StorageManager.Instance')) continue;
      result.add(_MenuApp('package:${package.id}', package.name,
          programIcon(package.id), () => nativeProgram(package), package: package,
          asset: {'SMBService': 'assets/control_panel/${Util.version}/file_services.png',
            'ContainerManager':'assets/applications/container_manager.png', 'Docker':'assets/applications/docker.png',
            'StorageManager':'assets/applications/${Util.version}/storage_manager.png',
            'Virtualization':'assets/applications/${Util.version}/virtual_machine.png',
            'DownloadStation':'assets/applications/download_station.png'}[package.id],
          caption: ProgramCapabilities.hasWorkspace(package.id) ? null : '套件管理'));
      if (package.id == 'SynologyDrive') result.add(_MenuApp('package:SynologyDrive:console',
        'Drive 控制台', Icons.cloud, () => ProgramPage(package), package: package,
        iconApps: ['SYNO.SDS.CSTN.Instance']));
    }
    if (!installed.contains('FileStation'))
      result.add(
          _MenuApp('FileStation', 'File Station', Icons.folder, () => Files(),
            package: NasPackage.fromJson({'id': 'FileStation', 'name': 'File Station'})));
    if (!installed.contains('SynologyPhotos') &&
        desktop.contains('SYNO.Foto.AppInstance'))
      result.add(_MenuApp(
          'Photos', 'Synology Photos', Icons.photo_library, () => Photos(),
          asset: 'assets/applications/7/synology_photos.png'));
    if (desktop.contains('SYNO.Photo.AppInstance'))
      result.add(_MenuApp('Moments', 'Moments', Icons.photo, () => Moments(), asset: 'assets/applications/6/moments.png'));
    if (desktop.contains('SYNO.SDS.DownloadStation.Application') &&
        !installed.contains('DownloadStation'))
      result.add(_MenuApp('DownloadStation', 'Download Station', Icons.download,
          () => DownloadStation(), asset: 'assets/applications/download_station.png'));
    if (desktop.contains('SYNO.SDS.Virtualization.Application') &&
        !installed.contains('Virtualization'))
      result.add(_MenuApp('Virtualization', 'Virtual Machine Manager',
          Icons.computer, () => VirtualMachine(), asset: 'assets/applications/${Util.version}/virtual_machine.png'));
    if (!installed.contains('ContainerManager') &&
        !installed.contains('Docker') &&
        (desktop.contains('SYNO.SDS.ContainerManager.Application') ||
            desktop.contains('SYNO.SDS.Docker.Application')))
      result.add(_MenuApp('ContainerManager', 'Container Manager',
          Icons.view_in_ar, () => DockerWorkspace(), asset: 'assets/applications/container_manager.png'));
    for (final container in containers) {
      final name = '${container['name']}';
      final managers = packages.where((p) => p.id == 'ContainerManager' || p.id == 'Docker');
      result.add(_MenuApp('container:$name', name, Icons.view_in_ar_outlined,
          () => nativeContainer(name, image: '${container['image'] ?? ''}'),
          package: managers.isEmpty ? null : managers.first, asset: 'assets/applications/container_manager.png'));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final shown = entries
        .where((a) =>
            '${a.title} ${a.id}'.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Container(
        width: MediaQuery.of(context).size.width * .8,
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
            child: Column(children: [
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
                    onPressed: loading ? null : load),
              ])),
          if (loading) LinearProgressIndicator(),
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
                            label: app.title,
                            child: GestureDetector(
                                onTap: () {
                                  final navigator = Navigator.of(context);
                                  navigator.pop();
                                  navigator.push(MaterialPageRoute(
                                      builder: (_) => app.page(),
                                      settings: RouteSettings(name: app.id)));
                                },
                                child: NeuCard(
                                  width:
                                      (MediaQuery.of(context).size.width * .8 -
                                              60) /
                                          2,
                                  padding: EdgeInsets.symmetric(
                                      vertical: 20, horizontal: 8),
                                  curveType: CurveType.flat,
                                  bevel: 20,
                                  decoration: NeumorphicDecoration(
                                      color: Theme.of(context)
                                          .scaffoldBackgroundColor,
                                      borderRadius: BorderRadius.circular(20)),
                                  child: Column(children: [
                                    app.package != null ? NasAppIcon(app.package, appIds: app.iconApps,
                                      key: ValueKey('icon:${Util.baseUrl}|${Util.sid}|${app.package.id}|${app.iconApps}'), fallbackAsset: app.asset) : app.asset == null
                                        ? Icon(app.icon,
                                            size: 45,
                                            color:
                                                Theme.of(context).primaryColor)
                                        : Image.asset(app.asset,
                                            height: 45,
                                            width: 45,
                                            errorBuilder: (_, __, ___) =>
                                                Icon(app.icon, size: 45)),
                                    SizedBox(height: 10),
                                    Text(app.title,
                                        maxLines: 2,
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis),
                                    if (app.id.startsWith('container:'))
                                      Text('容器',
                                          style: Theme.of(context)
                                              .textTheme
                                              .caption),
                                    if (app.caption != null) Text(app.caption, style: Theme.of(context).textTheme.caption),
                                  ]),
                                ))))
                        .toList()),
                if (shown.isEmpty && !loading)
                  Padding(padding: EdgeInsets.all(24), child: Text('没有匹配的程序')),
              ])),
        ])));
  }
}
