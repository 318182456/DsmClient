import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dsm_client/pages/download_station/add_task.dart';
import 'package:dsm_client/widgets/workspace.dart';
import 'torrent_program.dart';

class TorrentInbox {
  static const channel = MethodChannel('dsmclient/torrent_import');
  static Future<Map> take() async =>
      await channel.invokeMapMethod<String, dynamic>('takePending');
  static Future<bool> handlesCurrentIntent() async =>
      await channel.invokeMethod<bool>('isTorrentIntent') ?? false;
  static Future<void> discard(String path) async {
    if (path != null) await channel.invokeMethod('discard', {'path': path});
  }
}

class TorrentImport extends StatelessWidget {
  final String path, name;
  const TorrentImport({this.path, this.name});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('添加种子')),
      body: ListView(padding: EdgeInsets.all(20), children: [
        WorkspaceHeader(title: '选择下载程序', subtitle: '连接后确认添加，不会自动开始下载。'),
        Card(
            child: ListTile(
                leading: Icon(Icons.description_outlined),
                title: Text(name ?? 'download.torrent'),
                subtitle: Text('种子文件'))),
        SizedBox(height: 20),
        for (final target in [
          'qBittorrent',
          'Transmission',
          'Download Station'
        ])
          Card(
              child: ListTile(
                  leading: Icon(Icons.download_outlined),
                  title: Text(target),
                  trailing: Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => target == 'Download Station'
                              ? AddDownloadTask(torrentPath: path)
                              : TorrentProgram(
                                  target == 'Transmission'
                                      ? 'transmission'
                                      : 'qbittorrent',
                                  transmission: target == 'Transmission',
                                  torrentPath: path,
                                  torrentName: name))))),
      ]));
}

Future<List<int>> readIncomingTorrent(String path) async {
  final file = File(path);
  final length = await file.length();
  if (length == 0 || length > 8 * 1024 * 1024)
    throw FormatException('种子文件大小应在 1 字节至 8 MB 之间');
  return file.readAsBytes();
}
