// @dart=2.10
import 'dart:convert';
import 'dart:io';
import 'torrent_client.dart';

class DockhandMfaRequired implements Exception {}

/// Dockhand owns this session. No DSM cookies or NAS TLS overrides are used.
class DockhandClient {
  final Uri base;
  final HttpClient _http = HttpClient()..connectionTimeout = Duration(seconds: 15);
  final Map<String, String> _cookies = {};
  String _token = '';
  DockhandClient(String address) : base = TorrentClient.validate(address);

  Future<dynamic> request(String path, {Map<String, String> query = const {}, Map body, String method = 'GET'}) async {
    if (!path.startsWith('api/') || path.contains('..') || path.contains('?')) throw ArgumentError('Invalid API path');
    final uri = base.replace(path: '${base.path}/$path', queryParameters: query.isEmpty ? null : query);
    final req = await _http.openUrl(method, uri).timeout(Duration(seconds: 20));
    req.followRedirects = false;
    req.headers.set('Accept', 'application/json');
    req.headers.set('Origin', base.origin);
    req.headers.set('Referer', '${base.toString()}/');
    if (_token.isNotEmpty) req.headers.set('Authorization', 'Bearer $_token');
    if (_cookies.isNotEmpty) req.headers.set('Cookie', _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '));
    if (body != null) { req.headers.contentType = ContentType.json; req.write(jsonEncode(body)); }
    final response = await req.close().timeout(Duration(seconds: 30));
    final bytes = <int>[];
    await for (final chunk in response.timeout(Duration(seconds: 30))) {
      bytes.addAll(chunk);
      if (bytes.length > 16 * 1024 * 1024) throw StateError('Dockhand 响应过大，请缩小查询范围');
    }
    if (response.isRedirect) throw StateError('Dockhand 地址发生跳转，请填写服务的直接地址');
    for (final cookie in response.cookies) {
      if (cookie.maxAge == 0) _cookies.remove(cookie.name); else _cookies[cookie.name] = cookie.value;
    }
    if (response.statusCode == 401 || response.statusCode == 403)
      throw StateError('Dockhand 认证失败或权限不足，请检查该程序的账号 / API Token');
    dynamic value;
    try { value = bytes.isEmpty ? <String, dynamic>{} : jsonDecode(utf8.decode(bytes)); }
    catch (_) { throw StateError('此地址未返回 Dockhand API 数据'); }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final reason = value is Map ? '${value['error'] ?? ''}' : '';
      throw StateError('Dockhand 请求失败（${response.statusCode}）${reason.isEmpty ? '' : ': $reason'}');
    }
    return value;
  }

  Future<void> login({String user = '', String password = '', String mfa = '', String token = ''}) async {
    _token = token.trim();
    if (_token.isNotEmpty || user.isEmpty) return;
    final result = await request('api/auth/login', method: 'POST', body: {
      'username': user, 'password': password, 'provider': 'local', if (mfa.isNotEmpty) 'mfaToken': mfa,
    });
    if (result is Map && result['requiresMfa'] == true) throw DockhandMfaRequired();
    if (result is! Map || result['success'] != true) throw StateError('Dockhand 登录失败');
  }

  static List<Map> records(dynamic value) {
    if (value is! List) throw FormatException('Dockhand 返回了不兼容的列表格式');
    return (value as List).whereType<Map>().toList();
  }
  Future<List<Map>> environments() async => records(await request('api/environments'));
  Future<dynamic> resource(String name, String env) async {
    if (!['containers', 'images', 'stacks', 'networks', 'volumes'].contains(name)) throw ArgumentError('Unsupported resource');
    if (int.tryParse(env ?? '') == null || int.parse(env) <= 0) throw ArgumentError('请选择有效的 Docker 环境');
    return await request('api/$name', query: {'env': env, if (name == 'containers') 'all': 'true'});
  }
  static String identifier(String value) {
    if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(value ?? '')) throw ArgumentError('无效的容器或项目标识');
    return value;
  }
  Future<dynamic> container(String id, String view, String env) async {
    validateEnvironment(env);
    if (!['inspect', 'logs', 'stats', 'top'].contains(view)) throw ArgumentError('Unsupported detail');
    return await request('api/containers/${identifier(id)}/$view', query: {'env': env, if (view == 'logs') 'tail': '200'});
  }
  Future<void> control(String id, String action, String env, {bool stack = false}) async {
    validateEnvironment(env);
    if (!(stack ? ['start','stop','restart'] : ['start','stop','restart','pause','unpause']).contains(action))
      throw ArgumentError('Unsupported action');
    final result = await request('api/${stack ? 'stacks' : 'containers'}/${identifier(id)}/$action',
      method: 'POST', query: {'env': env}, body: {});
    if (result is Map && result['success'] == false) throw StateError('Dockhand 未接受此操作');
  }
  void close() { _cookies.clear(); _token = ''; _http.close(force: true); }
  static void validateEnvironment(String env) {
    if (int.tryParse(env ?? '') == null || int.parse(env) <= 0) throw ArgumentError('请选择有效的 Docker 环境');
  }
}
