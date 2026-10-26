import 'package:dsm_client/models/nas_package.dart';
import 'package:dsm_client/pages/docker/docker.dart';
import 'package:dsm_client/pages/download_station/download_station.dart';
import 'package:dsm_client/pages/file/file.dart';
import 'package:dsm_client/pages/photos/photos.dart';
import 'package:dsm_client/pages/storage_manager/storage_manager.dart';
import 'package:dsm_client/pages/virtual_machine/virtual_machine.dart';
import 'package:flutter/material.dart';
import 'audio_station.dart';
import 'drive.dart';
import 'program_page.dart';

/// Every installed package has a native route. No WebView fallback.
Widget nativeProgram(NasPackage package) {
  switch (package.id) {
    case 'FileStation':
      return Files();
    case 'SynologyPhotos':
      return Photos();
    case 'StorageManager':
      return StorageManager();
    case 'ContainerManager':
      return Docker(title: 'Container Manager');
    case 'Docker':
      return Docker();
    case 'DownloadStation':
      return DownloadStation();
    case 'AudioStation':
      return AudioStation();
    case 'Virtualization':
      return VirtualMachine();
    case 'SynologyDrive':
      return DrivePage(package);
    default:
      return ProgramPage(package);
  }
}

IconData programIcon(String id) {
  switch (id) {
    case 'SynologyDrive':
      return Icons.cloud_outlined;
    case 'AudioStation':
      return Icons.library_music;
    case 'HyperBackup':
      return Icons.backup_outlined;
    case 'CloudSync':
      return Icons.cloud_sync_outlined;
    case 'FileStation':
      return Icons.folder;
    case 'SynologyPhotos':
      return Icons.photo_library_outlined;
    case 'ContainerManager':
    case 'Docker':
      return Icons.view_in_ar;
    case 'Tailscale':
      return Icons.vpn_key_outlined;
    case 'ScsiTarget':
      return Icons.storage;
    case 'SnapshotReplication':
      return Icons.restore;
    case 'WebDAVServer':
      return Icons.folder_shared_outlined;
    case 'HybridShare':
      return Icons.cloud_queue;
    case 'Spreadsheet':
      return Icons.table_chart_outlined;
    case 'SynoFinder':
      return Icons.search;
    case 'AIConsole':
      return Icons.auto_awesome;
    case 'terminal':
      return Icons.terminal;
    default:
      return Icons.apps;
  }
}
