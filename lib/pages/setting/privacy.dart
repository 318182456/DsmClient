import 'package:flutter/material.dart';

class Privacy extends StatelessWidget {
  const Privacy({Key key}) : super(key: key);
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('隐私说明')),
      body: ListView(padding: EdgeInsets.all(24), children: [
        Text('本机数据', style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height: 8),
        Text(
            'NAS 地址、账号、你选择记住的登录信息及界面偏好保存在本机应用数据中。NAS 账号和第三方程序账号分别使用。Dockhand 可选择记住登录信息，密码或 Token 使用系统安全存储加密保存，按 NAS 和服务地址隔离；验证码不保存，可在连接页清除。qBittorrent 和 Transmission 也可选择加密记住登录信息，按 NAS、程序及服务地址隔离，可在连接页清除；关闭记住后不保存密码。'),
        SizedBox(height: 24),
        Text('NAS 与程序连接', style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height: 8),
        Text(
            '登录、文件、照片、备份及管理操作会连接你配置的 NAS 或程序服务。上传、下载与相册备份按你的操作访问本机文件或相册；相关数据会传输到你选择的服务。SSH 终端连接你配置的服务器。'),
        SizedBox(height: 24),
        Text('更新服务', style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height: 8),
        Text(
            '检查及下载更新会访问本项目的 GitHub Releases。更新请求不附带 NAS 会话、账号或密码；GitHub 会收到提供网络服务所必需的连接信息。应用升级安装由 Android 系统确认。'),
        SizedBox(height: 24),
        Text('权限与管理', style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height: 8),
        Text('可在系统设置中管理应用权限及清除本机应用数据。系统权限、远程服务的数据保存方式及账号访问权限由相应系统和服务管理。'),
      ]));
}
