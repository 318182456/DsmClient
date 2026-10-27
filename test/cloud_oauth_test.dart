// @dart=2.10
import '../lib/models/cloud_oauth.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  final flow =
      CloudOAuth('https://nas.example.com:8443', nonce: 'fixture-nonce');
  check(flow.authorize.host == 'openapi.baidu.com',
      'Use official provider authorization');
  check(flow.authorize.queryParameters['redirect_uri'] == CloudOAuth.redirect,
      'Use shipped Synology callback');
  check(
      flow.authorize.queryParameters['state']
          .endsWith('/dsmclient-oauth/fixture-nonce'),
      'Bind callback to unpredictable request path');
  final callback = flow.callback.replace(queryParameters: {
    'action': 'oauth',
    'oauth_step': 'success',
    'access_token': 'fixture-access',
    'refresh_token': 'fixture-refresh'
  }).toString();
  check(
      flow.matches(callback) &&
          flow.result(callback)['access_token'] == 'fixture-access',
      'Receive successful callback in memory');
  for (final bad in [
    callback.replaceFirst('nas.example.com', 'evil.example.com'),
    callback.replaceFirst('fixture-nonce', 'wrong-nonce'),
    callback.replaceFirst('8443', '443'),
    callback.replaceFirst('https:', 'http:'),
    callback.replaceFirst('action=oauth', 'action=other')
  ]) {
    check(
        !flow.matches(bad), 'Reject wrong callback origin, nonce or operation');
  }
  bool rejected = false;
  try {
    flow.result(flow.callback.replace(queryParameters: {
      'action': 'oauth',
      'oauth_step': 'cancel'
    }).toString());
  } catch (_) {
    rejected = true;
  }
  check(rejected, 'Cancellation cannot authorize a task');
  print('Cloud OAuth callback checks passed');
}
