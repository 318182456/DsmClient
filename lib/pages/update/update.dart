import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:dsm_client/util/update_download.dart';
import 'package:dsm_client/themes/app_theme.dart';
import 'package:dsm_client/util/function.dart';
import 'package:dsm_client/widgets/animation_progress_bar.dart';
import 'package:dsm_client/widgets/neu_back_button.dart';
import 'package:easy_app_installer/easy_app_installer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:neumorphic/neumorphic.dart';
import 'package:url_launcher/url_launcher_string.dart';

class Update extends StatefulWidget {
  final Map data;
  final bool direct;
  Update(this.data, {this.direct: false});
  @override
  _UpdateState createState() => _UpdateState();
}

class _UpdateState extends State<Update> {
  bool downloading = false;
  double progress = 0;
  String fileName = '';
  String statusText = '可在应用内下载并安装更新';
  String localApk;
  final updater = UpdateDownload();

  @override
  void initState() {
    super.initState();
    fileName = "DsmClient-${widget.data['buildVersionNo']}.apk";
    if (widget.direct) Future.microtask(download);
  }

  @override
  void dispose() {
    updater.pause();
    super.dispose();
  }

  Future<void> download() async {
    if (downloading) return;
    if (!Platform.isAndroid) {
      Util.toast('当前平台暂不支持应用内安装');
      return;
    }
    final size = int.tryParse('${widget.data['size']}') ?? 0;
    final digest = '${widget.data['sha256'] ?? ''}';
    if (size <= 0 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      Util.toast('更新信息不完整，请重新检查更新');
      return;
    }
    setState(() {
      downloading = true;
      statusText = progress > 0 ? '正在继续下载' : '正在下载安装包';
    });
    try {
      final directory = await getApplicationSupportDirectory();
      final file = await updater.fetch(
        url: widget.data['downloadURL'],
        path: '${directory.path}/updates/$fileName',
        size: size,
        digest: digest,
        onProgress: (value) {
          if (mounted)
            setState(() {
              progress = value;
              if (value >= 1) statusText = '正在校验安装包';
            });
        },
      );
      if (!mounted || updater.isPaused) return;
      setState(() {
        localApk = file.path;
        progress = 1;
        statusText = '安装包已校验，正在打开安装界面';
      });
      final result = await EasyAppInstaller.instance.installApk(file.path,
          explainContent: '需要允许 DsmClient 安装下载的新版本，以完成应用内更新。',
          positiveText: '去设置',
          negativeText: '稍后');
      if (!mounted) return;
      setState(() => statusText =
          (result ?? '').isEmpty ? '安装未启动，可再次点击安装更新' : '请在系统界面完成安装');
    } catch (error) {
      if (!mounted) return;
      setState(() => statusText = updater.isPaused
          ? '下载已暂停，可继续下载'
          : error is StateError
              ? '${error.message}'
              : '下载中断，请重试继续下载');
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(context),
        title: Text(
          "软件更新",
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: <Widget>[
                SizedBox(
                  height: 50,
                ),
                Center(
                  child: NeuCard(
                    bevel: 20,
                    curveType: CurveType.flat,
                    decoration: NeumorphicDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(60),
                    ),
                    child: CircleAvatar(
                      backgroundImage: AssetImage(
                        "assets/logo.png",
                      ),
                      radius: 60,
                    ),
                  ),
                ),
                SizedBox(
                  height: 30,
                ),
                Column(
                  children: [
                    Text(
                      "新版本 v${widget.data['buildVersion']} build ${widget.data['buildVersionNo']}",
                      style: TextStyle(fontSize: 18),
                    ),
                  ],
                ),
                SizedBox(
                  height: 40,
                ),
                NeuCard(
                  padding: EdgeInsets.symmetric(vertical: 20, horizontal: 25),
                  margin: EdgeInsets.symmetric(horizontal: 20),
                  curveType: CurveType.flat,
                  decoration: NeumorphicDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        "更新日志：",
                        style: TextStyle(fontSize: 16),
                      ),
                      SizedBox(
                        height: 10,
                      ),
                      Text(
                        "${widget.data['buildUpdateDescription'] ?? "暂无更新日志"}",
                        style: TextStyle(
                            color: AppTheme.of(context).placeholderColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Text(statusText, textAlign: TextAlign.center),
          ),
          if (widget.data['releaseURL'] != null)
            TextButton(
              onPressed: () => launchUrlString(widget.data['releaseURL'],
                  mode: LaunchMode.externalApplication),
              child: Text('查看版本说明'),
            ),
          GestureDetector(
            onTap: () {
              launchUrlString(widget.data['downloadURL'],
                  mode: LaunchMode.externalApplication);
            },
            child: Text(
              "使用浏览器下载",
              style: TextStyle(
                  color: Colors.grey,
                  decoration: TextDecoration.underline,
                  fontSize: 14),
            ),
          ),
          SizedBox(
            height: 20,
          ),
          if (!downloading)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: NeuButton(
                onPressed: () {
                  download();
                },
                // margin: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                padding: EdgeInsets.symmetric(vertical: 20),
                decoration: NeumorphicDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                bevel: 20,
                child: Text(
                  localApk != null
                      ? '安装更新'
                      : progress > 0
                          ? '继续下载'
                          : '下载并安装',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ),
          if (downloading)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: NeuCard(
                curveType: CurveType.flat,
                bevel: 10,
                decoration: NeumorphicDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: FAProgressBar(
                    backgroundColor: Colors.transparent,
                    progressColor: Colors.blue,
                    currentValue: (progress * 100).ceil(),
                    size: 64,
                    borderRadius: BorderRadius.circular(20),
                    displayText: '%',
                    displayTextStyle:
                        TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
              ),
            ),
          if (downloading)
            TextButton(
                onPressed: () {
                  updater.pause();
                  setState(() => statusText = '下载已暂停，可继续下载');
                },
                child: Text('暂停下载')),
          SizedBox(height: 30),
        ],
      ),
    );
  }
}
