// @dart=2.10
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dsm_client/util/backup_cloud_api.dart';
import 'package:dsm_client/pages/packages/backup_cloud_create.dart';
import 'package:dsm_client/themes/light.dart';

void main() {
  test(
      'Local backup uses multi-version repository then task with selected source and schedule',
      () async {
    final calls = <Map>[];
    final api = BackupCloudApi(request: (s, p) async {
      calls.add({'api': s.api, 'method': s.method, ...p});
      return {
        'success': true,
        'data': s.api.endsWith('Share.Local')
            ? {
                'share_list': [
                  ['Destination', 0, '', '/volume1', false]
                ]
              }
            : s.api.endsWith('Source.Folder')
                ? {
                    'folder': [
                      {'id': '/Source', 'disabled': false}
                    ]
                  }
                : s.api.endsWith('Repository')
                    ? {'repo_id': 42}
                    : {}
      };
    });
    final params = BackupCloudApi.localBackup(
        name: 'Example backup',
        share: 'Destination',
        folder: 'NewBackup',
        sources: ['/Source'],
        daily: true,
        hour: 3,
        minute: 15);
    final id = await api.createRepository(params);
    await api.createBackupTask(params, id);
    expect(calls.where((c) => c['method'] == 'create').map((c) => c['api']),
        ['SYNO.Backup.Repository', 'SYNO.Backup.Task']);
    expect(calls.last['repo_id'], 42);
    expect(params['target_type'], 'image');
    expect(params['transfer_type'], 'image_local');
    expect(params['target_id'], 'NewBackup.hbk');
    expect(params['source']['file_list'], ['/Source']);
    expect(params['schedule']['hour'], 3);
    expect(params['schedule']['min'], 15);
    expect(params['rotate_params']['enable_rotate'], false);
    expect(
        () => BackupCloudApi.localBackup(
            name: 'x',
            share: 'Destination',
            folder: '../old',
            sources: ['/Source']),
        throwsFormatException);
    expect(
        () => BackupCloudApi.localBackup(
            name: 'x',
            share: 'Destination',
            folder: 'New',
            sources: ['/Destination']),
        throwsFormatException);
  });
  test(
      'Cloud creation validates first and does not create after validation failure',
      () async {
    final methods = <String>[];
    bool valid = false;
    final api = BackupCloudApi(request: (s, p) async {
      methods.add(s.method);
      return {
        'success': s.method != 'test_task_setting' || valid,
        'data': {'filtered_paths': [], 'filtered_extensions': []},
        'error': {'code': 400}
      };
    });
    final info = await api.cloudTask(
        {'client_type': 'wd', 'auth_pass': 'fixture-only'},
        name: 'Sync',
        local: '/Source/folder',
        remote: {'path': '/', 'file_id': ''},
        direction: 'ONLY_UPLOAD');
    expect(info['path_share'], 'Source');
    expect(info['path_sync'], '/folder');
    expect(info['sync_direction'], 'ONLY_UPLOAD');
    expect(info['no_delete'], true);
    expect(info['server_encryption'], false);
    await expectLater(api.createCloud(info), throwsStateError);
    expect(methods, isNot(contains('create_link')));
    valid = true;
    await api.createCloud(info);
    expect(methods.sublist(methods.length - 2),
        ['test_task_setting', 'create_link']);
    final bidirectional = await api.cloudTask({'client_type': 'bd'},
        name: 'Baidu',
        local: '/Source',
        remote: {'path': '/', 'file_id': ''},
        direction: 'BIDIRECTION');
    expect(bidirectional['no_delete'], false);
  });
  testWidgets('Local backup creation waits for user confirmation',
      (tester) async {
    final writes = <String>[];
    final api = BackupCloudApi(request: (s, p) async {
      if (s.method == 'create') writes.add(s.api);
      return {
        'success': true,
        'data': s.api.endsWith('Share.Local')
            ? {
                'share_list': [
                  ['Destination', 0, '', '/volume1', false]
                ]
              }
            : s.api.endsWith('Source.Folder')
                ? {
                    'folder': [
                      {'id': '/Source', 'text': 'Source', 'disabled': false}
                    ]
                  }
                : {'repo_id': 42}
      };
    });
    await tester.pumpWidget(
        MaterialApp(theme: lightTheme, home: LocalBackupCreate(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Source'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('创建备份任务'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建备份任务'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(SizedBox());
  });
  testWidgets(
      'Cloud creation offers WebDAV and Baidu without creating a task on entry',
      (tester) async {
    await tester
        .pumpWidget(MaterialApp(theme: lightTheme, home: CloudSyncCreate()));
    await tester.pumpAndSettle();
    expect(find.text('WebDAV 服务地址'), findsOneWidget);
    await tester.tap(find.text('验证并连接'));
    await tester.pumpAndSettle();
    expect(find.text('请填写 WebDAV 服务地址、账号和密码'), findsOneWidget);
    await tester.tap(find.text('WebDAV').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('百度网盘').last);
    await tester.pumpAndSettle();
    expect(find.text('登录并授权百度网盘'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(SizedBox());
  });
}
