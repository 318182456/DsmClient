// @dart=2.10
import 'dart:convert';
import 'package:crypto/crypto.dart';

class ServiceSessionLease<T> {
  final _Session entry;
  final bool reused;
  bool released = false;
  ServiceSessionLease(this.entry, this.reused);
  T get client => entry.client as T;
  dynamic get data => entry.data;
  void update(dynamic value) {
    entry.data = value;
  }

  void release() {
    if (!released) {
      released = true;
      entry.users--;
      entry.lastUsed = DateTime.now();
    }
  }

  void invalidate() {
    if (identical(ServiceSessionPool._entries[entry.key], entry))
      ServiceSessionPool.remove(entry.key);
    release();
  }
}

class _Session {
  final String key, namespace;
  final dynamic client;
  final void Function() close;
  Future<void> ready;
  dynamic data;
  int users = 0;
  bool closed = false;
  DateTime lastUsed = DateTime.now();
  _Session(this.key, this.namespace, this.client, this.close);
  void shutdown() {
    if (!closed) {
      closed = true;
      close();
    }
  }
}

/// In-memory authenticated sessions. Passwords/cookies are never written by this pool.
class ServiceSessionPool {
  static final _entries = <String, _Session>{};
  static String key(
          String namespace, String service, String address, Map credentials) =>
      '$namespace|$service|${sha256.convert(utf8.encode(jsonEncode([
            address,
            credentials
          ])))}';
  static Future<ServiceSessionLease<T>> acquire<T>(
      {String namespace,
      String service,
      String address,
      Map credentials,
      T Function() create,
      Future<void> Function(T) login,
      Future<dynamic> Function(T) preload,
      void Function(T) close}) async {
    final id = key(namespace, service, address, credentials);
    var entry = _entries[id];
    if (entry != null &&
        entry.users == 0 &&
        DateTime.now().difference(entry.lastUsed) > Duration(minutes: 20)) {
      remove(id);
      entry = null;
    }
    final reused = entry != null;
    if (entry == null) {
      final client = create();
      entry = _Session(id, namespace, client, () => close(client));
      _entries[id] = entry;
      final created = entry;
      created.ready = (() async {
        try {
          await login(client);
          created.data = await preload(client);
        } catch (_) {
          if (identical(_entries[id], created)) _entries.remove(id);
          created.shutdown();
          rethrow;
        }
      })();
    }
    await entry.ready;
    if (entry.closed) throw StateError('连接已失效，请重试');
    entry.users++;
    entry.lastUsed = DateTime.now();
    return ServiceSessionLease<T>(entry, reused);
  }

  static void remove(String key) {
    _entries.remove(key)?.shutdown();
  }

  static void retainNamespace(String namespace) {
    for (final id in _entries.keys.toList()) {
      if (_entries[id].namespace != namespace) remove(id);
    }
  }

  static void clear() {
    for (final id in _entries.keys.toList()) remove(id);
  }
}
