// @dart=2.10
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Keeps partial files across navigation/restarts and verifies before installation.
class UpdateDownload {
  HttpClient _client;
  bool _paused = false;
  bool get isPaused => _paused;

  void pause() {
    _paused = true;
    _client?.close(force: true);
  }

  Future<bool> _valid(File file, int size, String digest) async {
    if (!await file.exists() || await file.length() != size) return false;
    return (await sha256.bind(file.openRead()).first).toString() == digest;
  }

  Future<File> fetch(
      {String url,
      String path,
      int size,
      String digest,
      void Function(double) onProgress}) async {
    _paused = false;
    final complete = File(path);
    final partial = File('$path.part');
    await complete.parent.create(recursive: true);
    if (await _valid(complete, size, digest)) return complete;
    if (await complete.exists()) await complete.delete();
    int received = await partial.exists() ? await partial.length() : 0;
    if (received > size) {
      await partial.delete();
      received = 0;
    }
    if (received == size) {
      if (await _valid(partial, size, digest)) return partial.rename(path);
      await partial.delete();
      received = 0;
    }
    _client = HttpClient()..connectionTimeout = Duration(seconds: 20);
    IOSink sink;
    try {
      final request =
          await _client.getUrl(Uri.parse(url)).timeout(Duration(seconds: 25));
      request.headers.set(HttpHeaders.userAgentHeader, 'DsmClient-Update');
      if (received > 0)
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$received-');
      final response = await request.close().timeout(Duration(seconds: 30));
      if (response.statusCode == HttpStatus.partialContent) {
        final range =
            response.headers.value(HttpHeaders.contentRangeHeader) ?? '';
        if (!range.startsWith('bytes $received-') ||
            !range.endsWith('/$size')) {
          throw StateError('服务器返回的断点信息不匹配，请稍后重试');
        }
      } else if (response.statusCode == HttpStatus.ok) {
        received = 0;
      } else {
        throw HttpException('下载请求失败（${response.statusCode}）');
      }
      sink = partial.openWrite(
          mode: received > 0 ? FileMode.append : FileMode.write);
      await for (final chunk in response.timeout(Duration(seconds: 30))) {
        if (_paused) throw StateError('下载已暂停');
        received += chunk.length;
        if (received > size) throw StateError('安装包大小不匹配');
        sink.add(chunk);
        onProgress?.call(received / size);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (!await _valid(partial, size, digest)) {
        if (received == size) await partial.delete();
        throw StateError('安装包校验失败，请重试');
      }
      return partial.rename(path);
    } finally {
      await sink?.flush();
      await sink?.close();
      _client?.close(force: true);
      _client = null;
    }
  }
}
