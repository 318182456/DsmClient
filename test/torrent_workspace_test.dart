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

class FixtureTorrentClient extends TorrentClient {
  final calls = <List>[];
  FixtureTorrentClient({bool transmission = false})
      : super('https://example.test', transmission: transmission);
  @override
  Future<void> login(String user, String password) async {
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
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
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
      await tester.tap(
          find.byWidgetPredicate((w) => w is PopupMenuButton<String>).first);
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
