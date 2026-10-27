// @dart=2.10
import 'dart:async';
import '../lib/util/service_session_pool.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

class Client {
  int closes = 0;
}

Future<void> main() async {
  var logins = 0, reads = 0, creates = 0;
  final gate = Completer<void>();
  Future<ServiceSessionLease<Client>> open(
          {String namespace = 'nas|user',
          String service = 'qb',
          String password = 'fixture',
          bool fail = false}) =>
      ServiceSessionPool.acquire<Client>(
          namespace: namespace,
          service: service,
          address: 'https://example.test',
          credentials: {'password': password},
          create: () {
            creates++;
            return Client();
          },
          login: (c) async {
            logins++;
            await gate.future;
            if (fail) throw StateError('fixture failure');
          },
          preload: (c) async {
            reads++;
            return ['cached'];
          },
          close: (c) {
            c.closes++;
          });
  final a = open(), b = open();
  gate.complete();
  final leases = await Future.wait([a, b]);
  check(creates == 1 && logins == 1 && reads == 1,
      'Concurrent startup and page opening must share login and preload');
  check(identical(leases[0].client, leases[1].client),
      'Same authenticated client');
  final client = leases[0].client;
  leases[0].update(['new']);
  leases.forEach((l) => l.release());
  leases.first.release();
  final again = await open();
  check(
      again.reused &&
          again.data.first == 'new' &&
          client.closes == 0 &&
          logins == 1,
      'Closing pages must retain authenticated session and latest list');
  again.invalidate();
  check(client.closes == 1, 'Explicit disconnect closes session');
  final replacement = await open();
  again.invalidate();
  final retained = await open();
  check(identical(replacement.client, retained.client),
      'Old lease cannot invalidate a replacement session');
  final changed = await open(password: 'changed');
  check(!identical(changed.client, retained.client),
      'Changed credentials require fresh authentication');
  final tr = await open(service: 'tr'),
      dockhand = await open(service: 'dockhand');
  check(!identical(tr.client, dockhand.client), 'Service sessions isolated');
  final other = await open(namespace: 'other-nas|user');
  ServiceSessionPool.retainNamespace('other-nas|user');
  check(retained.client.closes == 1 && other.client.closes == 0,
      'NAS/account switch closes old sessions');
  for (var i = 0; i < 2; i++) {
    var failed = false;
    try {
      await open(namespace: 'failure', fail: true);
    } catch (_) {
      failed = true;
    }
    check(failed, 'Authentication failures are propagated');
  }
  final recovered = await open(namespace: 'failure');
  check(recovered.client.closes == 0,
      'Failed login must not poison future connection');
  ServiceSessionPool.clear();
  check(other.client.closes == 1 && recovered.client.closes == 1,
      'All retained clients closed exactly once');
  print(
      'Service session reuse, concurrent startup, isolation and recovery passed');
}
