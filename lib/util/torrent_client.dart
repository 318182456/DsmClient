// @dart=2.10
import 'dart:convert';
import 'dart:io';

/// An isolated service session. Never uses DSM cookies, credentials or TLS
/// overrides. Credentials live only in this object until the page is closed.
class TorrentClient {
  final Uri base;
  final bool transmission;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = Duration(seconds: 15);
  String _cookie = '', _basic = '', _rpcSession = '';
  bool _qb5 = false;
  String version = '';

  TorrentClient(String address, {this.transmission = false})
      : base = validate(address);
  static Uri validate(String address) {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw FormatException('请输入不含账号、查询参数的 HTTP/HTTPS 服务地址');
    }
    return uri.replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''));
  }

  Uri endpoint(String path) => base.replace(path: '${base.path}/$path');
  Uri get rpcUrl {
    if (base.path.endsWith('/rpc')) return base;
    if (base.path.endsWith('/transmission')) return endpoint('rpc');
    return endpoint('transmission/rpc');
  }

  Future<_ServiceResponse> _request(Uri uri,
      {String body, bool json = false}) async {
    final request = await _http
        .openUrl(body == null ? 'GET' : 'POST', uri)
        .timeout(Duration(seconds: 20));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (_cookie.isNotEmpty)
      request.headers.set(HttpHeaders.cookieHeader, _cookie);
    if (_basic.isNotEmpty)
      request.headers.set(HttpHeaders.authorizationHeader, _basic);
    if (_rpcSession.isNotEmpty)
      request.headers.set('X-Transmission-Session-Id', _rpcSession);
    if (!transmission) {
      request.headers.set('Referer', '${base.toString()}/');
      request.headers.set('Origin', base.origin);
    }
    if (body != null) {
      request.headers.contentType = ContentType(
          'application', json ? 'json' : 'x-www-form-urlencoded',
          charset: 'utf-8');
      request.write(body);
    }
    final response = await request.close().timeout(Duration(seconds: 25));
    final bytes = <int>[];
    await for (final chunk in response.timeout(Duration(seconds: 25))) {
      bytes.addAll(chunk);
      if (bytes.length > 16 * 1024 * 1024) throw HttpException('响应过大，请缩小查询范围');
    }
    final session = response.headers.value('X-Transmission-Session-Id');
    if (session != null && session.isNotEmpty) _rpcSession = session;
    for (final cookie in response.cookies) {
      if (cookie.name == 'SID') _cookie = '${cookie.name}=${cookie.value}';
    }
    if (response.statusCode == 401 || response.statusCode == 403)
      throw HttpException('服务认证失败，请检查该程序的账号、密码和访问权限');
    if (response.isRedirect) throw HttpException('服务地址发生跳转，请填写程序的直接 API 地址');
    return _ServiceResponse(response.statusCode, utf8.decode(bytes));
  }

  Future<dynamic> qb(String path,
      {Map<String, String> params, bool post = false}) async {
    final uri = endpoint('api/v2/$path');
    final response = await _request(
        post ? uri : uri.replace(queryParameters: params),
        body: post ? Uri(queryParameters: params ?? {}).query : null);
    if (response.status != 200)
      throw HttpException('qBittorrent 请求失败（${response.status}）');
    if (response.body.trim().isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } catch (_) {
      return response.body;
    }
  }

  Future<Map> rpc(String method,
      [Map<String, dynamic> arguments = const {}]) async {
    final body = jsonEncode({'method': method, 'arguments': arguments});
    for (var attempt = 0; attempt < 2; attempt++) {
      final response = await _request(rpcUrl, body: body, json: true);
      if (response.status == 409 && _rpcSession.isNotEmpty && attempt == 0)
        continue;
      if (response.status != 200)
        throw HttpException('Transmission 请求失败（${response.status}）');
      final result = jsonDecode(response.body);
      if (result is! Map || result['result'] != 'success')
        throw HttpException('Transmission 未接受此操作');
      return result['arguments'] as Map ?? {};
    }
    throw HttpException('Transmission 会话协商失败');
  }

  Future<void> login(String user, String password) async {
    if (transmission) {
      if (user.isNotEmpty || password.isNotEmpty)
        _basic = 'Basic ${base64Encode(utf8.encode('$user:$password'))}';
      final result = await rpc('session-get');
      version = '${result['version'] ?? ''}';
    } else {
      if (user.isNotEmpty || password.isNotEmpty) {
        final result = await qb('auth/login',
            post: true, params: {'username': user, 'password': password});
        if ('$result'.trim() != 'Ok.') throw HttpException('qBittorrent 登录失败');
      }
      version = '${await qb('app/version')}';
      if (!RegExp(r'^v?\d+\.\d+').hasMatch(version))
        throw HttpException('此地址未返回有效的 qBittorrent API');
      final major =
          int.tryParse(version.replaceFirst('v', '').split('.').first) ?? 0;
      _qb5 = major >= 5;
    }
  }

  Future<List<Map>> list() async {
    if (transmission) {
      final result = await rpc('torrent-get', {
        'fields': [
          'id',
          'name',
          'status',
          'percentDone',
          'totalSize',
          'rateDownload',
          'rateUpload',
          'eta',
          'errorString',
          'downloadDir',
          'uploadRatio',
          'hashString',
          'addedDate'
        ]
      });
      return (result['torrents'] as List ?? [])
          .whereType<Map>()
          .map((t) => {
                'id': t['id'],
                'name': t['name'],
                'progress': t['percentDone'],
                'size': t['totalSize'],
                'downloadSpeed': t['rateDownload'],
                'uploadSpeed': t['rateUpload'],
                'state': '${t['status']}',
                'raw': t,
              })
          .toList();
    }
    final result = await qb('torrents/info',
        params: {'sort': 'added_on', 'reverse': 'true'});
    if (result is! List) throw HttpException('无法读取任务列表');
    return (result as List)
        .whereType<Map>()
        .map<Map>((t) => {
              'id': t['hash'],
              'name': t['name'],
              'progress': t['progress'],
              'size': t['size'],
              'downloadSpeed': t['dlspeed'],
              'uploadSpeed': t['upspeed'],
              'state': t['state'],
              'raw': t,
            })
        .toList();
  }

  Future<void> control(String action, dynamic id) async {
    if (id == null || '$id'.isEmpty) throw FormatException('缺少任务标识');
    if (!['start', 'stop', 'verify', 'remove'].contains(action))
      throw ArgumentError('Unsupported action');
    if (transmission) {
      await rpc(action == 'remove' ? 'torrent-remove' : 'torrent-$action', {
        'ids': [id],
        if (action == 'remove') 'delete-local-data': false
      });
    } else {
      final command = action == 'start'
          ? (_qb5 ? 'start' : 'resume')
          : action == 'stop'
              ? (_qb5 ? 'stop' : 'pause')
              : action == 'verify'
                  ? 'recheck'
                  : 'delete';
      await qb('torrents/$command', post: true, params: {
        'hashes': '$id',
        if (action == 'remove') 'deleteFiles': 'false'
      });
    }
  }

  Future<void> add(String address) async {
    final uri = Uri.tryParse(address.trim());
    if (uri == null || !['magnet', 'https', 'http'].contains(uri.scheme))
      throw FormatException('请输入磁力链接或种子下载地址');
    if (transmission) {
      final result = await rpc('torrent-add', {'filename': address.trim()});
      if (result['torrent-added'] == null &&
          result['torrent-duplicate'] == null) throw HttpException('服务未返回新任务');
    } else {
      final result = await qb('torrents/add',
          post: true, params: {'urls': address.trim()});
      if (result != null && '$result'.trim() != 'Ok.')
        throw HttpException('添加任务失败');
    }
  }

  Future<Map> details(dynamic id) async {
    if (transmission) {
      final result = await rpc('torrent-get', {
        'ids': [id],
        'fields': [
          'name',
          'files',
          'fileStats',
          'trackerStats',
          'peers',
          'downloadDir',
          'errorString'
        ]
      });
      final items = result['torrents'] as List ?? [];
      return items.isEmpty ? {} : items.first as Map;
    }
    final values = await Future.wait([
      qb('torrents/properties', params: {'hash': '$id'}),
      qb('torrents/files', params: {'hash': '$id'}),
      qb('torrents/trackers', params: {'hash': '$id'}),
    ]);
    return {'任务': values[0], '文件': values[1], 'Tracker': values[2]};
  }

  void close() {
    _cookie = '';
    _basic = '';
    _rpcSession = '';
    _http.close(force: true);
  }
}

class _ServiceResponse {
  final int status;
  final String body;
  _ServiceResponse(this.status, this.body);
}
