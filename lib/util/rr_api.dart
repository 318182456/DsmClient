import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dsm_client/models/rr_protocol.dart';
import 'package:dsm_client/util/function.dart';

class RrApi {
  static Future<Map> call(String action, {Map<String, dynamic> params = const {}, bool write = false}) async {
    RrProtocol.validate(action, params, write);
    final base = Util.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final token = Util.sessionTokens.tokenFor(Util.baseUrl, Util.sid);
    final uri = '$base/webman/3rdparty/rr-manager/scripts/api.cgi';
    final dio = Dio(BaseOptions(contentType: Headers.formUrlEncodedContentType,
      followRedirects: false, validateStatus: (_) => true,
      headers: {'Cookie': Util.cookie ?? '', 'Origin': Uri.parse(base).origin,
        'Referer': '$base/', if (token.isNotEmpty) 'X-SYNO-TOKEN': token}));
    if (!Util.checkSsl) {
      (dio.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate = (client) {
        client.badCertificateCallback = (_, __, ___) => true; return client;
      };
    }
    try {
      final response = await dio.request(uri, options: Options(method: write ? 'POST' : 'GET'),
        queryParameters: {'action': action, 'lang': 'zh-CN', '_sid': Util.sid,
          if (token.isNotEmpty) 'SynoToken': token, if (!write) ...params},
        data: write ? params : null).timeout(Duration(seconds: 45));
      Map value;
      try { value = RrProtocol.decode(response.data); }
      catch (_) { throw StateError('RR Manager 接口不可用（HTTP ${response.statusCode}），请确认 4.x 套件已启用并重新登录 NAS'); }
      if (value['ok'] != true) throw StateError('${value['error'] ?? 'RR 操作失败'}');
      return value;
    } finally { dio.close(force: true); }
  }
}
