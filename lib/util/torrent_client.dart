// @dart=2.10
import 'dart:convert';
import 'dart:io';
import 'service_auth_error.dart';

/// An isolated service session. Never uses DSM cookies, credentials or TLS
/// overrides. The session pool can retain this client between page visits.
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
      {String body,
      bool json = false,
      List<int> binary,
      ContentType contentType}) async {
    final request = await _http
        .openUrl(body == null && binary == null ? 'GET' : 'POST', uri)
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
    if (binary != null) {
      request.headers.contentType = contentType;
      request.contentLength = binary.length;
      request.add(binary);
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
      if (cookie.name == 'SID' ||
          RegExp(r'^QBT_SID_\d+$').hasMatch(cookie.name))
        _cookie = '${cookie.name}=${cookie.value}';
    }
    if (response.statusCode == 401 || response.statusCode == 403)
      throw ServiceAuthException(
          '服务认证失败，请检查该程序的账号、密码和访问权限', response.statusCode);
    if (response.isRedirect) throw HttpException('服务地址发生跳转，请填写程序的直接 API 地址');
    return _ServiceResponse(response.statusCode, utf8.decode(bytes));
  }

  Future<dynamic> qb(String path,
      {Map<String, String> params, bool post = false}) async {
    final uri = endpoint('api/v2/$path');
    final response = await _request(
        post ? uri : uri.replace(queryParameters: params),
        body: post ? Uri(queryParameters: params ?? {}).query : null);
    if (response.status < 200 || response.status >= 300)
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
        if (result != null && '$result'.trim() != 'Ok.')
          throw HttpException('qBittorrent 登录失败');
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
          'addedDate',
          'labels',
          'trackers'
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
    Map trackerIndex = {};
    try {
      final metadata = await qb('sync/maindata', params: {'rid': '0'});
      if (metadata is Map && metadata['trackers'] is Map)
        trackerIndex = metadata['trackers'];
    } catch (_) {/* Older servers still expose the active tracker per task. */}
    final byHash = <String, List<String>>{};
    trackerIndex.forEach((url, hashes) {
      if (hashes is List)
        for (final hash in hashes)
          byHash.putIfAbsent('$hash', () => []).add('$url');
    });
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
              'trackers': byHash['${t['hash']}'] ?? [],
            })
        .toList();
  }

  Future<void> control(String action, dynamic id) => controlMany(action, [id]);
  Future<void> controlMany(String action, List<dynamic> ids) async {
    if (ids.isEmpty ||
        ids.any((id) =>
            id == null ||
            '$id'.isEmpty ||
            '$id' == 'all' ||
            '$id'.contains('|'))) throw ArgumentError('请选择明确的下载任务');
    const methods = {
      'start': 'torrent-start',
      'stop': 'torrent-stop',
      'force': 'torrent-start-now',
      'verify': 'torrent-verify',
      'reannounce': 'torrent-reannounce',
      'remove': 'torrent-remove',
      'remove-data': 'torrent-remove'
    };
    if (!methods.containsKey(action))
      throw ArgumentError('Unsupported torrent action');
    if (transmission) {
      await rpc(methods[action], {
        'ids': ids,
        if (action.startsWith('remove'))
          'delete-local-data': action == 'remove-data'
      });
    } else {
      final method = action == 'start'
          ? (_qb5 ? 'start' : 'resume')
          : action == 'stop'
              ? (_qb5 ? 'stop' : 'pause')
              : const {
                  'force': 'setForceStart',
                  'verify': 'recheck',
                  'reannounce': 'reannounce',
                  'remove': 'delete',
                  'remove-data': 'delete'
                }[action];
      await qb('torrents/$method', post: true, params: {
        'hashes': ids.join('|'),
        if (action == 'force') 'value': 'true',
        if (action.startsWith('remove'))
          'deleteFiles': action == 'remove-data' ? 'true' : 'false'
      });
    }
  }

  Future<void> filePriority(dynamic id, int index, int priority) async {
    if (index < 0 || ![0, 1, 6, 7].contains(priority))
      throw ArgumentError('无效的文件优先级');
    if (transmission) {
      await rpc('torrent-set', {
        'ids': [id],
        priority == 0 ? 'files-unwanted' : 'files-wanted': [index],
        if (priority != 0)
          (priority >= 6 ? 'priority-high' : 'priority-normal'): [index]
      });
    } else
      await qb('torrents/filePrio',
          post: true,
          params: {'hash': '$id', 'id': '$index', 'priority': '$priority'});
  }

  Future<void> limits(dynamic id, int downloadKiB, int uploadKiB) async {
    if (downloadKiB < 0 ||
        uploadKiB < 0 ||
        downloadKiB > 10485760 ||
        uploadKiB > 10485760) throw ArgumentError('限速值超出范围');
    if (transmission) {
      await rpc('torrent-set', {
        'ids': [id],
        'downloadLimited': downloadKiB > 0,
        'downloadLimit': downloadKiB,
        'uploadLimited': uploadKiB > 0,
        'uploadLimit': uploadKiB
      });
    } else {
      await qb('torrents/setDownloadLimit',
          post: true,
          params: {'hashes': '$id', 'limit': '${downloadKiB * 1024}'});
      await qb('torrents/setUploadLimit',
          post: true,
          params: {'hashes': '$id', 'limit': '${uploadKiB * 1024}'});
    }
  }

  Future<void> addTracker(dynamic id, String address) async {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        !['http', 'https', 'udp'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) throw FormatException('请输入有效的 Tracker 地址');
    if (transmission)
      await rpc('torrent-set', {
        'ids': [id],
        'trackerAdd': [address.trim()]
      });
    else
      await qb('torrents/addTrackers',
          post: true, params: {'hash': '$id', 'urls': address.trim()});
  }

  Future<void> addFile(List<int> bytes) async {
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024)
      throw ArgumentError('种子文件需小于 8 MB');
    if (transmission) {
      final result =
          await rpc('torrent-add', {'metainfo': base64Encode(bytes)});
      if (result['torrent-added'] == null &&
          result['torrent-duplicate'] == null) throw HttpException('服务未返回新任务');
      return;
    }
    final boundary = 'DsmClient${DateTime.now().microsecondsSinceEpoch}';
    final body = <int>[
      ...utf8.encode(
          '--$boundary\r\nContent-Disposition: form-data; name="torrents"; filename="upload.torrent"\r\nContent-Type: application/x-bittorrent\r\n\r\n'),
      ...bytes,
      ...utf8.encode('\r\n--$boundary--\r\n')
    ];
    final result = await _request(endpoint('api/v2/torrents/add'),
        binary: body,
        contentType: ContentType('multipart', 'form-data',
            parameters: {'boundary': boundary}));
    if (result.status < 200 ||
        result.status >= 300 ||
        (result.body.trim().isNotEmpty && result.body.trim() != 'Ok.'))
      throw HttpException('添加种子文件失败');
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
          'errorString',
          'downloadLimit',
          'downloadLimited',
          'uploadLimit',
          'uploadLimited',
          'uploadRatio',
          'eta'
        ]
      });
      final items = result['torrents'] as List ?? [];
      if (items.isEmpty) return {};
      final data = items.first as Map;
      final files = data['files'] as List ?? [],
          stats = data['fileStats'] as List ?? [];
      return {
        'properties': data,
        'files': [
          for (var i = 0; i < files.length; i++)
            {
              ...files[i] as Map,
              'index': i,
              'progress': (files[i]['length'] as num ?? 0) > 0
                  ? (files[i]['bytesCompleted'] as num ?? 0) /
                      files[i]['length']
                  : 0,
              'priority': i < stats.length
                  ? (stats[i]['wanted'] == false
                      ? 0
                      : (stats[i]['priority'] as num ?? 0) > 0
                          ? 6
                          : 1)
                  : 1
            }
        ],
        'trackers': data['trackerStats'] ?? [],
        'peers': data['peers'] ?? []
      };
    }
    final values = await Future.wait([
      qb('torrents/properties', params: {'hash': '$id'}),
      qb('torrents/files', params: {'hash': '$id'}),
      qb('torrents/trackers', params: {'hash': '$id'}),
      qb('sync/torrentPeers', params: {'hash': '$id'}),
    ]);
    final peers = values[3] is Map
        ? ((values[3]['peers'] as Map ?? {}).values.toList())
        : [];
    return {
      'properties': values[0],
      'files': values[1],
      'trackers': values[2],
      'peers': peers
    };
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
