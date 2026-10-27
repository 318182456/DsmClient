// @dart=2.10
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dsm_client/pages/dashborad/applications.dart';
import 'package:dsm_client/pages/packages/qb_rss_rules.dart';
import 'package:dsm_client/util/program_catalog_cache.dart';
import 'package:dsm_client/util/torrent_client.dart';
import 'package:dsm_client/util/function.dart';
import 'package:dsm_client/themes/light.dart';
import 'package:dsm_client/widgets/service_app_icon.dart';

class RuleFixtureClient extends TorrentClient {
  final writes = <Map>[];
  Map rules = {};
  RuleFixtureClient() : super('https://example.test');
  @override
  Future<dynamic> qb(String path,
      {Map<String, String> params, bool post = false}) async {
    if (post) {
      writes.add({'path': path, 'params': params});
      if (path == 'rss/setRule')
        rules[params['ruleName']] = jsonDecode(params['ruleDef']);
      return null;
    }
    if (path == 'rss/rules') return rules;
    if (path == 'torrents/categories')
      return {
        'Existing': {'savePath': '/existing'}
      };
    if (path == 'rss/items')
      return {
        'Linux': {'url': 'https://feed.test/rss'}
      };
    if (path == 'torrents/tags') return ['iso'];
    if (path == 'app/preferences')
      return {
        'rss_auto_downloading_enabled': false,
        'rss_processing_enabled': true
      };
    if (path == 'rss/matchingArticles')
      return {
        'Linux': ['Ubuntu ISO']
      };
    throw StateError('Unexpected read $path');
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ProgramCatalogCache.memory.clear();
  });
  testWidgets(
      'Program search reuses cached catalog, manual refresh forces read, stale failure retains entries',
      (tester) async {
    final oldBase = Util.baseUrl, oldAccount = Util.account;
    Util.baseUrl = '';
    Util.account = 'fixture';
    addTearDown(() {
      Util.baseUrl = oldBase;
      Util.account = oldAccount;
      ProgramCatalogCache.memory.clear();
    });
    var calls = 0;
    Completer<Map> delayed;
    Future<Map> packages() async {
      calls++;
      if (delayed != null) return delayed.future;
      return {
        'success': true,
        'data': {
          'packages': [
            {'id': 'AudioStation', 'name': 'Cached Audio', 'version': '7'}
          ]
        }
      };
    }

    Future<Map> containers() async => {
          'success': true,
          'data': {'containers': []}
        };
    Widget page() => MaterialApp(
        theme: lightTheme,
        home: Scaffold(
            body: ApplicationList([], {}, [], [], {},
                packageLoader: packages,
                containerLoader: containers,
                useCatalogCache: true)));
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Cached Audio'), findsOneWidget);
    await tester.pumpWidget(SizedBox());
    await tester.pumpAndSettle();
    ProgramCatalogCache.memory.clear();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Cached Audio'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(calls, 2);
    await tester.pumpWidget(SizedBox());
    await tester.pumpAndSettle();
    ProgramCatalogCache.memory[ProgramCatalogCache.scope]['time'] = 0;
    delayed = Completer<Map>();
    await tester.pumpWidget(page());
    await tester.pump();
    await tester.pump(Duration(milliseconds: 50));
    expect(find.text('Cached Audio'), findsOneWidget);
    expect(calls, 3);
    delayed.complete({'success': false});
    await tester.pumpAndSettle();
    expect(find.text('Cached Audio'), findsOneWidget);
    await tester.pumpWidget(SizedBox());
    await tester.pumpAndSettle();
    Util.account = 'other';
    delayed = null;
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(calls, 4);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('Service containers use their original artwork widgets',
      (tester) async {
    Future<Map> packages() async => {
          'success': true,
          'data': {'packages': []}
        };
    Future<Map> containers() async => {
          'success': true,
          'data': {
            'containers': [
              {'name': 'qb', 'image': 'linuxserver/qbittorrent'},
              {'name': 'tr', 'image': 'linuxserver/transmission'},
              {'name': 'dockhand', 'image': 'finsys/dockhand'}
            ]
          }
        };
    await tester.pumpWidget(MaterialApp(
        theme: lightTheme,
        home: Scaffold(
            body: ApplicationList([], {}, [], [], {},
                packageLoader: packages, containerLoader: containers))));
    await tester.pumpAndSettle();
    final icons = tester
        .widgetList<ServiceAppIcon>(find.byType(ServiceAppIcon))
        .map((v) => v.service)
        .toSet();
    expect(icons, containsAll(['qbittorrent', 'transmission', 'dockhand']));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(SizedBox());
    await tester.pumpAndSettle();
  });
  Future<void> enter(WidgetTester tester, String label, String value) async {
    final field = find.byKey(ValueKey('rss-rule-field:$label'));
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await tester.pumpAndSettle();
  }

  Widget editor(RuleFixtureClient client, {String name, Map rule = const {}}) =>
      MaterialApp(
          theme: lightTheme,
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => QbRssRuleEditor(client,
                                  name: name,
                                  rule: rule,
                                  feeds: [
                                    {
                                      'url': 'https://feed.test/rss',
                                      'name': 'Linux'
                                    }
                                  ],
                                  presetFeed: 'https://feed.test/rss'))),
                      child: Text('Open')))));
  testWidgets(
      'RSS saves server category, tags, path only after confirmation, preserves latest history',
      (tester) async {
    final client = RuleFixtureClient();
    addTearDown(client.close);
    client.rules = {
      'Linux rule': {
        'enabled': true,
        'affectedFeeds': ['https://feed.test/rss'],
        'previouslyMatchedEpisodes': ['latest-episode'],
        'torrentParams': {'upload_limit': 1234}
      }
    };
    await tester.pumpWidget(editor(client, name: 'Linux rule', rule: {
      'enabled': true,
      'affectedFeeds': ['https://feed.test/rss']
    }));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await enter(tester, '标题包含', 'Ubuntu*');
    await enter(tester, '下载分类', 'Linux');
    await enter(tester, '下载标签', 'iso, linux');
    await enter(tester, '保存目录', '/data/linux');
    await tester.tap(find.text('保存规则'));
    await tester.pumpAndSettle();
    expect(client.writes, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(client.writes, isEmpty);
    await tester.tap(find.text('保存规则'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(client.writes.map((w) => w['path']),
        ['torrents/createCategory', 'rss/setRule']);
    final rule = jsonDecode(client.writes.last['params']['ruleDef']);
    expect(rule['mustContain'], 'Ubuntu*');
    expect(rule['torrentParams']['category'], 'Linux');
    expect(rule['torrentParams']['tags'], ['iso', 'linux']);
    expect(rule['torrentParams']['save_path'], '/data/linux');
    expect(rule['torrentParams']['upload_limit'], 1234);
    expect(rule['previouslyMatchedEpisodes'], ['latest-episode']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(SizedBox());
  });
  testWidgets(
      'RSS duplicate rules write nothing, engine enable requires explicit confirmation',
      (tester) async {
    final client = RuleFixtureClient();
    addTearDown(client.close);
    client.rules = {'Duplicate': {}};
    await tester.pumpWidget(editor(client));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await enter(tester, '规则名称', 'Duplicate');
    await tester.tap(find.text('保存规则'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(client.writes, isEmpty);
    await tester.scrollUntilVisible(find.text('规则名称已存在，请使用其他名称'), 400,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('规则名称已存在，请使用其他名称'), findsOneWidget);
    await tester.pumpWidget(SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
        MaterialApp(theme: lightTheme, home: QbRssRulesPage(client)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(client.writes, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(client.writes, isEmpty);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(client.writes.single['path'], 'app/setPreferences');
    expect(jsonDecode(client.writes.single['params']['json']),
        {'rss_auto_downloading_enabled': true, 'rss_processing_enabled': true});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(SizedBox());
  });
}
