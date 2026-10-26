import 'dart:convert';
import 'package:dsm_client/models/dsm_icons.dart';
import 'package:dsm_client/models/nas_package.dart';
import 'package:dsm_client/util/function.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';

class NasAppIcon extends StatefulWidget {
  final NasPackage package;
  final String fallbackAsset;
  final double size;
  final List<String> appIds;
  const NasAppIcon(this.package, {this.fallbackAsset, this.size = 45, this.appIds, Key key}) : super(key: key);
  @override State<NasAppIcon> createState() => _NasAppIconState();
}
class _NasAppIconState extends State<NasAppIcon> {
  static final cache = <String, Future<List<String>>>{};
  List<String> urls = [];
  int index = 0;
  String cookie;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    final base = Util.baseUrl;
    if (Uri.tryParse(base ?? '')?.hasAuthority != true) return;
    cookie = Util.cookie ?? '';
    final id = widget.package.id;
    final key = '$base|${Util.sid}|$id|${widget.appIds}';
    try {
      final paths = await (cache[key] ??= (() async {
        if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(id) || id.contains('..')) return <String>[];
        if (id == 'FileStation' || id == 'SynologyPhotos') return DsmIcons.builtinPaths(id)
          .map((p) => DsmIcons.resolve(base, p)).where((p) => p != null).toList();
        final response = await Util.get('$base/webman/3rdparty/$id/config', cookie: cookie);
        final config = response is String ? jsonDecode(response) : response;
        final preferred = <String>[
          ...(widget.appIds ?? <String>[]),
          ...(const {'AudioStation': ['SYNO.SDS.AudioStation.Application'],
            'HyperBackup': ['SYNO.SDS.Backup.Application'],
            'CloudSync': ['SYNO.SDS.DSCloudSync.Instance'],
            'SynologyDrive': ['SYNO.SDS.Drive.Application']}[id] ?? <String>[]),
          ...widget.package.appIds,
        ];
        return [...DsmIcons.paths(id, config, preferred), ...DsmIcons.builtinPaths(id)]
          .map((p) => DsmIcons.resolve(base, p))
          .where((p) => p != null).toList();
      })());
      if (mounted) setState(() => urls = paths);
    } catch (_) { /* Keep a bundled DSM icon where available. */ }
  }
  @override Widget build(BuildContext context) {
    if (index >= urls.length) return SizedBox(width: widget.size, height: widget.size,
      child: widget.fallbackAsset == null ? null : Image.asset(widget.fallbackAsset, fit: BoxFit.contain));
    return ExtendedImage.network(urls[index], width: widget.size, height: widget.size, fit: BoxFit.contain,
      cache: true, headers: {'Cookie': cookie}, loadStateChanged: (state) {
        if (state.extendedImageLoadState == LoadState.failed) {
          final failed = index;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && failed == index) setState(() => index++);
          });
          return SizedBox(width: widget.size, height: widget.size);
        }
        return null;
      });
  }
}
