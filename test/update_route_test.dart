// @dart=2.10
import '../lib/util/update_route.dart';
import '../lib/models/program_capabilities.dart';

void expect(bool value, String message) { if (!value) throw StateError(message); }
void main() {
  const original = 'https://github.com/318182456/DsmClient/releases/download/dev-15/DsmClient-dev-15-arm64.apk';
  expect(UpdateRoute.download(original, UpdateRoute.domestic) ==
    'https://edgeone.gh-proxy.org/$original', 'Use the user-selected proxy exactly');
  expect(UpdateRoute.download(original, '') == original, 'Direct route preserves official URL');
  expect(UpdateRoute.download(original, 'https://proxy.example.com/prefix/') ==
    'https://proxy.example.com/prefix/$original', 'Preserve custom proxy base paths');
  for (final prefix in ['http://proxy.example.com/', 'https://user:password@proxy.example.com/',
    'https://proxy.example.com/?token=secret', 'https://proxy.example.com/#frag']) {
    var rejected = false; try { UpdateRoute.download(original, prefix); } catch (_) { rejected = true; }
    expect(rejected, 'Reject unsafe proxy configuration');
  }
  for (final value in ['https://evil.example/file.apk', original.replaceFirst('318182456', 'other'),
    '$original?token=private', original.replaceFirst('github.com', 'github.com:8443'),
    original.replaceFirst('DsmClient-dev-15-arm64.apk', '%2Fetc%2Fpasswd')]) {
    var rejected = false; try { UpdateRoute.download(value, UpdateRoute.domestic); } catch (_) { rejected = true; }
    expect(rejected, 'Only proxy this project public release assets');
  }
  for (final id in ['Node.js_v22', 'Node.js_v18', 'python311', 'Python2', 'Perl', 'git',
    'CodecPack', 'OAuthService', 'ReplicationService', 'UnknownFuturePackage']) {
    expect(!ProgramCapabilities.hasWorkspace(id), 'Do not present runtime or placeholder as an application: $id');
  }
  for (final id in ['FileStation', 'AudioStation', 'SynologyDrive', 'HyperBackup',
    'CloudSync', 'ContainerManager', 'SMBService', 'HybridShare', 'rr-manager', 'StorageManager']) {
    expect(ProgramCapabilities.hasWorkspace(id), 'Retain usable native application: $id');
  }
  print('Update route and application capabilities tests passed');
}
