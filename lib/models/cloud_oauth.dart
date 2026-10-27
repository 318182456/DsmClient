// @dart=2.10
import 'dart:math';

/// Synology's shipped Cloud Sync OAuth client and callback contract. Tokens
/// stay in memory until the user confirms creation on their own NAS.
class CloudOAuth {
  static const clientId = 'HKeuanTUEZA0gK1EDTYd4lKP';
  static const redirect = 'https://synooauth.synology.com/CloudSync/bd.php';
  final Uri callback;
  CloudOAuth(String nas, {String nonce})
      : callback = Uri.parse(nas).replace(
            path:
                '/dsmclient-oauth/${nonce ?? List.generate(24, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}/webman/3rdparty/CloudSync/cloudsync.cgi',
            query: null,
            fragment: null);

  Uri get authorize => Uri.https('openapi.baidu.com', '/oauth/2.0/authorize', {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirect,
        'scope': 'netdisk',
        'confirm_login': '1',
        'state': callback
            .toString()
            .replaceFirst('/webman/3rdparty/CloudSync/cloudsync.cgi', '')
      });

  bool matches(String url) {
    final u = Uri.tryParse(url);
    return u != null &&
        u.scheme == callback.scheme &&
        u.host == callback.host &&
        u.port == callback.port &&
        u.userInfo.isEmpty &&
        u.path == callback.path &&
        u.queryParameters['action'] == 'oauth';
  }

  Map<String, dynamic> result(String url) {
    if (!matches(url)) throw FormatException('授权回调地址不匹配');
    final p = Uri.parse(url).queryParameters;
    if (p['oauth_step'] != 'success' || (p['access_token'] ?? '').isEmpty)
      throw StateError('百度网盘授权未完成，请重试');
    return {
      'client_type': 'bd',
      'client_id': clientId,
      'redirect': redirect,
      'access_token': p['access_token'],
      if (p['refresh_token'] != null) 'refresh_token': p['refresh_token']
    };
  }
}
