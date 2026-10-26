// @dart=2.10
import '../lib/models/rr_protocol.dart';
import '../lib/models/dsm_icons.dart';
import '../lib/models/docker_connection.dart';

void expect(bool value, String message) { if (!value) throw StateError(message); }
void main() {
  expect(RrProtocol.decode('{"ok":true,"log":"ready"}')['log'] == 'ready', 'Decode RR log response');
  for (final value in ['<html>login</html>', '{"success":true}', '[]']) {
    var rejected = false; try { RrProtocol.decode(value); } catch (_) { rejected = true; }
    expect(rejected, 'Do not mistake login HTML or DSM API envelopes for RR data');
  }
  RrProtocol.validate('read', {'file':'user-config'}, false);
  for (final action in ['write','save-addons','start-rr-update-online']) {
    var rejected = false; try { RrProtocol.validate(action, {}, false); } catch (_) { rejected = true; }
    expect(rejected, 'RR mutation cannot use the read request path');
  }
  var emptyRejected = false; try { RrProtocol.validate('write', {'file':'user-config','content':' '}, true); }
  catch (_) { emptyRejected = true; }
  expect(emptyRejected, 'Do not overwrite boot configuration with an empty document');
  expect(RrProtocol.selection([{'name':'system-addon','system':'true'}, {'name':'chosen'}, {'name':'off'}],
    {'chosen'}) == 'system-addon,chosen', 'Keep system addons even when filtering or deselecting');

  const config = {'.url': {
    'Drive.Files': {'icon':'images/Drive_{0}.png'},
    'Drive.Console': {'icon':'images/Console_{0}.png'},
  }};
  final icons = DsmIcons.paths('SynologyDrive', config, ['Drive.Console']);
  expect(icons.first == '/webman/3rdparty/SynologyDrive/images/Console_72.png', 'Console uses the NAS console icon');
  expect(icons.contains('/webman/3rdparty/SynologyDrive/images/Console_32.png'), 'Retry sizes shipped by the NAS');
  expect(!icons.any((s) => s.contains('Drive_')), 'Do not substitute the Drive file icon for the console');
  expect(DsmIcons.resolve('https://nas.example:5001', '/webman/icon.png') == 'https://nas.example:5001/webman/icon.png',
    'Resolve native icon on the authenticated NAS');
  for (final path in ['https://evil.example/icon.png', '//evil.example/icon.png', '../private.png',
    'https://user:pass@nas.example:5001/icon.png']) {
    expect(DsmIcons.resolve('https://nas.example:5001', path) == null, 'Never send NAS cookies to external icon hosts');
  }
  expect(DsmIcons.paths('../escape', config, ['Drive.Files']).isEmpty, 'Reject invalid package paths');
  expect(DsmIcons.builtinPaths('FileStation').single.contains('/HelpBrowser/'), 'Use built-in DSM File Station resource');
  expect(DockerConnection.dockhandAddress('https://nas.example:5001/dsm', {'port_bindings':[
    {'host_port':3009,'container_port':3000,'type':'tcp'}]}) == 'http://nas.example:3009', 'Discover Dockhand mapped port, not its container port');
  expect(DockerConnection.dockhandAddress('https://nas.example:5001', {'port_bindings':[
    {'host_port':70000,'container_port':3000}]}) == '', 'Reject invalid mapped port');
  print('RR, NAS icon and Docker discovery tests passed');
}
