// @dart=2.10
import 'dart:convert';
import 'dart:io';
import '../lib/util/torrent_client.dart';
import '../lib/models/torrent_presentation.dart';

void expect(bool result, String message) {
  if (!result) throw StateError(message);
}

Future<void> reject(Future<dynamic> future) async {
  var failed = false;
  try {
    await future;
  } catch (_) {
    failed = true;
  }
  expect(failed, 'Expected request to fail');
}

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final calls = <Map>[];
  final failures = <Object>[];
  var emptyVersion = false;
  server.listen((request) async {
    try {
      final bytes =
          await request.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
      final path = request.uri.path.split('/').last;
      if (request.uri.path.startsWith('/qb/')) {
        if (path == 'login') {
          request.response.cookies.add(Cookie('SID', 'demo-session'));
          request.response.statusCode = 204;
        } else {
          expect(request.headers.value('cookie') == 'SID=demo-session',
              'Reuse service cookie after 204 login');
          if (path == 'version') {
            if (emptyVersion)
              request.response.statusCode = 204;
            else
              request.response.write('v5.2.0');
          } else if (path == 'info')
            request.response.write(
                '[{"hash":"a","name":"demo","state":"stoppedDL","progress":0.5}]');
          else if (path == 'properties')
            request.response.write('{"name":"demo"}');
          else if (path == 'files')
            request.response.write(
                '[{"index":2,"name":"part.bin","priority":1,"progress":0.5}]');
          else if (path == 'trackers')
            request.response
                .write('[{"url":"udp://tracker.example.test:6969/announce"}]');
          else if (path == 'torrentPeers')
            request.response.write('{"peers":{"one":{"ip":"192.0.2.1"}}}');
          else {
            expect(request.method == 'POST', 'Mutation must use POST');
            if (request.headers.contentType.mimeType == 'multipart/form-data') {
              final value = latin1.decode(bytes);
              expect(
                  value.contains('name="torrents"') &&
                      value.contains('d4:name4:test'),
                  'Upload raw torrent multipart bytes');
              calls.add({'method': 'file'});
            } else {
              final params = Uri.splitQueryString(utf8.decode(bytes));
              calls.add({'method': path, 'params': params});
              expect(
                  params['hashes'] == 'a|b' ||
                      params['hashes'] == 'a' ||
                      params['hash'] == 'a',
                  'Target only selected torrents');
            }
            request.response.statusCode = 204;
          }
        }
      } else {
        final body = jsonDecode(utf8.decode(bytes));
        final method = body['method'];
        final params = body['arguments'] as Map;
        if (request.headers.value('X-Transmission-Session-Id') != 'session') {
          request.response.statusCode = 409;
          request.response.headers.set('X-Transmission-Session-Id', 'session');
        } else {
          Map result = {};
          if (method == 'session-get')
            result = {'version': '4.0.6'};
          else if (method == 'torrent-get')
            result = {
              'torrents': [
                {
                  'id': 9,
                  'name': 'demo',
                  'files': [
                    {'name': 'part.bin', 'length': 100, 'bytesCompleted': 25}
                  ],
                  'fileStats': [
                    {'wanted': false, 'priority': 0}
                  ],
                  'trackerStats': [],
                  'peers': []
                }
              ]
            };
          else {
            calls.add({'method': method, 'params': params});
            if (method == 'torrent-add') {
              expect(
                  utf8.decode(base64Decode(params['metainfo'])) ==
                      'd4:name4:teste!',
                  'Transmission torrent bytes');
              result = {
                'torrent-added': {'id': 10}
              };
            } else
              expect((params['ids'] as List).first == 9,
                  'Transmission task scoping');
          }
          request.response
              .write(jsonEncode({'result': 'success', 'arguments': result}));
        }
      }
    } catch (error) {
      failures.add(error);
      request.response.statusCode = 500;
    } finally {
      await request.response.close();
    }
  });
  final qb = TorrentClient('http://127.0.0.1:${server.port}/qb');
  final tr = TorrentClient('http://127.0.0.1:${server.port}/service',
      transmission: true);
  try {
    await qb.login('demo', 'fixture');
    expect(qb.version == 'v5.2.0', '204 login requires valid version read');
    expect((await qb.list()).single['id'] == 'a',
        'Read tasks after no-content login');
    await qb.controlMany('stop', ['a', 'b']);
    await qb.control('force', 'a');
    await qb.filePriority('a', 2, 6);
    await qb.limits('a', 1024, 512);
    await qb.addTracker('a', 'udp://tracker.example.test:6969/announce');
    final torrent = utf8.encode('d4:name4:teste!');
    await qb.addFile(torrent);
    final detail = await qb.details('a');
    expect(
        detail['files'].single['index'] == 2, 'Preserve server file indices');
    expect(detail['peers'].single['ip'] == '192.0.2.1', 'Normalize peers');
    expect(
        calls.any(
            (c) => c['method'] == 'stop' && c['params']['hashes'] == 'a|b'),
        'Batch selected qBittorrent hashes');
    expect(
        calls.any((c) =>
            c['method'] == 'setDownloadLimit' &&
            c['params']['limit'] == '1048576'),
        'Convert KiB/s to bytes/s for qBittorrent');
    expect(
        calls.any((c) =>
            c['method'] == 'filePrio' &&
            c['params']['id'] == '2' &&
            c['params']['priority'] == '6'),
        'Set only selected file priority');
    emptyVersion = true;
    await reject(qb.login('demo', 'fixture'));
    emptyVersion = false;
    await reject(qb.controlMany('start', ['all']));
    await tr.login('demo', 'fixture');
    await tr.controlMany('force', [9, 10]);
    await tr.filePriority(9, 2, 0);
    await tr.filePriority(9, 2, 6);
    await tr.limits(9, 1024, 0);
    await tr.addFile(torrent);
    final t = await tr.details(9);
    expect(
        t['files'].single['priority'] == 0 &&
            t['files'].single['progress'] == .25,
        'Normalize Transmission file status');
    expect(
        calls.any((c) =>
            c['method'] == 'torrent-start-now' &&
            (c['params']['ids'] as List).length == 2),
        'Force start selected Transmission ids');
    expect(
        calls.any((c) =>
            c['method'] == 'torrent-set' &&
            c['params']['downloadLimit'] == 1024 &&
            c['params']['uploadLimited'] == false),
        'Transmission keeps KiB units');
    expect(
        calls.any((c) =>
            c['method'] == 'torrent-set' &&
            c['params']['files-unwanted'] != null),
        'Transmission unwanted files are not priority-normal');
    expect(TorrentPresentation.group({'state': 'stoppedDL'}) == 'paused',
        'qBittorrent 5 stopped state');
    expect(
        TorrentPresentation.group({'state': '6'}, transmission: true) ==
            'seeding',
        'Transmission numeric state');
    expect(
        TorrentPresentation.group({
              'state': '4',
              'raw': {'errorString': 'test error'}
            }, transmission: true) ==
            'error',
        'Error takes precedence');
    expect(failures.isEmpty, 'Mock service assertions: $failures');
    print(
        'Advanced torrent 204, batch, priorities, rates, uploads and detail tests passed');
  } finally {
    qb.close();
    tr.close();
    await server.close(force: true);
  }
}
