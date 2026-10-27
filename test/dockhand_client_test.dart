// @dart=2.10
import 'dart:convert';
import 'dart:io';
import '../lib/util/dockhand_client.dart';

void expect(bool value, String text) {
  if (!value) throw StateError(text);
}

Future<void> rejects(Future<dynamic> future, String text) async {
  var failed = false;
  try {
    await future;
  } catch (_) {
    failed = true;
  }
  expect(failed, text);
}

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var redirected = 0, actions = 0, mfaRequests = 0;
  final failures = <Object>[];
  final clients = <DockhandClient>[];
  other.listen((r) {
    redirected++;
    r.response.close();
  });
  server.listen((r) async {
    try {
      expect(r.headers.value('origin') == 'http://127.0.0.1:${server.port}',
          'Service Origin must match Dockhand');
      expect(r.headers.value('accept') == 'application/json',
          'Job operations must negotiate the final JSON result');
      expect(!(r.headers.value('cookie') ?? '').contains('NAS'),
          'Never reuse a NAS cookie');
      final path = r.uri.path;
      final bodyText = await utf8.decoder.bind(r).join();
      if (path == '/dock/api/auth/login') {
        final body = jsonDecode(bodyText);
        expect(
            body['username'] == 'demo' && body['password'] == 'test-password',
            'Use the configured service account');
        if (body['mfaToken'] != '123456') {
          mfaRequests++;
          r.response.write('{"requiresMfa":true}');
        } else {
          r.response.cookies.add(Cookie('session_id', 'dockhand-demo'));
          r.response.write('{"success":true}');
        }
      } else {
        expect(
            r.headers.value('authorization') == 'Bearer dh_demo' ||
                r.headers.value('cookie') == 'session_id=dockhand-demo',
            'Authenticate independently with token or service session');
        if (path == '/dock/api/environments')
          r.response.write('[{"id":2,"name":"test-host"}]');
        else if (path == '/dock/api/redirect') {
          r.response.statusCode = 302;
          r.response.headers
              .set('Location', 'http://127.0.0.1:${other.port}/capture');
        } else {
          expect(r.uri.queryParameters['env'] == '2',
              'Every resource and action must retain environment scope');
          if (path == '/dock/api/containers')
            r.response.write('[{"id":"c1","name":"demo","state":"running"}]');
          else if (path == '/dock/api/containers/stats')
            r.response.write(
                '[{"id":"c1","cpuPercent":125,"memoryUsage":1024,"memoryLimit":8192}]');
          else if (path.endsWith('/logs'))
            r.response.write('{"logs":"example log"}');
          else if (path.endsWith('/stop') || path.endsWith('/restart')) {
            expect(r.method == 'POST', 'State changes require POST');
            actions++;
            if (path.contains('/failed-stack/'))
              r.response.write('{"success":false,"error":"compose failed"}');
            else if (path.contains('/pending-stack/'))
              r.response.write('{"jobId":"pending"}');
            else
              r.response.write('{"success":true}');
          } else
            r.response.write('[]');
        }
      }
    } catch (e) {
      failures.add(e);
      r.response.statusCode = 500;
    } finally {
      await r.response.close();
    }
  });
  try {
    final tokenClient = DockhandClient('http://127.0.0.1:${server.port}/dock');
    clients.add(tokenClient);
    await tokenClient.login(token: 'dh_demo');
    expect((await tokenClient.environments()).single['id'] == 2,
        'Load environments');
    expect(
        DockhandClient.records(await tokenClient.resource('containers', '2'))
                .single['id'] ==
            'c1',
        'Load native container data');
    expect((await tokenClient.statistics('2')).single['cpuPercent'] == 125,
        'Read environment-scoped container metrics without clamping multicore CPU');
    await rejects(tokenClient.statistics(null),
        'Reject stats requests without an environment');
    expect(
        (await tokenClient.container('c1', 'logs', '2'))['logs'] ==
            'example log',
        'Read logs');
    await tokenClient.control('c1', 'stop', '2');
    await tokenClient.control('my-stack', 'restart', '2', stack: true);
    expect(actions == 2, 'Only explicit requested actions execute');
    await rejects(
        tokenClient.control('failed-stack', 'restart', '2', stack: true),
        'Surface a failed compose operation');
    await rejects(
        tokenClient.control('pending-stack', 'restart', '2', stack: true),
        'Scheduling alone is not completion');
    expect(actions == 4, 'Never automatically retry state changes');
    await rejects(tokenClient.control('c1', 'stop', null),
        'Reject actions without an environment');
    await rejects(tokenClient.container('../escape', 'logs', '2'),
        'Reject path traversal in container identifiers');
    await rejects(tokenClient.request('api/redirect'),
        'Do not follow authenticated redirects');
    expect(
        redirected == 0, 'Service credentials must not reach another origin');
    final local = DockhandClient('http://127.0.0.1:${server.port}/dock');
    clients.add(local);
    var mfaRequired = false;
    try {
      await local.login(user: 'demo', password: 'test-password');
    } on DockhandMfaRequired {
      mfaRequired = true;
    }
    expect(mfaRequired && mfaRequests == 1,
        'Expose MFA requirement without automatic login retries');
    await local.login(user: 'demo', password: 'test-password', mfa: '123456');
    expect((await local.environments()).single['name'] == 'test-host',
        'Use the returned session cookie');
    expect(failures.isEmpty, 'Mock service assertions: $failures');
    print(
        'Dockhand authentication, environment and native management tests passed');
  } finally {
    for (final c in clients) c.close();
    await server.close(force: true);
    await other.close(force: true);
  }
}
