// @dart=2.10
import 'dart:convert';
import 'dart:io';
import '../lib/util/torrent_client.dart';

void expect(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> rejects(Future<dynamic> future, String message) async {
  var failed = false;
  try {
    await future;
  } catch (_) {
    failed = true;
  }
  expect(failed, message);
}

Future<void> main() async {
  final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var leaked = 0;
  other.listen((r) {
    leaked++;
    r.response.close();
  });
  final qb = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var version = 'v5.0.4';
  final commands = <String>[];
  final errors = <Object>[];
  qb.listen((r) async {
    try {
      final path = r.uri.path;
      final body = await utf8.decoder.bind(r).join();
      final params =
          body.isEmpty ? <String, String>{} : Uri.splitQueryString(body);
      expect(r.headers.value('Origin') == 'http://127.0.0.1:${qb.port}',
          'qBittorrent Origin matches service');
      expect(!(r.headers.value('Cookie') ?? '').contains('NAS'),
          'No DSM cookie forwarding');
      if (path.endsWith('/auth/login')) {
        expect(
            params['username'] == 'alice' &&
                params['password'] == 'test-password',
            'Form authentication encoding');
        r.response.cookies.add(Cookie('SID', 'service-session'));
        r.response.write('Ok.');
      } else {
        expect(r.headers.value('Cookie') == 'SID=service-session',
            'Use isolated service session');
        if (path.endsWith('/app/version'))
          r.response.write(version);
        else if (path.endsWith('/torrents/info'))
          r.response.write(jsonEncode([
            {
              'hash': 'one',
              'name': 'example',
              'progress': .5,
              'size': 100,
              'dlspeed': 10,
              'upspeed': 2,
              'state': 'downloading'
            }
          ]));
        else if (path.endsWith('/sync/maindata'))
          r.response.write('{}');
        else if (path.endsWith('/redirect')) {
          r.response.statusCode = 302;
          r.response.headers
              .set('Location', 'http://127.0.0.1:${other.port}/capture');
        } else {
          commands.add(path.split('/').last);
          expect(r.method == 'POST', 'Mutations use POST');
          if (path.endsWith('/torrents/add')) {
            expect(params['urls'] == 'magnet:?xt=urn:btih:one',
                'Preserve magnet URI');
            r.response.write('Ok.');
          } else {
            expect(
                params['hashes'] == 'one', 'Only target the selected torrent');
            if (path.endsWith('/delete'))
              expect(params['deleteFiles'] == 'false', 'Keep downloaded files');
          }
        }
      }
    } catch (e) {
      errors.add(e);
      r.response.statusCode = 500;
    } finally {
      await r.response.close();
    }
  });
  final clients = <TorrentClient>[];
  final tr = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var handshakeCount = 0, removeSeen = false, badRetries = 0;
  tr.listen((r) async {
    try {
      expect(r.uri.path == '/service/transmission/rpc',
          'Preserve reverse proxy prefix');
      expect(r.headers.value('Cookie') == null,
          'Do not share qBittorrent or DSM cookies');
      expect(
          r.headers.value('Authorization') ==
              'Basic ${base64Encode(utf8.encode('bob:rpc-password'))}',
          'Independent Basic authentication');
      final body = jsonDecode(await utf8.decoder.bind(r).join());
      if (body['method'] == 'blocked' ||
          r.headers.value('X-Transmission-Session-Id') != 'csrf-session') {
        if (body['method'] == 'blocked')
          badRetries++;
        else
          handshakeCount++;
        r.response.statusCode = 409;
        r.response.headers.set('X-Transmission-Session-Id', 'csrf-session');
      } else {
        dynamic args = {};
        if (body['method'] == 'session-get') args = {'version': '4.0.6'};
        if (body['method'] == 'torrent-get')
          args = {
            'torrents': [
              {
                'id': 9,
                'name': 'example',
                'percentDone': .25,
                'rateDownload': 20,
                'rateUpload': 3,
                'status': 4
              }
            ]
          };
        if (body['method'] == 'torrent-remove') {
          removeSeen = true;
          expect(body['arguments']['ids'].single == 9,
              'Transmission selected task id');
          expect(body['arguments']['delete-local-data'] == false,
              'Transmission removal retains data');
        }
        r.response.write(jsonEncode({'result': 'success', 'arguments': args}));
      }
    } catch (e) {
      errors.add(e);
      r.response.statusCode = 500;
    } finally {
      await r.response.close();
    }
  });
  try {
    for (final value in [
      'https://user:password@example.com',
      'file:///tmp/service',
      'https://example.com/?key=private'
    ]) {
      var failed = false;
      try {
        TorrentClient.validate(value);
      } catch (_) {
        failed = true;
      }
      expect(
          failed, 'Reject credentials, query strings and non-HTTP addresses');
    }
    final a = TorrentClient('http://127.0.0.1:${qb.port}/qb');
    clients.add(a);
    await a.login('alice', 'test-password');
    expect((await a.list()).single['id'] == 'one',
        'Normalize native qBittorrent task rows');
    for (final command in ['start', 'stop', 'verify', 'remove'])
      await a.control(command, 'one');
    await a.add('magnet:?xt=urn:btih:one');
    expect(commands.join(',') == 'start,stop,recheck,delete,add',
        'qBittorrent 5 command names');
    await rejects(a.qb('redirect'), 'Reject service redirects');
    expect(leaked == 0,
        'Never forward authentication to a redirected destination');
    version = 'v4.6.7';
    final b = TorrentClient('http://127.0.0.1:${qb.port}/qb');
    clients.add(b);
    await b.login('alice', 'test-password');
    await b.control('start', 'one');
    await b.control('stop', 'one');
    expect(commands.sublist(commands.length - 2).join(',') == 'resume,pause',
        'qBittorrent 4 compatibility');
    final c = TorrentClient('http://127.0.0.1:${tr.port}/service',
        transmission: true);
    clients.add(c);
    await c.login('bob', 'rpc-password');
    expect(handshakeCount == 1, 'Negotiate Transmission CSRF session once');
    final tasks = await c.list();
    expect(tasks.single['id'] == 9 && tasks.single['progress'] == .25,
        'Normalize Transmission rows');
    await c.control('remove', 9);
    expect(removeSeen, 'Transmission removal submitted');
    await rejects(c.rpc('blocked'), 'Bound repeated 409 retries');
    expect(badRetries == 2, 'No unbounded CSRF retry loop');
    expect(errors.isEmpty, 'Mock service assertions: $errors');
    print('Native torrent service integration tests passed');
  } finally {
    for (final client in clients) client.close();
    await qb.close(force: true);
    await tr.close(force: true);
    await other.close(force: true);
  }
}
