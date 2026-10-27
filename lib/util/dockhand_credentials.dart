import 'service_credentials.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DockhandCredentials extends ServiceCredentials {
  const DockhandCredentials(
      {FlutterSecureStorage storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true))})
      : super(scope: 'dockhand', storage: storage);
  static String key(String profile, String address) =>
      ServiceCredentials.keyFor('dockhand', profile, address);
}
