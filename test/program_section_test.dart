// @dart=2.10
import '../lib/models/program_section.dart';

void expect(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  const section = ProgramSection('日志', 'SYNO.CloudSync', 'get_log',
      listKey: 'items',
      params: {'connection_id': 32, 'offset': 0, 'limit': 100});
  final page = section.request(offset: 100, limit: 50);
  expect(
      page['offset'] == 100 && page['limit'] == 50, 'Pagination must advance');
  expect(page['connection_id'] == 32, 'Pagination preserves connection scope');
  expect(
      section.request()['offset'] == 0, 'Requests do not mutate shared params');
  expect(
      section.rows({
            'items': [
              {'name': 'a'},
              null,
              5
            ]
          }).length ==
          1,
      'Ignore malformed records without discarding valid rows');
  const nested = ProgramSection('', '', '', listKey: 'additional.songs');
  expect(
      nested.rows({
            'additional': {
              'songs': [
                {'id': 'one'}
              ]
            }
          }).single['id'] ==
          'one',
      'Handle nested playlist records');
  expect(nested.rows({}).isEmpty, 'Handle missing optional collections');
  const repository = ProgramSection('', 'SYNO.Backup.Repository', 'list');
  final unnamed = {'name': '', 'share': 'Backup', 'repo_id': 7};
  expect(repository.rowTitle(unnamed) == 'Backup',
      'Empty repository names fall back to the shared folder');
  expect(unnamed['name'] == '', 'A display fallback does not rename NAS data');
  expect(repository.rowTitle({'title': '  ', 'name': '文档备份', 'share': 'Backup'}) == '文档备份',
      'Whitespace labels cannot hide a valid user name');
  expect(repository.rowTitle({'name': '', 'share': ' ', 'repo_id': 7}) == '存储库 #7',
      'Missing labels retain a distinguishable repository identifier');
  expect(repository.rowTitle({}) == '未命名存储库', 'Never render a blank repository title');
  expect(section.rowTitle({'name': '', 'task_display_name': '同步任务'}) == '同步任务',
      'Other package lists also skip empty name fields');
  final safe = ProgramSection.publicValue({
    'sid': 'private',
    'SynoToken': 'private',
    'client_session_id': 'private',
    'settings': {
      'password': 'private',
      'pwd': 'private',
      'auth_pass': 'private',
      'max_upload_speed': 20
    },
    'records': [
      {'api_key_secret': 'private', 'status': 'running'}
    ],
  }) as Map;
  expect(!safe.toString().contains('private'),
      'Never render credentials or sessions at any depth');
  expect(
      safe['settings']['max_upload_speed'] == 20 &&
          safe['records'][0]['status'] == 'running',
      'Retain public business fields');
  print('Native program protocol tests passed');
}
