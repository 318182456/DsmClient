import 'package:dsm_client/models/nas_package.dart';
import 'package:dsm_client/pages/docker/workspace.dart';
import 'package:dsm_client/pages/docker/detail.dart';
import 'package:dsm_client/pages/download_station/download_station.dart';
import 'package:dsm_client/pages/control_panel/file_service/file_service.dart';
import 'package:dsm_client/pages/packages/packages.dart';
import 'package:dsm_client/models/program_capabilities.dart';
import 'package:dsm_client/util/function.dart';
import 'package:dsm_client/pages/file/file.dart';
import 'package:dsm_client/pages/photos/photos.dart';
import 'package:dsm_client/pages/storage_manager/storage_manager.dart';
import 'package:dsm_client/pages/virtual_machine/virtual_machine.dart';
import 'package:flutter/material.dart';
import 'audio_station.dart';
import 'drive.dart';
import 'program_page.dart';
import 'snapshots.dart';
import 'torrent_program.dart';
import 'rr_program.dart';
import 'office_management.dart';
import 'ai_console.dart';
import 'package:dsm_client/util/drive_admin_api.dart';

Widget nativeContainer(String name, {String image = ''}) {
  final service = '$name $image'.toLowerCase();
  if (service.contains('dockhand'))
    return DockerWorkspace(initialBackend: 'dockhand');
  if (service.contains('qbittorrent')) return TorrentProgram(name);
  if (service.contains('transmission'))
    return TorrentProgram(name, transmission: true);
  return ContainerDetail(name);
}

/// Every installed package has a native route. No WebView fallback.
Widget nativeProgram(NasPackage package) {
  if (!ProgramCapabilities.hasWorkspace(package.id))
    return ProgramPage(package);
  switch (package.id) {
    case 'rr-manager':
      return RrProgram();
    case 'SMBService':
      return FileService();
    case 'FileStation':
      return Files();
    case 'SynologyPhotos':
      return Photos();
    case 'StorageManager':
      return StorageManager();
    case 'ContainerManager':
      return DockerWorkspace();
    case 'Docker':
      return DockerWorkspace();
    case 'DownloadStation':
      return DownloadStation();
    case 'AudioStation':
      return AudioStation();
    case 'Virtualization':
      return VirtualMachine();
    case 'SnapshotReplication':
      return SnapshotProgram();
    case 'SynologyDrive':
      return DrivePage(package);
    case 'Spreadsheet':
      return OfficeConsole(package);
    case 'AIConsole':
      return AiConsolePage(DriveAdminApi());
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
