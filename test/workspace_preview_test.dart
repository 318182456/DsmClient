// @dart=2.10
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dsm_client/themes/light.dart';
import 'package:dsm_client/themes/dark.dart';
import 'package:dsm_client/pages/packages/audio_station.dart';
import 'package:dsm_client/pages/docker/dockhand.dart';
import 'package:dsm_client/pages/control_panel/control_panel.dart';
import 'package:dsm_client/pages/login/login.dart';
import 'package:dsm_client/widgets/surfaces.dart' as surfaces;
import 'package:dsm_client/widgets/adaptive_tab_bar.dart';
import 'package:dsm_client/pages/dashborad/applications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dsm_client/pages/packages/torrent_program.dart';
import 'torrent_workspace_test.dart' show FixtureTorrentClient;
import 'dockhand_stats_widget_test.dart' show FixtureDockhandClient;
import 'torrent_features_widget_test.dart' show RssFixtureClient;
import 'program_cache_rss_widget_test.dart' show RuleFixtureClient;
import 'package:dsm_client/pages/packages/qb_rss_rules.dart';
import 'package:dsm_client/pages/packages/torrent_rss.dart';
import 'package:dsm_client/util/program_pins.dart';
import 'drive_localization_widget_test.dart' show FixtureDriveAdmin;
import 'package:dsm_client/models/nas_package.dart';
import 'package:dsm_client/pages/packages/drive_console.dart';
import 'package:dsm_client/pages/packages/drive_management.dart';
import 'package:dsm_client/pages/packages/office_management.dart';
import 'package:dsm_client/pages/packages/ai_console.dart';
import 'package:dsm_client/pages/packages/program_page.dart';
import 'package:dsm_client/widgets/service_app_icon.dart';
import 'package:dsm_client/pages/packages/backup_cloud_create.dart';
import 'package:dsm_client/util/backup_cloud_api.dart';

void main() {
  testWidgets('Render temporary design review previews when requested',
      (tester) async {
    final directory = Platform.environment['DSM_UI_PREVIEW_DIR'] ?? '';
    if (directory.isEmpty) return;
    final root = Platform.environment['RUNNER_TEMP'];
    await tester.runAsync(() async {
      final loader = FontLoader('ReviewFont');
      loader.addFont(File('$root/dsm-review-font.otf')
          .readAsBytes()
          .then((v) => ByteData.view(v.buffer)));
      await loader.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(File(
              '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          .readAsBytes()
          .then((v) => ByteData.view(v.buffer)));
      await icons.load();
    });
    tester.binding.window.physicalSizeTestValue = Size(390, 844);
    tester.binding.window.devicePixelRatioTestValue = 1;
    addTearDown(() {
      tester.binding.window.clearPhysicalSizeTestValue();
      tester.binding.window.clearDevicePixelRatioTestValue();
    });
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final output = Directory(directory)..createSync(recursive: true);
    ThemeData reviewTheme(ThemeData theme) => theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'ReviewFont'),
        appBarTheme: theme.appBarTheme.copyWith(
            titleTextStyle: theme.appBarTheme.titleTextStyle
                .copyWith(fontFamily: 'ReviewFont')),
        tabBarTheme: theme.tabBarTheme.copyWith(
            labelStyle:
                theme.tabBarTheme.labelStyle.copyWith(fontFamily: 'ReviewFont'),
            unselectedLabelStyle: theme.tabBarTheme.unselectedLabelStyle
                .copyWith(fontFamily: 'ReviewFont')));
    Future<void> capture(String name, Widget page, ThemeData theme) async {
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: reviewTheme(theme),
              home: page)));
      await tester.pumpAndSettle();
      if (name == 'transmission-icon') {
        await tester.runAsync(() => precacheImage(
            AssetImage('assets/applications/transmission.png'),
            key.currentContext));
        await tester.pumpAndSettle();
      }
      if (name == 'rss-rule-settings') {
        await tester.ensureVisible(find.byKey(ValueKey('rss-rule-field:下载分类')));
        await tester.pumpAndSettle();
      }
      if (name == 'rss-articles') {
        await tester.tap(find.text('Linux'));
        await tester.pumpAndSettle();
      }
      if (name == 'dockhand-stats') {
        await tester.enterText(
            find.byType(TextField).first, 'https://example.test');
        await tester.pump(Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(1), 'demo');
        await tester.enterText(find.byType(TextField).last, 'fixture');
        await tester.ensureVisible(find.text('连接 Dockhand'));
        await tester.tap(find.text('连接 Dockhand'));
        await tester.pumpAndSettle();
      }
      if (name == 'torrent-light' || name == 'torrent-dark') {
        await tester.enterText(
            find.byType(TextField).first, 'https://example.test');
        await tester.pump(Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('连接'));
        await tester.tap(find.text('连接'));
        await tester.pumpAndSettle();
      }
      if (name == 'media-menu') {
        await tester.longPress(find.text('测试歌曲'));
        await tester.pumpAndSettle();
      }
      if (name == 'program-picker') {
        await tester.tap(find.text('添加'));
        await tester.pumpAndSettle();
        await tester.tap(find
            .byKey(ValueKey('program-card:SYNO.SDS.AdminCenter.Application')));
        await tester.pumpAndSettle();
      }
      if (name == 'program-cards' ||
          name == 'program-pins' ||
          name == 'program-picker') {
        await tester.runAsync(() async {
          for (final icon in [
            'control_panel',
            'storage_manager',
            'resource_monitor'
          ]) {
            await precacheImage(AssetImage('assets/applications/7/$icon.png'),
                key.currentContext);
          }
        });
        await tester.pumpAndSettle();
      }
      if (page is ControlPanel) {
        await tester.runAsync(() async {
          for (final icon in [
            'shared_folders',
            'file_services',
            'users',
            'public_access',
            'network',
            'terminal_and_SNMP',
            'info_center',
            'hardware_and_power',
            'external_devices',
            'update_and_reset',
            'file_index',
            'task_scheduler'
          ]) {
            await precacheImage(AssetImage('assets/control_panel/7/$icon.png'),
                key.currentContext);
          }
        });
        await tester.pumpAndSettle();
      }
      await tester.runAsync(() async {
        final boundary =
            key.currentContext.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${output.path}/$name.png')
            .writeAsBytesSync(bytes.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(SizedBox());
      await tester.pumpAndSettle();
    }

    AudioStation music() => AudioStation(
        loader: (section, params) async => {
              'success': true,
              'data': {
                'total': 8,
                'songs': [
                  for (final song in [
                    '孤独患者',
                    '哎呀咿呀',
                    '看穿',
                    '吟游诗人',
                    '张氏情歌',
                    'Baby Song',
                    '听一千遍后',
                    '이 사랑'
                  ])
                    {
                      'id': song,
                      'title': song,
                      'additional': {
                        'song_tag': {
                          'artist': song == '이 사랑' ? 'DAVICHI' : '陈奕迅',
                          'album': '音乐资料库'
                        },
                        'song_audio': {'duration': 245}
                      }
                    }
                ]
              }
            });
    final backupApi = BackupCloudApi(
        request: (s, p) async => {
              'success': true,
              'data': s.api.endsWith('Share.Local')
                  ? {
                      'share_list': [
                        ['Backup', 0, '', '/volume1', false]
                      ]
                    }
                  : {
                      'folder': [
                        {'id': '/Documents', 'text': '文档', 'disabled': false},
                        {'id': '/Photos', 'text': '照片', 'disabled': false}
                      ]
                    }
            });
    await capture(
        'backup-create', LocalBackupCreate(api: backupApi), lightTheme);
    await capture('cloud-create', CloudSyncCreate(api: backupApi), lightTheme);
    await capture(
        'backup-properties',
        Scaffold(
            appBar: AppBar(title: Text('备份存储库')),
            body: NativeProperties({
              'name': '重要文件备份',
              'share': 'Backup',
              'target_type': 'image',
              'transfer_type': 'image_local',
              'repo_id': 1,
              'state': 'backupable',
              'last_bkp_result': 'done'
            }, contextName: 'HyperBackup')),
        lightTheme);
    final driveApi = FixtureDriveAdmin();
    await capture(
        'drive-console',
        DriveConsole(
            NasPackage.fromJson({
              'id': 'SynologyDrive',
              'name': 'Synology Drive',
              'version': '4.0.3'
            }),
            api: driveApi),
        lightTheme);
    await capture(
        'drive-team-folder', DriveShareEditor(driveApi, '团队资料'), lightTheme);
    await capture('drive-settings', DriveSettingsPage(driveApi), lightTheme);
    await capture('office-fonts', OfficeFontsPage(driveApi), lightTheme);
    await capture('ai-console', AiConsolePage(driveApi), lightTheme);
    await capture(
        'torrent-properties',
        Scaffold(
            appBar: AppBar(title: Text('任务详情')),
            body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: NativeProperties({
                  'downloadDir': '/data/downloads',
                  'total_downloaded': 1048576,
                  'uploadRatio': 1.5,
                  'eta': 120,
                  'state': 4
                }, contextName: 'transmission'))),
        lightTheme);
    await capture(
        'dockhand-properties',
        Scaffold(
            appBar: AppBar(title: Text('容器配置')),
            body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: NativeProperties({
                  'Name': 'example-service',
                  'State': 'exited',
                  'RestartPolicy': {'Name': 'always'},
                  'NetworkSettings': {'IPAddress': '192.0.2.1'}
                }, contextName: 'docker'))),
        lightTheme);
    await capture(
        'transmission-icon',
        Scaffold(
            appBar: AppBar(title: Text('Transmission')),
            body: Center(child: ServiceAppIcon('transmission', size: 128))),
        lightTheme);
    await capture('music-light', music(), lightTheme);
    await capture('music-dark', music(), darkTheme);
    await capture(
        'rss-articles',
        TorrentRssPage(client: RssFixtureClient(), profile: 'preview'),
        lightTheme);
    await ProgramPins.toggle('SYNO.SDS.AdminCenter.Application');
    final rssClient = RuleFixtureClient();
    rssClient.rules = {
      'Linux ISO': {
        'enabled': true,
        'affectedFeeds': ['https://feed.test/rss'],
        'mustContain': 'Ubuntu*',
        'torrentParams': {
          'category': 'Linux',
          'tags': ['iso'],
          'save_path': '/data/linux'
        }
      }
    };
    await capture('rss-rules', QbRssRulesPage(rssClient), lightTheme);
    QbRssRuleEditor ruleEditor() => QbRssRuleEditor(rssClient,
            name: 'Linux ISO',
            rule: rssClient.rules['Linux ISO'],
            feeds: [
              {'url': 'https://feed.test/rss', 'name': 'Linux 发行版'}
            ],
            categories: {
              'Linux': {}
            },
            knownTags: [
              'iso',
              'linux'
            ]);
    await capture('rss-rule-editor', ruleEditor(), lightTheme);
    await capture('rss-rule-settings', ruleEditor(), lightTheme);
    rssClient.close();
    await capture(
        'program-pins',
        Scaffold(
            appBar: AppBar(title: Text('控制台')),
            body: ApplicationList(
                ['SYNO.SDS.AdminCenter.Application'], {}, [], [], {},
                pinnedOnly: true,
                packageLoader: () async => {
                      'success': true,
                      'data': {'packages': []}
                    },
                containerLoader: () async => {
                      'success': true,
                      'data': {'containers': []}
                    })),
        lightTheme);
    await ProgramPins.toggle('SYNO.SDS.AdminCenter.Application');
    await capture(
        'program-picker',
        Scaffold(
            appBar: AppBar(title: Text('控制台')),
            body: SingleChildScrollView(
                child: ApplicationList([
              'SYNO.SDS.AdminCenter.Application',
              'SYNO.SDS.ResourceMonitor.Instance'
            ], {}, [], [], {},
                    pinnedOnly: true,
                    packageLoader: () async => {
                          'success': true,
                          'data': {'packages': []}
                        },
                    containerLoader: () async => {
                          'success': true,
                          'data': {'containers': []}
                        }))),
        lightTheme);
    await capture(
        'torrent-light',
        TorrentProgram('review',
            clientFactory: (_, __) => FixtureTorrentClient()),
        lightTheme);
    await capture(
        'torrent-dark',
        TorrentProgram('review-dark',
            transmission: true,
            clientFactory: (_, __) => FixtureTorrentClient(transmission: true)),
        darkTheme);
    await capture(
        'dockhand-connect', DockhandProgram(profile: 'review'), lightTheme);
    await capture(
        'dockhand-stats',
        DockhandProgram(
            profile: 'review-stats',
            clientFactory: (_) => FixtureDockhandClient()),
        lightTheme);
    await capture('control-panel', ControlPanel({}, [], [], {}), lightTheme);
    SharedPreferences.setMockInitialValues({'agreement': '1', 'read': '1'});
    Login login() => Login(server: {
          'https': true,
          'host': 'nas.example.test',
          'port': '65535',
          'account': 'demo-user',
          'password': 'fixture-only',
          'note': '测试 NAS',
          'auto_login': true,
          'remember_password': true,
          'check_ssl': true,
          'cookie': '',
          'sid': '',
          'action': 'edit'
        });
    await capture('login-light', login(), lightTheme);
    await capture('login-dark', login(), darkTheme);
    await capture(
        'legacy-form',
        Scaffold(
            appBar: AppBar(title: Text('表单边框检查')),
            body: Padding(
                padding: EdgeInsets.all(20),
                child: surfaces.NeuCard(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                        decoration: InputDecoration(
                            border: InputBorder.none,
                            labelText: '单层边框',
                            hintText: '旧页面的输入框'))))),
        lightTheme);
    await capture(
        'button-tabs',
        DefaultTabController(
            length: 3,
            child: Scaffold(
                appBar: AppBar(title: Text('按钮与分类')),
                body: Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(children: [
                      AdaptiveTabBar(tabs: [
                        Tab(text: '文件'),
                        Tab(text: '下载'),
                        Tab(text: '设置')
                      ]),
                      SizedBox(height: 24),
                      SizedBox(
                          width: double.infinity,
                          height: 64,
                          child: surfaces.NeuButton(
                              onPressed: () {}, child: Text('确认操作'))),
                      SizedBox(height: 24),
                      SizedBox(
                          width: 96,
                          height: 96,
                          child: surfaces.NeuButton(
                              onPressed: () {},
                              decoration: surfaces.NeumorphicDecoration(
                                  shape: BoxShape.circle),
                              child: Text('取消'))),
                    ])))),
        lightTheme);
    await capture(
        'media-menu',
        AudioLibrary('歌曲', 'Song', 'songs',
            loader: (section, params) async => {
                  'success': true,
                  'data': {
                    'total': 2,
                    'songs': [
                      {'id': 'a', 'title': '测试歌曲'},
                      {'id': 'b', 'title': '下一首'}
                    ]
                  }
                }),
        lightTheme);
    await capture(
        'program-cards',
        Scaffold(
            appBar: AppBar(title: Text('程序卡片')),
            body: ApplicationList([
              'SYNO.SDS.AdminCenter.Application',
              'SYNO.SDS.StorageManager.Instance',
              'SYNO.SDS.ResourceMonitor.Instance'
            ], {}, [], [], {},
                packageLoader: () async => {
                      'success': true,
                      'data': {'packages': []}
                    },
                containerLoader: () async => {
                      'success': true,
                      'data': {'containers': []}
                    })),
        lightTheme);
  });
}
