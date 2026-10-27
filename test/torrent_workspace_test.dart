// @dart=2.10
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dsm_client/pages/packages/torrent_program.dart';
import 'package:dsm_client/pages/packages/torrent_detail.dart';
import 'package:dsm_client/themes/light.dart';
import 'package:dsm_client/util/torrent_client.dart';
import 'package:dsm_client/util/service_credentials.dart';
import 'package:dsm_client/util/dockhand_credentials.dart';
import 'package:dsm_client/pages/packages/torrent_import.dart';
import 'dart:io';
import 'dart:convert';

class FixtureTorrentClient extends TorrentClient {
  final calls = <List>[];
  int loginCount = 0;
  bool rejectLogin = false;
  FixtureTorrentClient({bool transmission = false})
      : super('https://example.test', transmission: transmission);
  @override
  Future<void> login(String user, String password) async {
    loginCount++;
    if (rejectLogin) throw HttpException('fixture authentication rejected');
    version = '5.2.0';
  }

  @override
  Future<List<Map>> list() async => [
        {
          'id': 'a',
          'name': 'Ubuntu 24.04 LTS',
          'state': transmission ? '4' : 'downloading',
          'progress': .45,
          'size': 4000000000,
          'downloadSpeed': 2300000,
          'uploadSpeed': 120000,
          'raw': {'added_on': 3, 'addedDate': 3}
        },
        {
          'id': 'b',
          'name': 'Debian 13',
          'state': transmission ? '6' : 'uploading',
          'progress': 1,
          'size': 2000000000,
          'downloadSpeed': 0,
          'uploadSpeed': 850000,
          'raw': {'added_on': 2, 'addedDate': 2}
        },
        {
          'id': 'c',
          'name': 'Fedora Workstation',
          'state': transmission ? '0' : 'stoppedDL',
          'progress': .12,
          'size': 3000000000,
          'downloadSpeed': 0,
          'uploadSpeed': 0,
          'raw': {'added_on': 1, 'addedDate': 1}
        },
      ];
  @override
  Future<void> controlMany(String action, List<dynamic> ids) async {
    calls.add([action, ids]);
  }

  @override
  Future<Map> details(dynamic id) async => {
        'properties': {
          'name': 'Ubuntu 24.04 LTS',
          'dl_limit': 0,
          'up_limit': 0
        },
        'files': [
          {'index': 7, 'name': 'ubuntu.iso', 'priority': 1, 'progress': .45}
        ],
        'trackers': [],
        'peers': []
      };
  @override
  Future<void> filePriority(dynamic id, int index, int priority) async {
    calls.add([id, index, priority]);
  }

  @override
  Future<void> limits(dynamic id, int down, int up) async {
    calls.add([id, down, up]);
  }

  @override
  Future<void> addFile(List<int> bytes) async {
    calls.add(['upload', utf8.decode(bytes)]);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  for (final transmission in [false, true]) {
    testWidgets(
        'Remembered service reconnects once; disconnect, failure and forgetting stay editable ($transmission)',
        (tester) async {
      Future<void> open(FixtureTorrentClient client) async {
        await tester.pumpWidget(MaterialApp(
            key: UniqueKey(),
            theme: lightTheme,
            home: TorrentProgram('reconnect-fixture',
                transmission: transmission, clientFactory: (_, __) => client)));
        await tester.pumpAndSettle();
        await tester.pump(Duration(milliseconds: 400));
        await tester.pumpAndSettle();
      }

      final first = FixtureTorrentClient(transmission: transmission);
      await open(first);
      await tester.enterText(
          find.byType(TextField).first, 'https://example.test');
      await tester.pump(Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), 'demo');
      await tester.enterText(find.byType(TextField).last, 'fixture');
      await tester.ensureVisible(find.text('连接'));
      await tester.tap(find.text('连接'));
      await tester.pumpAndSettle();
      expect(first.loginCount, 1);
      await tester.pumpWidget(SizedBox());
      await tester.pumpAndSettle();
      final second = FixtureTorrentClient(transmission: transmission);
      await open(second);
      expect(second.loginCount, 1);
      expect(find.byType(TorrentTaskCard), findsNWidgets(3));
      await tester.tap(find.byTooltip('断开连接'));
      await tester.pumpAndSettle();
      await tester.pump(Duration(seconds: 1));
      expect(second.loginCount, 1);
      final failed = FixtureTorrentClient(transmission: transmission)
        ..rejectLogin = true;
      await open(failed);
      expect(failed.loginCount, 1);
      expect(find.text('fixture authentication rejected'), findsOneWidget);
      await tester.pump(Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(failed.loginCount, 1);
      expect(
          tester.widget<TextField>(find.byType(TextField).last).controller.text,
          'fixture');
      await tester.ensureVisible(find.text('记住登录信息'));
      await tester.tap(find.text('记住登录信息'));
      await tester.pumpAndSettle();
      final forgotten = FixtureTorrentClient(transmission: transmission);
      await open(forgotten);
      expect(forgotten.loginCount, 0);
      expect(
          tester.widget<TextField>(find.byType(TextField).last).controller.text,
          isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(SizedBox());
      await tester.pumpAndSettle();
    });
  }
  testWidgets(
      'External seed selection forwards the file and waits for explicit upload confirmation',
      (tester) async {
    final folder =
        Directory.systemTemp.createTempSync('DsmClient-torrent-test-');
    final file = File('${folder.path}/example.torrent')
      ..writeAsStringSync('d4:name4:teste!');
    addTearDown(() => folder.deleteSync(recursive: true));
    await tester.pumpWidget(MaterialApp(
        theme: lightTheme,
        home: TorrentImport(path: file.path, name: 'example.torrent')));
    await tester.tap(find.text('Transmission'));
    await tester.pumpAndSettle();
    final route = tester.widget<TorrentProgram>(find.byType(TorrentProgram));
    expect(route.transmission, isTrue);
    expect(route.torrentPath, file.path);
    final client = FixtureTorrentClient();
    await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        theme: lightTheme,
        home: TorrentProgram('fixture',
            torrentPath: file.path,
            torrentName: 'example.torrent',
            clientFactory: (_, __) => client)));
    await tester.enterText(
        find.byType(TextField).first, 'https://example.test');
    await tester.pump(Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('连接'));
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(client.calls, isEmpty);
    expect(find.text('example.torrent'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('确认添加'));
      await Future.delayed(Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(client.calls.single, ['upload', 'd4:name4:teste!']);
    expect(find.text('确认添加'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets(
      'Credentials remain isolated by backend, NAS and URL, including existing Dockhand keys',
      (tester) async {
    const qb = ServiceCredentials(scope: 'qbittorrent');
    const tr = ServiceCredentials(scope: 'transmission');
    await qb.save('nas-a', 'https://example.test/',
        {'mode': 'local', 'account': 'demo', 'password': 'fixture'});
    expect((await qb.read('nas-a', 'https://example.test'))['password'],
        'fixture');
    expect(await qb.read('nas-b', 'https://example.test'), isNull);
    expect(await tr.read('nas-a', 'https://example.test'), isNull);
    expect(await qb.read('nas-a', 'https://other.test'), isNull);
    expect(DockhandCredentials.key('nas-a', 'https://example.test'),
        ServiceCredentials.keyFor('dockhand', 'nas-a', 'https://example.test'));
    await qb.delete('nas-a', 'https://example.test');
    expect(await qb.read('nas-a', 'https://example.test'), isNull);
  });
  for (final transmission in [false, true]) {
    testWidgets(
        'Native torrent filters and confirmed batch controls ($transmission)',
        (tester) async {
      final client = FixtureTorrentClient(transmission: transmission);
      await tester.pumpWidget(MaterialApp(
          theme: lightTheme,
          home: TorrentProgram('fixture',
              transmission: transmission, clientFactory: (_, __) => client)));
      await tester.enterText(
          find.byType(TextField).first, 'https://example.test');
      await tester.pump(Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('连接'));
      await tester.tap(find.text('连接'));
      await tester.pumpAndSettle();
      expect(find.byType(TorrentTaskCard), findsNWidgets(3));
      await tester.tap(find.text('下载中 1'));
      await tester.pumpAndSettle();
      expect(find.byType(TorrentTaskCard), findsOneWidget);
      await tester.longPress(find.text('Ubuntu 24.04 LTS'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 项'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('torrent-batch-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('暂停').last);
      await tester.pumpAndSettle();
      expect(client.calls, isEmpty);
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(client.calls.single, [
        'stop',
        ['a']
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(SizedBox());
      await tester.pumpAndSettle();
    });
  }
  testWidgets('File priority and task limits target the chosen task and file',
      (tester) async {
    final client = FixtureTorrentClient();
    await tester.pumpWidget(MaterialApp(
        theme: lightTheme,
        home: TorrentDetail(
            client: client, task: {'id': 'a', 'name': 'Ubuntu 24.04 LTS'})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('文件优先级'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('高优先级'));
    await tester.pumpAndSettle();
    expect(client.calls.single, ['a', 7, 6]);
    await tester.tap(find.byTooltip('任务限速'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '1024');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(client.calls.last, ['a', 1024, 0]);
    expect(tester.takeException(), isNull);
    await tester.pump(Duration(milliseconds: 500));
    await tester.pumpWidget(SizedBox());
    client.close();
  });
}
