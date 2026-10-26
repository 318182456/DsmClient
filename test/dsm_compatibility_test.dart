// @dart=2.10
// Standalone protocol regression tests: no Flutter, package downloads or NAS required.
import 'dart:convert';

import '../lib/models/api_model.dart';
import '../lib/models/nas_package.dart';
import '../lib/util/dsm_compatibility.dart';

void expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  expect(
      DsmCompatibility.firmwareVersion('DSM 7.4.1-90080 Update 1') ==
          '7.4.1-90080',
      'DSM 7.4.1 firmware parsing');
  expect(DsmCompatibility.firmwareMajor('7.4.1-90080') == 7,
      'Firmware without DSM prefix');
  expect(
      DsmCompatibility.firmwareMajor('DSM 6.2.4-25556') == 6, 'DSM 6 fallback');
  expect(DsmCompatibility.firmwareVersion(null).isEmpty, 'Missing firmware');
  final auth = ApiModel.fromJson(
      {'minVersion': 1, 'maxVersion': 7, 'path': 'entry.cgi'});
  expect(DsmCompatibility.supportedVersion(auth, 6) == 6,
      'Keep documented auth version 6 instead of forcing latest version');
  final upload = ApiModel.fromJson(
      {'minVersion': 2, 'maxVersion': 3, 'path': 'entry.cgi'});
  expect(DsmCompatibility.supportedVersion(upload, 3) == 3,
      'Upload chooses supported preferred version, not minimum');
  expect(DsmCompatibility.supportedVersion(upload, 1) == 2,
      'Respect minimum supported version');
  expect(DsmCompatibility.supportedVersion(upload, 9) == 3,
      'Respect maximum supported version');
  expect(DsmCompatibility.supportedVersion(null, 2) == 2,
      'Missing catalog does not crash');
  expect(DsmCompatibility.apiPath(auth, 'auth.cgi') == 'entry.cgi',
      'Use discovered auth path');
  expect(
      DsmCompatibility.apiPath(
              ApiModel(path: 'https://evil.invalid/a.cgi'), 'entry.cgi') ==
          'entry.cgi',
      'Reject absolute API endpoints');
  expect(
      DsmCompatibility.apiPath(ApiModel(path: '../auth.cgi'), 'entry.cgi') ==
          'entry.cgi',
      'Reject path traversal');
  final original = <String, dynamic>{
    'api': '"SYNO.FileStation.Upload"',
    'version': 1,
    'path': '"/photos"'
  };
  final prepared = DsmCompatibility.prepareParameters(
      original, {'SYNO.FileStation.Upload': upload});
  expect(prepared['version'] == 2 && prepared['path'] == '"/photos"',
      'Preserve JSON encoded business parameters');
  expect(original['version'] == 1, 'Do not mutate caller parameters');
  final compound = DsmCompatibility.prepareParameters({
    'api': 'SYNO.Entry.Request',
    'version': 1,
    'compound': jsonEncode([
      {'api': 'SYNO.FileStation.Upload', 'version': 9}
    ]),
  }, {
    'SYNO.FileStation.Upload': upload
  });
  expect(jsonDecode(compound['compound'])[0]['version'] == 3,
      'Negotiate nested compound API versions');
  final tokens = DsmSessionTokens();
  tokens.remember('https://nas-a.invalid:5001/', 'sid-a', 'token-a');
  tokens.remember('https://nas-b.invalid:5001', 'sid-b', 'token-b');
  expect(tokens.tokenFor('https://NAS-A.invalid:5001', 'sid-a') == 'token-a',
      'Normalize host casing and trailing slash');
  expect(tokens.tokenFor('https://nas-b.invalid:5001', 'sid-a').isEmpty,
      'Never reuse token on a different NAS');
  expect(tokens.tokenFor('https://nas-a.invalid:5001', 'sid-b').isEmpty,
      'Never reuse token for a different account session');
  expect(tokens.tokenFor('http://nas-a.invalid:5001', 'sid-a').isEmpty,
      'Never reuse HTTPS token over HTTP');
  expect(tokens.tokenFor('https://nas-a.invalid:5001/proxy', 'sid-a').isEmpty,
      'Keep reverse proxy paths separate');
  tokens.clear();
  expect(tokens.tokenFor('https://nas-a.invalid:5001', 'sid-a').isEmpty,
      'Clear session tokens on logout');
  final package = NasPackage.fromJson({
    'id': 'Example',
    'name': 'Example App',
    'version': '1.0',
    'additional': {
      'status': 'running',
      'dsm_apps':
          ' APP.Main.Application  APP.Main.InternalComponent APP.Other.Instance '
    },
  });
  expect(package.appIds.length == 3, 'Parse whitespace-separated DSM registry');
  expect(package.launchApps(['APP.Main.Application']).length == 1,
      'Only launch desktop applications, not internal component classes');
  expect(package.launchApps(['UNINSTALLED.Application']).isEmpty,
      'Do not create guessed launch targets');
  final service = NasPackage.fromJson({'id': 'Runtime', 'additional': {}});
  expect(service.appIds.isEmpty && service.name == 'Runtime',
      'Show background services without inventing a web interface');
  expect(
      NasPackage.parseAppIds(['APP.Main.Application', 'javascript:alert(1)'])
              .length ==
          1,
      'Reject invalid application identifiers');
  print('DSM compatibility regression tests passed.');
}
