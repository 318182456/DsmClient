// @dart=2.10
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dsm_client/themes/light.dart';
import 'package:dsm_client/themes/dark.dart';
import 'package:dsm_client/pages/packages/audio_station.dart';
import 'package:dsm_client/pages/docker/dockhand.dart';
import 'package:dsm_client/pages/control_panel/control_panel.dart';
import 'package:dsm_client/pages/login/login.dart';
import 'package:dsm_client/widgets/surfaces.dart' as surfaces;

void main() {
  testWidgets('Render temporary design review previews when requested',
      (tester) async {
    final directory = Platform.environment['DSM_UI_PREVIEW_DIR'] ?? '';
    if (directory.isEmpty) return;
    final root = Platform.environment['RUNNER_TEMP'];
    await tester.runAsync(() async {
      final loader = FontLoader('ReviewFont');
      loader.addFont(File('$root/dsm-review-font.otf')
          .readAsBytes()
          .then((v) => ByteData.view(v.buffer)));
      await loader.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(File(
              '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          .readAsBytes()
          .then((v) => ByteData.view(v.buffer)));
      await icons.load();
    });
    tester.binding.window.physicalSizeTestValue = Size(390, 844);
    tester.binding.window.devicePixelRatioTestValue = 1;
    addTearDown(() {
      tester.binding.window.clearPhysicalSizeTestValue();
      tester.binding.window.clearDevicePixelRatioTestValue();
    });
    SharedPreferences.setMockInitialValues({});
    final output = Directory(directory)..createSync(recursive: true);
    ThemeData reviewTheme(ThemeData theme) => theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'ReviewFont'),
        appBarTheme: theme.appBarTheme.copyWith(
            titleTextStyle: theme.appBarTheme.titleTextStyle
                .copyWith(fontFamily: 'ReviewFont')),
        tabBarTheme: theme.tabBarTheme.copyWith(
            labelStyle:
                theme.tabBarTheme.labelStyle.copyWith(fontFamily: 'ReviewFont'),
            unselectedLabelStyle: theme.tabBarTheme.unselectedLabelStyle
                .copyWith(fontFamily: 'ReviewFont')));
    Future<void> capture(String name, Widget page, ThemeData theme) async {
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: reviewTheme(theme),
              home: page)));
      await tester.pumpAndSettle();
      if (page is ControlPanel) {
        await tester.runAsync(() async {
          for (final icon in [
            'shared_folders',
            'file_services',
            'users',
            'public_access',
            'network',
            'terminal_and_SNMP',
            'info_center',
            'hardware_and_power',
            'external_devices',
            'update_and_reset',
            'file_index',
            'task_scheduler'
          ]) {
            await precacheImage(AssetImage('assets/control_panel/7/$icon.png'),
                key.currentContext);
          }
        });
        await tester.pumpAndSettle();
      }
      await tester.runAsync(() async {
        final boundary =
            key.currentContext.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${output.path}/$name.png')
            .writeAsBytesSync(bytes.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(SizedBox());
      await tester.pumpAndSettle();
    }

    AudioStation music() => AudioStation(
        loader: (section, params) async => {
              'success': true,
              'data': {
                'total': 8,
                'songs': [
                  for (final song in [
                    '孤独患者',
                    '哎呀咿呀',
                    '看穿',
                    '吟游诗人',
                    '张氏情歌',
                    'Baby Song',
                    '听一千遍后',
                    '이 사랑'
                  ])
                    {
                      'id': song,
                      'title': song,
                      'additional': {
                        'song_tag': {
                          'artist': song == '이 사랑' ? 'DAVICHI' : '陈奕迅',
                          'album': '音乐资料库'
                        },
                        'song_audio': {'duration': 245}
                      }
                    }
                ]
              }
            });
    await capture('music-light', music(), lightTheme);
    await capture('music-dark', music(), darkTheme);
    await capture(
        'dockhand-connect', DockhandProgram(profile: 'review'), lightTheme);
    await capture('control-panel', ControlPanel({}, [], [], {}), lightTheme);
    SharedPreferences.setMockInitialValues({'agreement':'1','read':'1'});
    Login login() => Login(server:{'https':true,'host':'nas.example.test','port':'65535',
      'account':'demo-user','password':'fixture-only','note':'测试 NAS','auto_login':true,
      'remember_password':true,'check_ssl':true,'cookie':'','sid':'','action':'edit'});
    await capture('login-light',login(),lightTheme);
    await capture('login-dark',login(),darkTheme);
    await capture('legacy-form',Scaffold(appBar:AppBar(title:Text('表单边框检查')),body:Padding(padding:EdgeInsets.all(20),
      child:surfaces.NeuCard(padding:EdgeInsets.symmetric(horizontal:16,vertical:8),
        child:TextField(decoration:InputDecoration(border:InputBorder.none,labelText:'单层边框',hintText:'旧页面的输入框'))))),lightTheme);
  });
}
