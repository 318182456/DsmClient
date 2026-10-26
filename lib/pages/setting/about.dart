import 'dart:io';
import 'package:dsm_client/pages/setting/license.dart';
import 'package:dsm_client/pages/setting/open_source.dart';
import 'package:dsm_client/pages/setting/privacy.dart';
import 'package:dsm_client/util/function.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class About extends StatefulWidget {
  @override
  State<About> createState() => _AboutState();
}

class _AboutState extends State<About> {
  PackageInfo info;
  bool checking = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final value = await PackageInfo.fromPlatform();
    if (mounted) setState(() => info = value);
  }

  void open(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('关于 DsmClient')),
      body: ListView(padding: EdgeInsets.all(24), children: [
        SizedBox(height: 20),
        Center(
            child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset('assets/logo.png', width: 96, height: 96))),
        SizedBox(height: 16),
        Center(
            child: Text('DsmClient',
                style: Theme.of(context).textTheme.headline5)),
        if (info != null)
          Padding(
              padding: EdgeInsets.all(8),
              child: Center(
                  child: Text('v${info.version} · build ${info.buildNumber}'))),
        SizedBox(height: 24),
        ListTile(
            leading: Icon(Icons.description_outlined),
            title: Text('开源许可'),
            trailing: Icon(Icons.chevron_right),
            onTap: () => open(License())),
        ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('隐私说明'),
            trailing: Icon(Icons.chevron_right),
            onTap: () => open(Privacy())),
        ListTile(
            leading: Icon(Icons.code),
            title: Text('开源依赖'),
            trailing: Icon(Icons.chevron_right),
            onTap: () => open(OpenSource())),
        if (Platform.isAndroid)
          Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: ElevatedButton.icon(
                  icon: Icon(Icons.system_update),
                  label: Text(checking ? '正在检查…' : '检查更新'),
                  onPressed: checking
                      ? null
                      : () async {
                          setState(() => checking = true);
                          try {
                            await Util.checkUpdate(true, context, force: true);
                          } finally {
                            if (mounted) setState(() => checking = false);
                          }
                        })),
      ]));
}
