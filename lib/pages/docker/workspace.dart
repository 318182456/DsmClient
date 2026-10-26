import 'package:dsm_client/util/function.dart';
import 'package:dsm_client/util/dsm_compatibility.dart';
import 'package:flutter/material.dart';
import 'docker.dart';
import 'dockhand.dart';

class DockerWorkspace extends StatefulWidget {
  final String initialBackend;
  const DockerWorkspace({this.initialBackend});
  @override State<DockerWorkspace> createState() => _DockerWorkspaceState();
}
class _DockerWorkspaceState extends State<DockerWorkspace> {
  String backend;
  String get profile => DsmCompatibility.connectionKey(Util.baseUrl);
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    String value;
    try { value = widget.initialBackend ?? await Util.getStorage('docker_backend_$profile'); } catch (_) {}
    if (mounted) setState(() => backend = value == 'dockhand' ? value : 'synology');
  }
  Future<void> choose() async {
    final value = await showModalBottomSheet<String>(context: context, builder: (sheet) => SafeArea(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text('选择容器管理方式')),
        RadioListTile<String>(title: Text('群晖 Container Manager'), value: 'synology', groupValue: backend,
          onChanged: (v) => Navigator.pop(sheet, v)),
        RadioListTile<String>(title: Text('Dockhand'), subtitle: Text('连接 Dockhand API 管理 Docker 环境'),
          value: 'dockhand', groupValue: backend, onChanged: (v) => Navigator.pop(sheet, v)),
      ])));
    if (value == null || !mounted) return;
    setState(() => backend = value);
    await Util.setStorage('docker_backend_$profile', value);
  }
  @override Widget build(BuildContext context) {
    if (backend == null) return Scaffold(appBar: AppBar(title: Text('容器管理')), body: Center(child: CircularProgressIndicator()));
    return backend == 'dockhand' ? DockhandProgram(profile: profile, onChooseBackend: choose)
      : Docker(title: 'Container Manager', onChooseBackend: choose);
  }
}
