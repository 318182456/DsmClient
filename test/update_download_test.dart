// @dart=2.10
import 'dart:io';

import 'package:crypto/crypto.dart';
import '../lib/util/update_download.dart';

void expect(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final directory =
      await Directory.systemTemp.createTemp('dsmclient-update-test-');
  final payload = List<int>.generate(256 * 1024, (index) => index % 251);
  final digest = sha256.convert(payload).toString();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final ranges = <String>[];
  int requests = 0;
  server.listen((request) async {
    requests++;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null) ranges.add(range);
    int start = 0;
    if (range != null && request.uri.path != '/ignore-range') {
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range).group(1));
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(HttpHeaders.contentRangeHeader,
          'bytes $start-${payload.length - 1}/${payload.length}');
    }
    try {
      if (request.uri.path == '/bad') {
        request.response.add(List.filled(payload.length, 0));
      } else if (request.uri.path == '/truncated') {
        request.response.add(payload.sublist(0, payload.length ~/ 2));
      } else if (request.uri.path == '/slow') {
        for (int index = start; index < payload.length; index += 4096) {
          request.response.add(payload.sublist(
              index, (index + 4096).clamp(0, payload.length).toInt()));
          await request.response.flush();
          await Future.delayed(Duration(milliseconds: 15));
        }
      } else {
        request.response.add(payload.sublist(start));
      }
    } catch (_) {
      // Closing the client to pause a test also closes the server response.
    } finally {
      try {
        await request.response.close();
      } catch (_) {}
    }
  });
  final base = 'http://127.0.0.1:${server.port}';
  Future<File> fetch(String name, String route,
          {UpdateDownload download, void Function(double) progress}) =>
      (download ?? UpdateDownload()).fetch(
          url: '$base/$route',
          path: '${directory.path}/$name.apk',
          size: payload.length,
          digest: digest,
          onProgress: progress);
  try {
    final cached = File('${directory.path}/cached.apk');
    await cached.writeAsBytes(payload);
    final before = requests;
    await fetch('cached', 'normal');
    expect(requests == before,
        'Reuse a verified complete APK without any network request');

    final resume = File('${directory.path}/resume.apk.part');
    final half = payload.length ~/ 2;
    await resume.writeAsBytes(payload.sublist(0, half));
    final file = await fetch('resume', 'normal');
    expect(ranges.last == 'bytes=$half-', 'Request remaining bytes only');
    expect(sha256.convert(await file.readAsBytes()).toString() == digest,
        'Resumed file matches published digest');

    await File('${directory.path}/restart.apk.part')
        .writeAsBytes(payload.sublist(0, 100));
    final restarted = await fetch('restart', 'ignore-range');
    expect(await restarted.length() == payload.length,
        'Restart safely when server ignores Range instead of appending duplicate bytes');

    bool failed = false;
    try {
      await fetch('bad', 'bad');
    } catch (_) {
      failed = true;
    }
    expect(failed && !await File('${directory.path}/bad.apk').exists(),
        'Never promote a wrong-checksum download to an installable APK');
    expect(!await File('${directory.path}/bad.apk.part').exists(),
        'Discard a corrupt complete download');

    failed = false;
    try {
      await fetch('interrupted', 'truncated');
    } catch (_) {
      failed = true;
    }
    expect(
        failed &&
            await File('${directory.path}/interrupted.apk.part').length() ==
                half,
        'Preserve bytes after an incomplete response');
    await fetch('interrupted', 'normal');
    expect(ranges.last == 'bytes=$half-',
        'Resume after a previously interrupted request');

    final paused = UpdateDownload();
    failed = false;
    try {
      await fetch('paused', 'slow',
          download: paused, progress: (_) => paused.pause());
    } catch (_) {
      failed = true;
    }
    final partial = File('${directory.path}/paused.apk.part');
    expect(failed && paused.isPaused && await partial.exists(),
        'Pausing retains a partial file');
    final saved = await partial.length();
    expect(saved > 0 && saved < payload.length,
        'Keep the received prefix on pause');
    await fetch('paused', 'normal');
    expect(ranges.last == 'bytes=$saved-',
        'A later attempt resumes the paused download');
    print('In-app update download, resume, cache and integrity tests passed.');
  } finally {
    await server.close(force: true);
    await directory.delete(recursive: true);
  }
}
