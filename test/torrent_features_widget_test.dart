// @dart=2.10
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dsm_client/pages/packages/torrent_rss.dart';
import 'package:dsm_client/pages/dashborad/applications.dart';
import 'package:dsm_client/pages/control_panel/control_panel.dart';
import 'package:dsm_client/util/program_pins.dart';
import 'package:dsm_client/util/torrent_rss_store.dart';
import 'package:dsm_client/util/torrent_client.dart';
import 'package:dsm_client/widgets/torrent_filters.dart';
import 'package:dsm_client/util/function.dart';
import 'package:dsm_client/themes/light.dart';

class RssFixtureClient extends TorrentClient {
  final writes = <Map>[];
  bool removed = false;
  RssFixtureClient() : super('https://example.test');
  @override
  Future<dynamic> qb(String path,
      {Map<String, String> params, bool post = false}) async {
    if (post) {
      writes.add({'path': path, 'params': params});
      if (path == 'rss/removeItem') removed = true;
      return null;
    }
    if (path == 'app/preferences') return {'rss_processing_enabled': true};
    if (path == 'rss/items')
      return removed
          ? {}
          : {
              'Linux': {
                'url': 'https://feed.test/rss?key=fixture',
                'articles': [
                  {
                    'id': 'a',
                    'title': 'Ubuntu ISO',
                    'torrentURL': 'https://feed.test/a.torrent'
                  }
                ]
              }
            };
    throw StateError('Unexpected fixture read');
  }

  @override
  Future<void> add(String url) async {
    writes.add({'path': 'add', 'url': url});
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  testWidgets('RSS article download and feed removal require confirmation',
      (tester) async {
    final client = RssFixtureClient();
    await tester.pumpWidget(MaterialApp(
        theme: lightTheme,
        home: TorrentRssPage(client: client, profile: 'test')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Linux'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ubuntu ISO'));
    await tester.pumpAndSettle();
    expect(client.writes, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(client.writes, isEmpty);
    await tester.tap(find.text('Ubuntu ISO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(client.writes.first['url'], 'https://feed.test/a.torrent');
    expect(client.writes.last['params']['articleId'], 'a');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('移除订阅'));
    await tester.pumpAndSettle();
    expect(client.removed, isFalse);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(client.removed, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(SizedBox());
    client.close();
  });
  testWidgets(
      'Local subscriptions are encrypted and scoped; program pins keep NAS order/isolation',
      (tester) async {
    const store = TorrentRssStore('nas/service-a');
    await store.save([
      {'name': 'feed', 'url': 'https://feed.test/rss?passkey=fixture'}
    ]);
    expect((await store.read()).single['name'], 'feed');
    expect(await TorrentRssStore('nas/service-b').read(), isEmpty);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    final oldBase = Util.baseUrl, oldAccount = Util.account;
    addTearDown(() {
      Util.baseUrl = oldBase;
      Util.account = oldAccount;
    });
    Util.baseUrl = 'https://nas-a.test:5001';
    Util.account = 'demo';
    await ProgramPins.toggle('a');
    await ProgramPins.toggle('b');
    await ProgramPins.move('b', -1);
    expect(await ProgramPins.read(), ['b', 'a']);
    Util.baseUrl = 'https://nas-b.test:5001';
    expect(await ProgramPins.read(), isEmpty);
    Util.baseUrl = 'https://nas-a.test:5001';
    await ProgramPins.toggle('b');
    expect(await ProgramPins.read(), ['a']);
  });
  testWidgets(
      'Long press pins a native program to the console and opens its native route',
      (tester) async {
    final oldBase = Util.baseUrl;
    Util.baseUrl = '';
    addTearDown(() => Util.baseUrl = oldBase);
    Future<Map> packages() async => {
          'success': true,
          'data': {'packages': []}
        };
    Future<Map> containers() async => {
          'success': true,
          'data': {'containers': []}
        };
    const apps = ['SYNO.SDS.AdminCenter.Application'];
    await tester.pumpWidget(MaterialApp(
        theme: lightTheme,
        home: Scaffold(
            body: Column(children: [
          ApplicationList(apps, {}, [], [], {},
              pinnedOnly: true,
              packageLoader: packages,
              containerLoader: containers),
          Expanded(
              child: ApplicationList(apps, {}, [], [], {},
                  packageLoader: packages, containerLoader: containers)),
        ]))));
    await tester.pumpAndSettle();
    await tester.longPress(
        find.byKey(ValueKey('program-card:SYNO.SDS.AdminCenter.Application')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加到首页'));
    await tester.pumpAndSettle();
    final shortcut =
        find.byKey(ValueKey('pinned-program:SYNO.SDS.AdminCenter.Application'));
    expect(shortcut, findsOneWidget);
    await tester.tap(shortcut);
    await tester.pumpAndSettle();
    expect(find.byType(ControlPanel), findsOneWidget);
    Navigator.of(tester.element(find.byType(ControlPanel))).pop();
    await tester.pumpAndSettle();
    await tester.longPress(shortcut);
    await tester.pumpAndSettle();
    await tester.tap(find.text('从首页移除'));
    await tester.pumpAndSettle();
    expect(shortcut, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('Home Add selects programs and saves without opening them', (tester) async {
    final oldBase = Util.baseUrl; Util.baseUrl = ''; addTearDown(() => Util.baseUrl = oldBase);
    Future<Map> packages() async => {'success':true,'data':{'packages':[]}};
    Future<Map> containers() async => {'success':true,'data':{'containers':[]}};
    await tester.pumpWidget(MaterialApp(theme:lightTheme,home:Scaffold(body:SingleChildScrollView(
      child:ApplicationList(['SYNO.SDS.AdminCenter.Application','SYNO.SDS.ResourceMonitor.Instance'],{},[],[],{},
        pinnedOnly:true,packageLoader:packages,containerLoader:containers)))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加')); await tester.pumpAndSettle();
    expect(find.text('选择常用程序'),findsOneWidget);
    await tester.tap(find.byKey(ValueKey('program-card:SYNO.SDS.AdminCenter.Application')));await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('program-card:SYNO.SDS.ResourceMonitor.Instance')));await tester.pumpAndSettle();
    expect(find.byType(ControlPanel),findsNothing);
    expect(await ProgramPins.read(),isEmpty);
    expect(find.text('保存（2）'),findsOneWidget);
    await tester.tap(find.byKey(ValueKey('save-home-programs')));await tester.pumpAndSettle();
    expect(find.text('选择常用程序'),findsNothing);
    expect(find.byKey(ValueKey('pinned-program:SYNO.SDS.AdminCenter.Application')),findsOneWidget);
    expect(find.byKey(ValueKey('pinned-program:SYNO.SDS.ResourceMonitor.Instance')),findsOneWidget);
    expect(await ProgramPins.read(),['SYNO.SDS.AdminCenter.Application','SYNO.SDS.ResourceMonitor.Instance']);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(SizedBox());await tester.pumpAndSettle();
  });
  testWidgets('Cancel discards selection and Clear only persists after Save', (tester) async {
    final oldBase = Util.baseUrl; Util.baseUrl = ''; addTearDown(() => Util.baseUrl = oldBase);
    await ProgramPins.replace(['SYNO.SDS.AdminCenter.Application']);
    Future<Map> packages() async => {'success':true,'data':{'packages':[]}};
    Future<Map> containers() async => {'success':true,'data':{'containers':[]}};
    await tester.pumpWidget(MaterialApp(theme:lightTheme,home:Scaffold(body:SingleChildScrollView(
      child:ApplicationList(['SYNO.SDS.AdminCenter.Application','SYNO.SDS.ResourceMonitor.Instance'],{},[],[],{},
        pinnedOnly:true,packageLoader:packages,containerLoader:containers)))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加'));await tester.pumpAndSettle();
    expect(find.text('保存（1）'),findsOneWidget);
    await tester.tap(find.text('清空'));await tester.pumpAndSettle();
    expect(await ProgramPins.read(),['SYNO.SDS.AdminCenter.Application']);
    await tester.pageBack();await tester.pumpAndSettle();
    expect(await ProgramPins.read(),['SYNO.SDS.AdminCenter.Application']);
    await tester.tap(find.text('添加'));await tester.pumpAndSettle();
    expect(find.text('保存（1）'),findsOneWidget);
    await tester.tap(find.text('清空'));await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('save-home-programs')));await tester.pumpAndSettle();
    expect(await ProgramPins.read(),isEmpty);
    expect(find.byKey(ValueKey('pinned-program:SYNO.SDS.AdminCenter.Application')),findsNothing);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(SizedBox());await tester.pumpAndSettle();
  });
  testWidgets(
      'Advanced filters retain independent category, tag and Tracker values',
      (tester) async {
    Map selected;
    await tester.pumpWidget(MaterialApp(
        theme: lightTheme,
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    child: Text('筛选'),
                    onPressed: () async {
                      selected = await showTorrentFilters(context, [
                        {
                          'raw': {
                            'category': 'linux',
                            'tags': 'keep',
                            'tracker': 'https://tracker.test/announce',
                            'save_path': '/data'
                          }
                        }
                      ]);
                    })))));
    await tester.tap(find.text('筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('filter-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('linux').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('filter-tag')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('keep').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('filter-tracker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('tracker.test').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('应用筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(selected,
        {'category': 'linux', 'tag': 'keep', 'tracker': 'tracker.test'});
    expect(tester.takeException(), isNull);
  });
}
