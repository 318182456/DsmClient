import 'package:dsm_client/models/nas_package.dart';
import 'package:dsm_client/util/function.dart';
import 'package:dsm_client/util/program_api.dart';
import 'package:flutter/material.dart';
import 'program_launcher.dart';

/// A desktop shortcut resolves to the same native package route as the drawer.
class PackageShortcut extends StatefulWidget {
  final String packageId, title;
  const PackageShortcut(this.packageId, {this.title = '程序'});
  @override
  State<PackageShortcut> createState() => _PackageShortcutState();
}

class _PackageShortcutState extends State<PackageShortcut> {
  Future<Map> result;
  @override
  void initState() {
    super.initState();
    result = Api.nasPackages();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map>(
      future: result,
      builder: (_, snapshot) {
        final response = snapshot.data;
        if (response != null && response['success'] == true) {
          final items = ((response['data'] ?? {})['packages'] as List ?? [])
              .whereType<Map>();
          final found = items.where((p) => p['id'] == widget.packageId);
          if (found.isNotEmpty)
            return nativeProgram(NasPackage.fromJson(found.first));
        }
        return Scaffold(
            appBar: AppBar(title: Text(widget.title)),
            body: Center(
                child: snapshot.connectionState != ConnectionState.done
                    ? CircularProgressIndicator()
                    : Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(response == null
                            ? '连接失败，请返回重试'
                            : response['success'] != true
                                ? ProgramApi.error(response)
                                : '当前账号未发现此套件，请从程序菜单查看可用应用。'))));
      });
}
