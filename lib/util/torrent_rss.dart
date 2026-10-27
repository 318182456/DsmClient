// @dart=2.10
import 'dart:convert';
import 'dart:io';
import 'package:xml/xml.dart';

class TorrentRssReader {
  final HttpClient _http = HttpClient()
    ..connectionTimeout = Duration(seconds: 15);
  static Uri validate(String address) {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty)
      throw FormatException('请输入有效的 HTTP/HTTPS RSS 地址');
    return uri;
  }

  static List<Map> parse(String content, Uri base) {
    if (content.toUpperCase().contains('<!DOCTYPE'))
      throw FormatException('不支持包含 DTD 的订阅');
    final document = XmlDocument.parse(content);
    if (!['rss', 'feed', 'RDF'].contains(document.rootElement.name.local))
      throw FormatException('该地址不是 RSS/Atom 订阅');
    final items = document.descendants
        .whereType<XmlElement>()
        .where((e) => ['item', 'entry'].contains(e.name.local))
        .take(1000);
    String text(XmlElement item, String name) => item.childElements
        .where((e) => e.name.local == name)
        .map((e) => e.innerText.trim())
        .join();
    return items.map<Map>((item) {
      String target = '';
      for (final child in item.childElements) {
        final name = child.name.local;
        final raw = name == 'enclosure'
            ? child.getAttribute('url')
            : name == 'link' && child.getAttribute('rel') == 'enclosure'
                ? child.getAttribute('href')
                : null;
        if (raw != null && raw.isNotEmpty) {
          target = base.resolve(raw).toString();
          break;
        }
      }
      if (target.isEmpty) {
        final link =
            item.childElements.where((e) => e.name.local == 'link').toList();
        if (link.isNotEmpty) {
          final raw =
              link.first.getAttribute('href') ?? link.first.innerText.trim();
          final uri = base.resolve(raw);
          if (uri.scheme == 'magnet' ||
              uri.path.toLowerCase().endsWith('.torrent'))
            target = uri.toString();
        }
      }
      final uri = Uri.tryParse(target);
      if (uri == null || !['http', 'https', 'magnet'].contains(uri.scheme))
        target = '';
      return {
        'id':
            text(item, 'guid').isEmpty ? text(item, 'id') : text(item, 'guid'),
        'title': text(item, 'title'),
        'date': text(item, 'pubDate').isEmpty
            ? text(item, 'updated')
            : text(item, 'pubDate'),
        'torrentURL': target
      };
    }).toList();
  }

  Future<List<Map>> read(String address) async {
    var url = validate(address);
    for (var redirects = 0; redirects < 4; redirects++) {
      final req = await _http.getUrl(url).timeout(Duration(seconds: 20));
      req.followRedirects = false;
      req.headers.set('Accept',
          'application/rss+xml, application/atom+xml, application/xml, text/xml');
      final res = await req.close().timeout(Duration(seconds: 20));
      if (res.isRedirect) {
        final location = res.headers.value(HttpHeaders.locationHeader);
        await res.drain();
        if (location == null) throw FormatException('订阅地址重定向无效');
        final next = validate(url.resolve(location).toString());
        if (url.scheme == 'https' && next.scheme != 'https')
          throw FormatException('订阅重定向到不安全地址');
        url = next;
        continue;
      }
      if (res.statusCode != 200) {
        await res.drain();
        throw HttpException('订阅读取失败（${res.statusCode}）');
      }
      final bytes = <int>[];
      await for (final chunk in res.timeout(Duration(seconds: 20))) {
        bytes.addAll(chunk);
        if (bytes.length > 8 * 1024 * 1024)
          throw FormatException('订阅内容超过 8 MB');
      }
      return parse(utf8.decode(bytes, allowMalformed: true), url);
    }
    throw FormatException('订阅地址重定向次数过多');
  }

  static List<Map> flatten(Map source, [String parent = '']) {
    final rows = <Map>[];
    source.forEach((key, value) {
      if (value is! Map) return;
      final path = parent.isEmpty ? '$key' : '$parent\\$key';
      if (value.containsKey('url'))
        rows.add({...value, 'path': path, 'name': '$key'});
      else
        rows.addAll(flatten(value, path));
    });
    return rows;
  }

  void close() => _http.close(force: true);
}
