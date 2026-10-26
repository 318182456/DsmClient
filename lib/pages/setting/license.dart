import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class License extends StatefulWidget {
  const License({Key key}) : super(key: key);
  @override
  State<License> createState() => _LicenseState();
}

class _LicenseState extends State<License> {
  final Future<String> license = rootBundle.loadString('LICENSE');
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('开源许可')),
      body: FutureBuilder<String>(
          future: license,
          builder: (_, snapshot) {
            if (snapshot.hasError) return Center(child: Text('许可文件加载失败'));
            if (!snapshot.hasData)
              return Center(child: CircularProgressIndicator());
            return SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'DsmClient 基于 DSM helper 开源代码重新开发，沿用 Apache License 2.0。原作者与贡献者版权归各自权利人所有。'),
                      SizedBox(height: 20),
                      SelectableText(snapshot.data),
                    ]));
          }));
}
