// @dart=2.10
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dsm_client/models/nas_package.dart';
import 'package:dsm_client/models/program_section.dart';
import 'package:dsm_client/pages/packages/drive_console.dart';
import 'package:dsm_client/pages/packages/drive_management.dart';
import 'package:dsm_client/pages/packages/office_management.dart';
import 'package:dsm_client/pages/packages/program_page.dart';
import 'package:dsm_client/util/drive_admin_api.dart';
import 'package:dsm_client/util/function.dart';
import 'package:dsm_client/themes/light.dart';
import 'package:dsm_client/widgets/service_app_icon.dart';
import 'package:extended_image/extended_image.dart';

class FixtureDriveAdmin extends DriveAdminApi {
  final writes = <Map>[];
  FixtureDriveAdmin() : super();
  @override
  Future<dynamic> call(String name, String method,
      {int version = 1, Map<String, dynamic> params = const {}}) async {
    if (name == 'SYNO.AI.Proxy.Provider')
      return {
        'providers': [
          {
            'id': 1,
            'name': '示例 AI 服务',
            'type': 'openai_compat',
            'chat_completion_model': 'example-model',
            'api_key': 'must-not-display'
          }
        ]
      };
    if (name == 'SYNO.AI.Policy.Application')
      return {
        'applications': [
          {'ns': 'Spreadsheet', 'enable_policy': 1, 'provider_id': 1}
        ]
      };
    if (name == 'SYNO.AI.Statistics.Request.Log') return {'logs': []};
    if (name == 'SYNO.AI.Statistics.Request.Log.Setting')
      return {
        'retention_days': 30,
        'max_size': 1000,
        'save_content_output': false
      };
    throw StateError('Unexpected fixture endpoint');
  }

  @override
  Future<Map> status() async => {'csrv_enable': true, 'cstn_freeze': false};
  @override
  Future<Map> summary() async =>
      {'total': 4, 'desktop': 3, 'mobile': 1, 'sharesync': 0};
  @override
  Future<Map> list(String api,
          {int offset = 0, String keyword = '', int logType = -1}) async =>
      {
        'items': api.endsWith('.Connection')
            ? [
                {
                  'client_name': 'Example PC',
                  'client_session_id': 'fixture-session',
                  'client_ip': '192.0.2.1',
                  'client_status': 'on_line',
                  'client_type': 'drive',
                  'last_auth_time': 1800000000
                }
              ]
            : [],
        'total': api.endsWith('.Connection') ? 1 : 0
      };
  @override
  Future<void> disconnect(String id) async {
    writes.add({'disconnect': id});
  }

  @override
  Future<Map> share(String name) async => {
        'share_name': name,
        'share_enable': true,
        'rotate_cnt': 8,
        'rotate_days': 0,
        'rotate_policy': 'smart',
        'disable_download': false,
        'enable_watermark': false
      };
  @override
  Future<void> saveShare(String name, Map<String, dynamic> changes) async {
    writes.add({'name': name, ...changes});
  }

  @override
  Future<Map> settings() async => {
        'default_enable_full_content_indexing': true,
        'sharing_level': 'internal',
        'file_request_enabled': true
      };
  @override
  Future<Map> config() async => {
        'volume_select': '/volume1',
        'volume_list': [
          {'mount_point': '/volume1', 'display': '存储空间 1'}
        ],
        'support_moving_repository': true,
        'enable_non_admin_user_sync': true
      };
  @override
  Future<Map> activation() async =>
      {'activated': true, 'activation_time': 1800000000};
  @override
  Future<Map> fonts() async => {
        'Arial': {'system': true},
        'Example Family': {'system': false, 'disable': true}
      };
  @override
  Future<void> fontAction(String action, List<String> names) async {
    writes.add({'fontAction': action, 'fonts': names});
  }

  @override
  Future<Map> officeSettings() async => {'history_prune': false};
  @override
  Future<void> setOfficeHistory(bool value) async {
    writes.add({'history_prune': value});
  }
}

void main() {
  testWidgets(
      'Shared program details localize backup, cloud, SAN, snapshot and WebDAV schemas',
      (tester) async {
    final cases = <String, Map>{
      'HyperBackup': {
        'state': 'backupable',
        'last_bkp_result': 'done',
        'repo_id': 7
      },
      'CloudSync': {
        'sync_status': 'syncing',
        'remote_path': '/original-english-name'
      },
      'ScsiTarget': {'type_str': 'THIN', 'block_size': 4096},
      'SnapshotReplication': {'snapshot_count': 3, 'worm_lock': true},
      'WebDAVServer': {'enable_depth_infinity': true, 'max_connections': 200},
    };
    final expected = <String, List<String>>{
      'HyperBackup': ['可备份', '已完成', '存储库标识'],
      'CloudSync': ['同步中', '远程路径', '/original-english-name'],
      'ScsiTarget': ['精简配置', '区块大小'],
      'SnapshotReplication': ['快照数量', '不可变锁定'],
      'WebDAVServer': ['允许递归目录查询', '最大连接数'],
    };
    for (final entry in cases.entries) {
      await tester.pumpWidget(MaterialApp(
          theme: lightTheme,
          home: Scaffold(
              body: SingleChildScrollView(
                  child:
                      NativeProperties(entry.value, contextName: entry.key)))));
      await tester.pumpAndSettle();
      for (final text in expected[entry.key])
        expect(find.text(text), findsOneWidget);
    }
    expect(cases['CloudSync']['remote_path'], '/original-english-name');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(SizedBox());
  });
  testWidgets(
      'Transmission artwork is bundled even when NAS supplies a generic container icon',
      (tester) async {
    final old = Util.baseUrl;
    Util.baseUrl = 'https://nas.test';
    addTearDown(() => Util.baseUrl = old);
    await tester.pumpWidget(MaterialApp(
        home: ServiceAppIcon('transmission',
            nasIcon: '/webman/3rdparty/ContainerManager/images/docker.png')));
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName,
        'assets/applications/transmission.png');
    expect(find.byType(ExtendedImage), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(SizedBox());
  });
  testWidgets(
      'Known property labels and states are Chinese without rewriting names or Docker label values',
      (tester) async {
    final data = {
      'Name': 'running',
      'State': {'Status': 'exited'},
      'downloadDir': '/running/Files',
      'Labels': {'state': 'running'},
      'api_key': 'hidden-value'
    };
    await tester.pumpWidget(MaterialApp(
        theme: lightTheme,
        home: Scaffold(
            body: SingleChildScrollView(
                child: NativeProperties(data, contextName: 'docker')))));
    await tester.pumpAndSettle();
    expect(find.text('名称'), findsOneWidget);
    expect(find.text('下载目录'), findsOneWidget);
    expect(find.text('hidden-value'), findsNothing);
    await tester.tap(find.text('状态'));
    await tester.pumpAndSettle();
    expect(find.text('已停止'), findsOneWidget);
    await tester.tap(find.text('标签'));
    await tester.pumpAndSettle();
    expect(find.text('state'), findsOneWidget);
    expect(data['Name'], 'running');
    expect(ProgramSection.sensitive('api_key'), true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(SizedBox());
  });
  testWidgets(
      'Drive console exposes all screenshot modules and disconnect waits for confirmation',
      (tester) async {
    final old = Util.baseUrl;
    Util.baseUrl = '';
    addTearDown(() => Util.baseUrl = old);
    final api = FixtureDriveAdmin();
    await tester.pumpWidget(MaterialApp(
        theme: lightTheme,
        home: DriveConsole(
            NasPackage.fromJson({
              'id': 'SynologyDrive',
              'name': 'Synology Drive',
              'version': '4.0.3'
            }),
            api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Drive 控制台'), findsOneWidget);
    expect(find.text('停止套件'), findsNothing);
    final scroll = find.byType(Scrollable).first;
    for (final title in [
      '客户端列表',
      '日志',
      '团队文件夹',
      '高级功能',
      '设置',
      '字体',
      '版本轮换',
      'AI 助理'
    ]) {
      await tester.scrollUntilVisible(find.text(title), 200,
          scrollable: scroll);
      expect(find.text(title), findsOneWidget);
    }
    await tester.drag(find.byType(ListView), Offset(0, 1800));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('客户端列表'));
    await tester.tap(find.text('客户端列表'));
    await tester.pumpAndSettle();
    expect(find.text('Example PC'), findsOneWidget);
    await tester.tap(find.byTooltip('断开客户端'));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    await tester.tap(find.byTooltip('断开客户端'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(api.writes.single['disconnect'], 'fixture-session');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(SizedBox());
  });
  testWidgets(
      'Team folder and Office history changes do not execute before confirmation',
      (tester) async {
    final api = FixtureDriveAdmin();
    await tester.pumpWidget(
        MaterialApp(theme: lightTheme, home: DriveShareEditor(api, 'Team')));
    await tester.pumpAndSettle();
    final count = find.byKey(ValueKey('drive-share:版本数量（0 表示不保留版本）'));
    await tester.enterText(count, '16');
    await tester.tap(find.text('保存设置'));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    await tester.pumpWidget(SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
        MaterialApp(theme: lightTheme, home: OfficeHistoryPage(api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存设置'));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(api.writes.single, {'history_prune': true});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(SizedBox());
  });
}
