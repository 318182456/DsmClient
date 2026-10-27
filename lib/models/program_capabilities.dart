// @dart=2.10
/// Separate runnable native workspaces from dependencies and desktop-only apps.
/// Runtime dependencies stay in Package Center; desktop apps can expose package management.
class ProgramCapabilities {
  static bool hasContainerWorkspace(String name, String image) {
    final repository = (image ?? '')
        .toLowerCase()
        .split('@')
        .first
        .split('/')
        .last
        .split(':')
        .first;
    if (repository.isNotEmpty)
      return RegExp(
              r'^(arch-)?(dockhand|qbittorrent(vpn)?|transmission(vpn)?)$')
          .hasMatch(repository);
    return RegExp(r'^(dockhand|qbittorrent|transmission)(-\d+)?$')
        .hasMatch((name ?? '').toLowerCase());
  }

  static bool isDependency(String id) =>
      (id ?? '').startsWith('Node.js') ||
      (id ?? '').toLowerCase().startsWith('python') ||
      const {
        'git',
        'Git',
        'Perl',
        'ffmpeg7',
        'CodecPack',
        'ReplicationService',
        'OAuthService',
        'SynologyApplicationService',
        'SimplePermissionManager',
        'UniversalViewer',
        'SynoOnlinePack_v2',
        'SynoAnalytics',
        'synocli-videodriver',
        'synocli-videodriver-tools',
      }.contains(id);
  static bool hasWorkspace(String id) => const {
        'FileStation',
        'SynologyPhotos',
        'StorageManager',
        'ContainerManager',
        'Docker',
        'DownloadStation',
        'AudioStation',
        'Virtualization',
        'SnapshotReplication',
        'SynologyDrive',
        'Spreadsheet',
        'AIConsole',
        'HyperBackup',
        'CloudSync',
        'ScsiTarget',
        'WebDAVServer',
        'HybridShare',
        'SMBService',
        'rr-manager',
      }.contains(id);
}
