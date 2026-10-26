// @dart=2.10
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dsm_client/pages/dashborad/applications.dart';
import 'package:dsm_client/pages/packages/program_page.dart';
import 'package:dsm_client/pages/packages/torrent_program.dart';
import 'package:dsm_client/pages/setting/about.dart';
import 'package:dsm_client/pages/setting/privacy.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  testWidgets(
      'About opens local privacy and license pages without promotion links',
      (tester) async {
    PackageInfo.setMockInitialValues(
        appName: 'DsmClient',
        packageName: 'fit.flutter.dsm_helper',
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
      drawer:
          ApplicationList(['SYNO.SDS.StorageManager.Instance'], {}, [], [], {},
              packageLoader: () async => {
                    'success': true,
                    'data': {
                      'packages': [
                        {'id': 'StorageManager', 'name': '存储空间管理员'},
                        {'id': 'FileStation', 'name': 'File Station'},
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
    expect(find.text('File Station'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'qbittorrent');
    await tester.pumpAndSettle();
    expect(find.text('Node.js v22'), findsNothing);
    await tester
        .tap(find.byKey(ValueKey('program-card:container:qbittorrent')));
    await tester.pumpAndSettle();
    expect(find.byType(TorrentProgram), findsOneWidget);
    expect(find.text('连接 qBittorrent API'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Unsupported programs describe their scope without a web fallback',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      drawer: ApplicationList([], {}, [], [], {},
          packageLoader: () async => {
                'success': true,
                'data': {
                  'packages': [
                    {
                      'id': 'Node.js_v22',
                      'name': 'Node.js v22',
                      'version': '22.0'
                    },
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
    await tester.enterText(find.byType(TextField), 'Node');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Node.js v22'));
    await tester.pumpAndSettle();
    expect(find.byType(ProgramPage), findsOneWidget);
    expect(find.textContaining('专用业务功能尚未接入'), findsOneWidget);
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
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(find.textContaining('请输入不含账号'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
