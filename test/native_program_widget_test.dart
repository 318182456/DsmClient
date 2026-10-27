// @dart=2.10
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dsm_client/pages/dashborad/applications.dart';
import 'package:dsm_client/pages/packages/torrent_program.dart';
import 'package:dsm_client/pages/setting/about.dart';
import 'package:dsm_client/pages/setting/privacy.dart';
import 'package:dsm_client/models/shortcut_item_model.dart';
import 'package:dsm_client/pages/dashborad/shortcut_list.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  testWidgets('URL container shortcuts use the native program route',
      (tester) async {
    final shortcut = ShortcutItemModel.fromJson({
      'className': 'SYNO.SDS.ContainerManager.ContainerDetail.Instance',
      'param': {
        'data': {'name': 'qbittorrent'}
      },
      'title': 'qbittorrent',
      'type': 'url',
      'url': 'https://untrusted.invalid/web',
    });
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: ShortcutList([shortcut], {}, [], [], {}, context,
                      validAppViewOrder: [
                        'SYNO.SDS.ContainerManager.Application'
                      ]),
                ))));
    await tester.tap(find.text('qbittorrent'));
    await tester.pumpAndSettle();
    expect(find.byType(TorrentProgram), findsOneWidget);
    expect(find.text('连接 qBittorrent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'About opens local privacy and license pages without promotion links',
      (tester) async {
    PackageInfo.setMockInitialValues(
        appName: 'DsmClient',
        packageName: 'io.github.user318182456.dsmclient',
        version: '0.1.0',
        buildNumber: '10000',
        buildSignature: '');
    await tester.pumpWidget(MaterialApp(home: About()));
    await tester.pumpAndSettle();
    expect(find.textContaining('10000'), findsOneWidget);
    for (final text in ['加群', 'QQ频道', '公众号', '进入小程序', '打赏']) {
      expect(find.textContaining(text), findsNothing);
    }
    await tester.tap(find.text('隐私说明'));
    await tester.pumpAndSettle();
    expect(find.byType(Privacy), findsOneWidget);
    expect(find.text('本机数据'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('开源许可'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Apache License'), findsWidgets);
    expect(find.text('许可文件加载失败'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Installed programs have searchable, distinct native drawer routes',
      (tester) async {
    tester.binding.window.physicalSizeTestValue = Size(360, 760);
    tester.binding.window.devicePixelRatioTestValue = 1;
    addTearDown(() {
      tester.binding.window.clearPhysicalSizeTestValue();
      tester.binding.window.clearDevicePixelRatioTestValue();
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      drawer: ApplicationList([
        'SYNO.SDS.StorageManager.Instance',
        'SYNO.SDS.AdminCenter.Application'
      ], {}, [], [], {},
          packageLoader: () async => {
                'success': true,
                'data': {
                  'packages': [
                    {'id': 'StorageManager', 'name': '存储空间管理员'},
                    {'id': 'FileStation', 'name': 'File Station'},
                    {'id': 'AudioStation', 'name': 'Audio Station'},
                    {'id': 'CloudSync', 'name': 'Cloud Sync'},
                    {'id': 'HybridShare', 'name': 'Hybrid Share'},
                    {'id': 'HyperBackup', 'name': 'Hyper Backup'},
                    {'id': 'rr-manager', 'name': 'RR Manager'},
                    {'id': 'SynologyDrive', 'name': 'Synology Drive'},
                    {
                      'id': 'Node.js_v22',
                      'name': 'Node.js v22',
                      'version': '22.0',
                      'additional': {
                        'status': 'running',
                        'description': 'JavaScript runtime'
                      }
                    },
                  ]
                }
              },
          containerLoader: () async => {
                'success': true,
                'data': {
                  'containers': [
                    {'name': 'qbittorrent', 'image': 'qbittorrent:latest'},
                    {'name': 'dockhand-postgres', 'image': 'postgres:17'},
                    {'name': 'redis', 'image': 'redis:alpine'},
                  ]
                }
              }),
      body: Builder(
          builder: (context) => TextButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              child: Text('打开菜单'))),
    )));
    await tester.tap(find.text('打开菜单'));
    await tester.pumpAndSettle();
    expect(find.text('NAS 应用'), findsNothing);
    expect(find.text('存储空间管理员'), findsOneWidget);
    expect(find.text('控制面板'), findsOneWidget);
    for (final name in [
      'Audio Station',
      'Cloud Sync',
      'Hybrid Share',
      'Hyper Backup',
      'RR Manager',
      'Synology Drive',
      'Drive 控制台'
    ]) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('File Station'), findsOneWidget);
    tester.binding.window.textScaleFactorTestValue = 1.6;
    addTearDown(() => tester.binding.window.clearTextScaleFactorTestValue());
    await tester.pumpAndSettle();
    final cards = find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.key is ValueKey &&
        '${(widget.key as ValueKey).value}'.startsWith('program-card:'));
    final heights = [
      for (var i = 0; i < cards.evaluate().length; i++)
        tester.getSize(cards.at(i)).height
    ];
    expect(heights.toSet().length, 1);
    final titleOffsets = [
      for (var i = 0; i < cards.evaluate().length; i++)
        ((tester
                        .getTopLeft(find
                            .descendant(
                                of: cards.at(i), matching: find.byType(Text))
                            .first)
                        .dy -
                    tester.getTopLeft(cards.at(i)).dy) *
                100)
            .round()
    ];
    expect(titleOffsets.toSet().length, 1);
    tester.binding.window.textScaleFactorTestValue = 1;
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'postgres');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的程序'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'qbittorrent');
    await tester.pumpAndSettle();
    expect(find.text('Node.js v22'), findsNothing);
    await tester
        .tap(find.byKey(ValueKey('program-card:container:qbittorrent')));
    await tester.pumpAndSettle();
    expect(find.byType(TorrentProgram), findsOneWidget);
    expect(find.text('连接 qBittorrent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Runtime dependencies and placeholder workspaces are hidden from the menu',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      drawer: ApplicationList(['SYNO.SDS.PkgManApp.Instance'], {}, [], [], {},
          packageLoader: () async => {
                'success': true,
                'data': {
                  'packages': [
                    {
                      'id': 'Node.js_v22',
                      'name': 'Node.js v22',
                      'version': '22.0'
                    },
                    {'id': 'git', 'name': 'Git'},
                    {'id': 'python311', 'name': 'Python 3.11'},
                    {'id': 'CodecPack', 'name': 'Codec Pack'},
                    {'id': 'UnknownApp', 'name': 'Unknown App'},
                  ]
                }
              },
          containerLoader: () async => {
                'success': true,
                'data': {'containers': []}
              }),
      body: Builder(
          builder: (context) => TextButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              child: Text('打开菜单'))),
    )));
    await tester.tap(find.text('打开菜单'));
    await tester.pumpAndSettle();
    expect(find.text('套件中心'), findsOneWidget);
    expect(find.text('Node.js v22'), findsNothing);
    expect(find.text('Git'), findsNothing);
    expect(find.text('Python 3.11'), findsNothing);
    expect(find.text('Codec Pack'), findsNothing);
    expect(find.text('Unknown App'), findsNothing);
    expect(find.textContaining('未接入'), findsNothing);
    expect(find.textContaining('打开 DSM'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Service connection rejects an invalid URL and keeps passwords obscured',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: TorrentProgram('qbittorrent')));
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.last.obscureText, isTrue);
    await tester.enterText(find.byType(TextField).first, 'file:///private');
    await tester.pump(Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(find.textContaining('请输入不含账号'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
