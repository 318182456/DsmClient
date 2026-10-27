import 'package:shared_preferences/shared_preferences.dart';
import 'dsm_compatibility.dart';
import 'function.dart';
import 'service_credentials.dart';
import 'service_session_pool.dart';
import 'torrent_client.dart';
import 'dockhand_client.dart';
import 'dockhand_credentials.dart';

class ServiceSessions {
  static String get namespace =>
      '${DsmCompatibility.connectionKey(Util.baseUrl)}|${Util.account}';
  static final warmed = <String>{};
  static int generation = 0;
  static void clear() {
    generation++;
    warmed.clear();
    ServiceSessionPool.clear();
  }

  static Future<ServiceSessionLease<TorrentClient>> torrent(String profile,
          String address, bool transmission, String account, String password) =>
      ServiceSessionPool.acquire<TorrentClient>(
          namespace: namespace,
          service: 'torrent:$transmission:$profile',
          address: TorrentClient.validate(address).toString(),
          credentials: {'account': account, 'password': password},
          create: () => TorrentClient(address, transmission: transmission),
          login: (c) => c.login(account, password),
          preload: (c) => c.list(),
          close: (c) => c.close());
  static Future<ServiceSessionLease<DockhandClient>> dockhand(
          String profile,
          String address,
          String mode,
          String account,
          String password,
          String token,
          {String otp = ''}) =>
      ServiceSessionPool.acquire<DockhandClient>(
          namespace: namespace,
          service: 'dockhand:$profile',
          address: TorrentClient.validate(address).toString(),
          credentials: {
            'mode': mode,
            'account': account,
            'password': password,
            'token': token
          },
          create: () => DockhandClient(address),
          login: (c) => c.login(
              user: mode == 'local' ? account : '',
              password: password,
              token: mode == 'token' ? token : '',
              mfa: otp),
          preload: (c) => c.environments(),
          close: (c) => c.close());
  static Future<void> warmUp() async {
    final scope = namespace;
    final epoch = generation;
    bool current() => epoch == generation && scope == namespace;
    ServiceSessionPool.retainNamespace(scope);
    if (warmed.contains(scope)) return;
    warmed.clear();
    warmed.add(scope);
    final prefs = await SharedPreferences.getInstance();
    if (!current()) return;
    final nas = DsmCompatibility.connectionKey(Util.baseUrl);
    final keys = prefs
        .getKeys()
        .where((k) =>
            k.startsWith('torrent_url_false_$nas|') ||
            k.startsWith('torrent_url_true_$nas|') ||
            k == 'dockhand_url_$nas')
        .take(12)
        .toList();
    for (var i = 0; i < keys.length; i += 2) {
      await Future.wait(keys.skip(i).take(2).map((key) async {
        if (!current()) return;
        final address = prefs.getString(key);
        if (address == null || address.isEmpty) return;
        try {
          if (key.startsWith('torrent_url_')) {
            final transmission = key.startsWith('torrent_url_true_');
            final profile =
                key.substring('torrent_url_${transmission}_'.length);
            final saved = await ServiceCredentials(
                    scope: transmission ? 'transmission' : 'qbittorrent')
                .read(profile, address);
            if (saved == null || !current()) return;
            final lease = await torrent(profile, address, transmission,
                '${saved['account'] ?? ''}', '${saved['password'] ?? ''}');
            lease.release();
          } else {
            final profile = key.substring('dockhand_url_'.length);
            final saved = await DockhandCredentials().read(profile, address);
            if (saved == null || !current()) return;
            final lease = await dockhand(
                profile,
                address,
                '${saved['mode']}',
                '${saved['account'] ?? ''}',
                '${saved['password'] ?? ''}',
                '${saved['token'] ?? ''}');
            lease.release();
          }
        } catch (_) {
          /* Opening a page exposes authentication/MFA errors without blocking NAS startup. */
        }
      }));
    }
  }
}
