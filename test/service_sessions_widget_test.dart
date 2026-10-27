// @dart=2.10
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dsm_client/util/function.dart';
import 'package:dsm_client/util/dsm_compatibility.dart';
import 'package:dsm_client/util/service_credentials.dart';
import 'package:dsm_client/util/dockhand_credentials.dart';
import 'package:dsm_client/util/service_sessions.dart';
import 'package:dsm_client/util/service_session_pool.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'Startup warms saved qB, TR and Dockhand and page opening reuses authenticated clients',
      () async {
    final oldBase = Util.baseUrl, oldAccount = Util.account;
    Util.baseUrl = 'https://nas.test';
    Util.account = 'fixture';
    final oldOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    final nas = DsmCompatibility.connectionKey(Util.baseUrl);
    final qp = '$nas|qb', tp = '$nas|tr';
    ServiceSessions.warmed.clear();
    ServiceSessionPool.clear();
    FlutterSecureStorage.setMockInitialValues({});
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final address = 'http://127.0.0.1:${server.port}';
    SharedPreferences.setMockInitialValues({
      'torrent_url_false_$qp': address,
      'torrent_url_true_$tp': address,
      'dockhand_url_$nas': address,
      'torrent_url_false_$nas|not-remembered': address
    });
    final counts = <String, int>{};
    final errors = <Object>[];
    server.listen((request) async {
      try {
        final body = await utf8.decoder.bind(request).join();
        final path = request.uri.path;
        counts[path] = (counts[path] ?? 0) + 1;
        request.response.headers.contentType = ContentType.json;
        if (path == '/api/v2/auth/login') {
          request.response.cookies.add(Cookie('QBT_SID_8080', 'fixture'));
          request.response.write('Ok.');
        } else if (path == '/api/v2/app/version') {
          expect(request.cookies.any((c) => c.name == 'QBT_SID_8080'), true);
          request.response.write('v5.3.0');
        } else if (path == '/api/v2/torrents/info') {
          request.response.write('[]');
        } else if (path == '/api/v2/sync/maindata') {
          request.response.write('{}');
        } else if (path == '/transmission/rpc') {
          expect(request.headers.value('Authorization'),
              'Basic ${base64Encode(utf8.encode('demo:fixture'))}');
          final message = jsonDecode(body);
          request.response.write(jsonEncode({
            'result': 'success',
            'arguments': message['method'] == 'session-get'
                ? {'version': '4.0'}
                : {'torrents': []}
          }));
        } else if (path == '/api/auth/login') {
          request.response.cookies.add(Cookie('dockhand_session', 'fixture'));
          request.response.write('{"success":true}');
        } else if (path == '/api/environments') {
          expect(
              request.cookies.any((c) => c.name == 'dockhand_session'), true);
          request.response.write('[{"id":1,"name":"fixture"}]');
        } else {
          throw StateError('Unexpected $path');
        }
      } catch (e) {
        errors.add(e);
        request.response.statusCode = 500;
      } finally {
        await request.response.close();
      }
    });
    try {
      for (final service in ['qbittorrent', 'transmission'])
        await ServiceCredentials(scope: service).save(
            service == 'qbittorrent' ? qp : tp,
            address,
            {'mode': 'local', 'account': 'demo', 'password': 'fixture'});
      await DockhandCredentials().save(nas, address,
          {'mode': 'local', 'account': 'demo', 'password': 'fixture'});
      await (() async {
        await ServiceSessions.warmUp();
        expect(counts['/api/v2/auth/login'], 1);
        expect(counts['/transmission/rpc'], 2);
        expect(counts['/api/auth/login'], 1);
        final q = await ServiceSessions.torrent(
            qp, address, false, 'demo', 'fixture');
        final t =
            await ServiceSessions.torrent(tp, address, true, 'demo', 'fixture');
        final d = await ServiceSessions.dockhand(
            nas, address, 'local', 'demo', 'fixture', '');
        expect(q.reused && t.reused && d.reused, true);
        q.release();
        t.release();
        d.release();
        await ServiceSessions.warmUp();
        expect(counts['/api/v2/auth/login'], 1);
        expect(counts['/transmission/rpc'], 2);
        expect(counts['/api/auth/login'], 1);
        expect(errors, isEmpty);
        ServiceSessions.clear();
        await ServiceSessions.warmUp();
        expect(counts['/api/v2/auth/login'], 2);
        expect(counts['/transmission/rpc'], 4);
        expect(counts['/api/auth/login'], 2);
        expect(errors, isEmpty);
      })();
    } finally {
      ServiceSessionPool.clear();
      ServiceSessions.warmed.clear();
      await server.close(force: true);
      HttpOverrides.global = oldOverrides;
      Util.baseUrl = oldBase;
      Util.account = oldAccount;
    }
  });
}
