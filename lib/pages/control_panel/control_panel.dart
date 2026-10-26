import 'package:dsm_client/pages/control_panel/external_device/external_device.dart';
import 'package:dsm_client/pages/control_panel/file_service/file_service.dart';
import 'package:dsm_client/pages/control_panel/media_index/media_index.dart';
import 'package:dsm_client/pages/control_panel/network/network.dart';
import 'package:dsm_client/pages/control_panel/power/power.dart';
import 'package:dsm_client/pages/control_panel/public_access/public_access.dart';
import 'package:dsm_client/pages/control_panel/ssh/ssh.dart';
import 'package:dsm_client/pages/control_panel/task_scheduler/task_scheduler.dart';
import 'package:dsm_client/pages/control_panel/update_reset/update_reset.dart';
import 'package:dsm_client/pages/control_panel/user_groups/user_group.dart';
import 'package:dsm_client/pages/control_panel/users/users.dart';
import 'package:dsm_client/util/function.dart';
import 'package:dsm_client/widgets/neu_back_button.dart';

import 'shared_folders/shared_folders.dart';
import 'package:dsm_client/pages/control_panel/info/info.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' hide Badge;

import 'package:dsm_client/widgets/workspace.dart';

class ControlPanel extends StatefulWidget {
  final Map system, notify;
  final List volumes, disks;
  ControlPanel(this.system, this.volumes, this.disks, this.notify);
  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlEntry {
  final String title, detail, icon, route;
  final Widget Function() page;
  _ControlEntry(this.title, this.detail, this.icon, this.route, this.page);
}

class _ControlPanelState extends State<ControlPanel> {
  String query = '';
  Map<String, List<_ControlEntry>> get groups => {
        '文件与账户': [
          _ControlEntry('共享文件夹', '共享空间与访问权限', 'shared_folders', 'share_folders',
              () => SharedFolders()),
          _ControlEntry('文件服务', 'SMB、AFP 与传输服务', 'file_services',
              'file_service', () => FileService()),
          _ControlEntry(Util.version < 7 ? '用户账户' : '用户与群组', '账号及权限管理', 'users',
              'users', () => Users()),
          if (Util.version < 7)
            _ControlEntry(
                '用户群组', '账户分组与权限', 'groups', 'user_groups', () => UserGroups()),
        ],
        '网络与连接': [
          _ControlEntry('外部访问', '远程访问与连接设置', 'public_access', 'public_access',
              () => PublicAccess()),
          _ControlEntry('网络', '接口与网络配置', 'network', 'network', () => Network()),
          if (Util.version >= 7)
            _ControlEntry('终端机和 SNMP', 'SSH 与远程管理', 'terminal_and_SNMP',
                'ssh_setting', () => SshSetting()),
        ],
        '设备与系统': [
          _ControlEntry('信息中心', '设备、网络与系统信息', 'info_center', 'system_info_all',
              () => SystemInfo(0, widget.system, widget.volumes, widget.disks)),
          _ControlEntry('硬件和电源', '风扇、休眠与电源计划', 'hardware_and_power', 'power',
              () => Power()),
          _ControlEntry('外接设备', 'USB 与外部存储设备', 'external_devices',
              'external_device', () => ExternalDevice()),
          _ControlEntry('更新和还原', '系统版本与更新状态', 'update_and_reset',
              'update_reset', () => UpdateReset()),
          if (Util.version < 7)
            _ControlEntry('任务计划', '计划任务与执行记录', 'task_scheduler',
                'task_scheduler', () => TaskScheduler()),
        ],
        '应用服务': [
          _ControlEntry('索引服务', '媒体资料库索引', 'file_index', 'media_index',
              () => MediaIndex()),
          if (Util.version < 7)
            _ControlEntry('终端机和 SNMP', 'SSH 与远程管理', 'terminal_and_SNMP',
                'ssh_setting', () => SshSetting()),
          if (Util.version >= 7)
            _ControlEntry('任务计划', '计划任务与执行记录', 'task_scheduler',
                'task_scheduler', () => TaskScheduler()),
        ],
      };
  Widget tile(_ControlEntry entry, double width) {
    final theme = Theme.of(context);
    final unread = entry.route == 'update_reset'
        ? (widget.notify?['SYNO.SDS.AdminCenter.Update_Reset.Main'] ??
            {})['unread']
        : null;
    return SizedBox(
        width: width,
        child: Material(
            color: theme.cardColor,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: theme.dividerColor)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
                onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                        builder: (_) => entry.page(),
                        settings: RouteSettings(name: entry.route))),
                child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: 152),
                    child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Image.asset(
                                    'assets/control_panel/${Util.version}/${entry.icon}.png',
                                    width: 36,
                                    height: 36,
                                    errorBuilder: (_, __, ___) => Image.asset(
                                        'assets/control_panel/7/${entry.icon}.png',
                                        width: 36,
                                        height: 36)),
                                Spacer(),
                                if (unread != null && '$unread' != '0')
                                  Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                          color:
                                              theme.colorScheme.errorContainer,
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                      child: Text('$unread',
                                          style: TextStyle(
                                              color: theme
                                                  .colorScheme.onErrorContainer,
                                              fontSize: 12))),
                              ]),
                              SizedBox(height: 14),
                              Text(entry.title,
                                  style: theme.textTheme.subtitle2),
                              SizedBox(height: 4),
                              Text(entry.detail,
                                  style: theme.textTheme.caption),
                            ]))))));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = {
      for (final group in groups.entries)
        group.key: group.value
            .where((e) => '${e.title} ${e.detail}'
                .toLowerCase()
                .contains(query.toLowerCase()))
            .toList()
    };
    return Scaffold(
        appBar: AppBar(leading: AppBackButton(context), title: Text('控制面板')),
        body: ListView(padding: EdgeInsets.fromLTRB(20, 0, 20, 28), children: [
          WorkspaceHeader(title: '设备与服务', subtitle: '集中管理 NAS 的账户、连接与系统。'),
          TextField(
              onChanged: (value) => setState(() => query = value),
              decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search), hintText: '搜索设置')),
          for (final group in filtered.entries)
            if (group.value.isNotEmpty) ...[
              Padding(
                  padding: EdgeInsets.only(top: 24, bottom: 12),
                  child: Text(group.key,
                      style: Theme.of(context).textTheme.subtitle1)),
              LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: group.value
                          .map((e) => tile(e, (constraints.maxWidth - 12) / 2))
                          .toList())),
            ],
          if (filtered.values.every((entries) => entries.isEmpty))
            WorkspaceEmpty('没有匹配的设置', icon: Icons.search_off),
        ]));
  }
}
