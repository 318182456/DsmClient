// @dart=2.10
import 'package:flutter_test/flutter_test.dart';
import 'package:dsm_client/util/drive_admin_api.dart';
import 'package:dsm_client/util/ai_console_api.dart';
import 'package:dsm_client/models/program_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'Drive contracts preserve latest share protections and reject invalid writes',
      () async {
    final calls = <Map>[];
    var current = {
      'share_name': 'Team',
      'share_enable': true,
      'share_type': 'normal',
      'rotate_cnt': 8,
      'rotate_days': 0,
      'rotate_policy': 'smart',
      'watermark_text': 'Changed elsewhere',
      'watermark_version': 2
    };
    final api = DriveAdminApi(request: (name, method, version, params) async {
      calls.add({
        'api': name,
        'method': method,
        'version': version,
        'params': params
      });
      if (method == 'list')
        return {
          'success': true,
          'data': {
            'items': [current],
            'total': 1
          }
        };
      if (name == 'SYNO.SynologyDrive.Config' && method == 'get')
        return {
          'success': true,
          'data': {
            'volume_list': [
              {'mount_point': '/volume1'}
            ]
          }
        };
      return {'success': true, 'data': {}};
    });
    await api.saveShare('Team', {'rotate_cnt': 16});
    expect(calls.first['params']['sort_by'], 'share_name');
    expect(calls.first['params']['sort_direction'], 'ASC');
    final submitted = calls.last['params']['share'].single;
    expect(submitted['rotate_cnt'], 16);
    expect(submitted['watermark_text'], 'Changed elsewhere');
    expect(submitted['watermark_version'], 2);
    final before = calls.where((c) => c['method'] == 'set').length;
    await expectLater(
        api.saveShare('Team', {'rotate_cnt': 33}), throwsFormatException);
    await expectLater(
        api.saveSettings({'enable_public_sharing': true}), throwsArgumentError);
    await expectLater(
        api.saveSettings({'db_volume': '/etc'}, serverConfig: true),
        throwsFormatException);
    expect(calls.where((c) => c['method'] == 'set').length, before);
    await api.disconnect('fixture-session');
    expect(calls.last['params'],
        {'client_sess_id': 'fixture-session', 'data_wipe': false});
    await api.list('SYNO.SynologyDrive.Connection');
    expect(calls.last['params']['sort_by'], 'last_auth_time');
    await api.list('SYNO.SynologyDrive.Log', logType: 13);
    expect(calls.last['params']['log_type'], [13]);
    await api.saveSettings({'sharing_level': 'internal'});
    expect(calls.last['version'], 2);
    current = {...current, 'share_name': 'homes'};
    await expectLater(
        api.saveShare('homes', {'share_enable': false}), throwsFormatException);
  });
  test('Office font operations guard system fonts and only transmit names',
      () async {
    final writes = <Map>[];
    final api = DriveAdminApi(request: (name, method, version, params) async {
      if (method == 'list')
        return {
          'success': true,
          'data': {
            'Arial': {'system': true},
            'Custom': {'system': false}
          }
        };
      writes.add({'api': name, 'method': method, 'params': params});
      return {'success': true, 'data': {}};
    });
    await expectLater(
        api.fontAction('disable', ['Arial']), throwsFormatException);
    await expectLater(
        api.fontAction('delete', ['Arial']), throwsFormatException);
    expect(writes, isEmpty);
    await api.fontAction('add', ['Example Family']);
    expect(writes.single['params'], {
      'fonts': ['Example Family']
    });
    await api.fontAction('delete', ['Custom']);
    expect(writes.last['method'], 'delete');
    await api.setOfficeHistory(true);
    expect(writes.last['params'], {'history_prune': true});
  });
  test(
      'AI provider secrets are excluded and application policy updates preserve current exceptions',
      () async {
    final writes = <Map>[];
    final root = DriveAdminApi(request: (name, method, version, params) async {
      if (name == 'SYNO.AI.Proxy.Provider' && method == 'list')
        return {
          'success': true,
          'data': {
            'providers': [
              {
                'id': 1,
                'name': 'Fixture',
                'api_key': 'do-not-display',
                'credentials': {'secret_key': 'hidden'},
                'chat_completion_model': 'fixture-model'
              }
            ]
          }
        };
      if (name == 'SYNO.AI.Policy.Application' && method == 'list')
        return {
          'success': true,
          'data': {
            'applications': [
              {
                'ns': 'Spreadsheet',
                'enable_policy': 2,
                'provider_id': 1,
                'except_user_ids': [12],
                'future_option': 'preserved'
              }
            ]
          }
        };
      writes.add(params);
      return {'success': true, 'data': {}};
    });
    final api = AiConsoleApi(root),
        providers = await AiConsoleApi(root).providers();
    expect(providers.single.containsKey('api_key'), false);
    expect(providers.single.containsKey('credentials'), false);
    await api.policy('Spreadsheet', 2, 1);
    expect(writes.single['applications'].single['except_user_ids'], [12]);
    expect(writes.single['applications'].single['future_option'], 'preserved');
    await api.policy('Spreadsheet', 1, 1);
    expect(writes.last['applications'].single.containsKey('except_user_ids'),
        false);
    expect(
        ProgramSection.publicValue({
          'api_key': 'x',
          'apiKey': 'y',
          'AccessKey': 'z',
          'name': 'visible'
        }),
        {'name': 'visible'});
  });
}
