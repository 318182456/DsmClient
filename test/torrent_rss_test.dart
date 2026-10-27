// @dart=2.10
import 'dart:io';
import '../lib/util/torrent_rss.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final uri = Uri.parse('https://example.test/rss/feed.xml');
  final rss = TorrentRssReader.parse(
      '<rss><channel><item><guid>a</guid><title><![CDATA[A & B]]></title><enclosure url="../file.torrent?key=fixture" type="application/x-bittorrent"/></item></channel></rss>',
      uri);
  check(
      rss.single['title'] == 'A & B' &&
          rss.single['torrentURL'] ==
              'https://example.test/file.torrent?key=fixture',
      'RSS enclosure, CDATA and relative URLs');
  final atom = TorrentRssReader.parse(
      '<feed xmlns="http://www.w3.org/2005/Atom"><entry><id>b</id><title>Atom</title><link rel="enclosure" href="https://example.test/b.torrent"/></entry></feed>',
      uri);
  check(
      atom.single['id'] == 'b' &&
          atom.single['torrentURL'].endsWith('b.torrent'),
      'Atom enclosure');
  for (final invalid in [
    '<html>login</html>',
    '<!DOCTYPE rss [<!ENTITY a "x">]><rss/>'
  ]) {
    var rejected = false;
    try {
      TorrentRssReader.parse(invalid, uri);
    } catch (_) {
      rejected = true;
    }
    check(rejected, 'Reject HTML/DTD');
  }
  final tree = {
    'folder': {
      'Linux': {'url': 'https://example.test/rss', 'articles': rss}
    }
  };
  check(TorrentRssReader.flatten(tree).single['path'] == r'folder\Linux',
      'qB nested feed path');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final reader = TorrentRssReader();
  final errors = <Object>[];
  server.listen((r) async {
    try {
      check(
          r.headers.value('Cookie') == null &&
              r.headers.value('Authorization') == null,
          'RSS never forwards service credentials');
      if (r.uri.path == '/redirect') {
        r.response.statusCode = 302;
        r.response.headers.set('Location', '/rss');
      } else
        r.response.write(
            '<rss><channel><item><title>Fixture</title><enclosure url="/test.torrent"/></item></channel></rss>');
    } catch (e) {
      errors.add(e);
      r.response.statusCode = 500;
    } finally {
      await r.response.close();
    }
  });
  try {
    final result =
        await reader.read('http://127.0.0.1:${server.port}/redirect');
    check(result.single['title'] == 'Fixture' && errors.isEmpty,
        'Read isolated RSS with bounded redirect');
  } finally {
    reader.close();
    await server.close(force: true);
  }
  print('RSS/Atom parsing, privacy boundaries and HTTP tests passed');
}
