// @dart=2.10
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dsm_client/themes/light.dart';
import 'package:dsm_client/themes/dark.dart';
import 'package:dsm_client/themes/app_theme.dart';
import 'package:dsm_client/pages/packages/audio_station.dart';
import 'package:dsm_client/pages/docker/dockhand.dart';
import 'package:dsm_client/util/dockhand_credentials.dart';
import 'package:dsm_client/models/program_capabilities.dart';
import 'package:dsm_client/pages/control_panel/control_panel.dart';
import 'package:dsm_client/widgets/surfaces.dart' as surfaces;

double contrast(Color a, Color b) =>
    (max(a.computeLuminance(), b.computeLuminance()) + .05) /
    (min(a.computeLuminance(), b.computeLuminance()) + .05);
void main() {
  testWidgets(
      'Shared cards retain button taps and use the current theme surface',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
        theme: darkTheme,
        home: Scaffold(
            body: surfaces.NeuCard(
                decoration: surfaces.NeumorphicDecoration(
                    color: darkTheme.scaffoldBackgroundColor),
                padding: EdgeInsets.all(16),
                child: surfaces.NeuButton(
                    onPressed: () => taps++, child: Text('测试操作'))))));
    await tester.tap(find.text('测试操作'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(
        tester
            .widgetList<Material>(find.byType(Material))
            .where((m) => m.color == darkTheme.cardColor),
        isNotEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Control panel remains searchable with large text on a narrow screen',
      (tester) async {
    tester.binding.window.physicalSizeTestValue = Size(320, 760);
    tester.binding.window.devicePixelRatioTestValue = 1;
    tester.binding.window.textScaleFactorTestValue = 1.6;
    addTearDown(() {
      tester.binding.window.clearPhysicalSizeTestValue();
      tester.binding.window.clearDevicePixelRatioTestValue();
      tester.binding.window.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(
        MaterialApp(theme: lightTheme, home: ControlPanel({}, [], [], {})));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '任务计划');
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate(
            (widget) => widget is Text && widget.data == '任务计划'),
        findsOneWidget);
    expect(find.text('硬件和电源'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(SizedBox());
  });
  test(
      'Both themes keep active tabs, inactive tabs and secondary text readable',
      () {
    for (final theme in [lightTheme, darkTheme]) {
      for (final color in [
        theme.tabBarTheme.labelColor,
        theme.tabBarTheme.unselectedLabelColor,
        theme.textTheme.bodyText1.color,
        theme.textTheme.caption.color,
        theme.extension<AppTheme>().placeholderColor
      ]) {
        expect(contrast(color, theme.scaffoldBackgroundColor),
            greaterThanOrEqualTo(4.5));
        expect(contrast(color, theme.cardColor), greaterThanOrEqualTo(4.5));
      }
      expect(
          contrast(theme.colorScheme.onPrimaryContainer,
              theme.colorScheme.primaryContainer),
          greaterThanOrEqualTo(4.5));
    }
    final copied =
        lightTheme.extension<AppTheme>().copyWith(placeholderColor: Colors.red);
    expect(copied.placeholderColor, Colors.red);
    expect(copied.titleColor, lightTheme.extension<AppTheme>().titleColor);
  });
  test('Only containers with supported workspaces appear as app shortcuts', () {
    for (final name in ['dockhand', 'qbittorrent', 'transmission-1']) {
      expect(ProgramCapabilities.hasContainerWorkspace(name, ''), isTrue);
    }
    expect(
        ProgramCapabilities.hasContainerWorkspace(
            'downloads', 'lscr.io/linuxserver/qbittorrent:latest'),
        isTrue);
    for (final name in [
      'postgres',
      'redis',
      'mariadb',
      'watchtower',
      'dockhand-postgres'
    ]) {
      expect(ProgramCapabilities.hasContainerWorkspace(name, ''), isFalse);
    }
  });
  for (final dark in [false, true]) {
    testWidgets(
        'Audio library remains readable at narrow width and large text (${dark ? 'dark' : 'light'})',
        (tester) async {
      tester.binding.window.physicalSizeTestValue = Size(320, 760);
      tester.binding.window.devicePixelRatioTestValue = 1;
      tester.binding.window.textScaleFactorTestValue = 1.6;
      addTearDown(() {
        tester.binding.window.clearPhysicalSizeTestValue();
        tester.binding.window.clearDevicePixelRatioTestValue();
        tester.binding.window.clearTextScaleFactorTestValue();
      });
      await tester.pumpWidget(MaterialApp(
          theme: dark ? darkTheme : lightTheme,
          home: AudioStation(
              loader: (section, params) async => {
                    'success': true,
                    'data': {
                      'total': 1,
                      'songs': [
                        {
                          'id': 'demo',
                          'title': '孤独患者 / A very long song title',
                          'additional': {
                            'song_tag': {'artist': '陈奕迅', 'album': '音乐资料库'},
                            'song_audio': {'duration': 265}
                          }
                        }
                      ],
                      'albums': [
                        {'name': '很长的专辑名称 Album', 'album_artist': '陈奕迅'}
                      ]
                    }
                  })));
      await tester.pumpAndSettle();
      expect(find.text('音乐资料库'), findsOneWidget);
      expect(find.text('孤独患者 / A very long song title'), findsOneWidget);
      expect(find.text('陈奕迅 · 音乐资料库'), findsOneWidget);
      await tester.tap(find.text('专辑'));
      await tester.pumpAndSettle();
      expect(find.byType(AudioCollectionCard), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(SizedBox());
    });
  }
  testWidgets(
      'Dockhand remembers credentials after reopening and clears them on address change',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues(
        {'dockhand_url_test': 'https://dock.example.com'});
    const vault = DockhandCredentials();
    await vault.save('test', 'https://dock.example.com', {
      'mode': 'local',
      'account': 'demo',
      'password': 'fixture-password',
      'otp': '123456'
    });
    expect(await vault.read('other-nas', 'https://dock.example.com'), isNull);
    expect(await vault.read('test', 'https://other.example.com'), isNull);
    expect(
        (await vault.read('test', 'https://dock.example.com'))
            .containsKey('otp'),
        isFalse);
    for (var i = 0; i < 2; i++) {
      await tester.pumpWidget(MaterialApp(
          theme: lightTheme, home: DockhandProgram(profile: 'test')));
      await tester.pumpAndSettle();
      await tester.pump(Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final inputs =
          tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(inputs[1].controller.text, 'demo');
      expect(inputs[2].controller.text, 'fixture-password');
      expect(inputs[2].obscureText, isTrue);
      if (i == 0) {
        await tester.pumpWidget(SizedBox());
        await tester.pumpAndSettle();
      }
    }
    await tester.enterText(
        find.byType(TextField).first, 'https://other.example.com');
    await tester.pump(Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .last
            .controller
            .text,
        isEmpty);
    await tester.enterText(
        find.byType(TextField).first, 'https://dock.example.com');
    await tester.pump(Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    final forget = find.text('清除已保存登录信息');
    await tester.ensureVisible(forget);
    await tester.pumpAndSettle();
    await tester.tap(forget);
    await tester.pumpAndSettle();
    expect(await vault.read('test', 'https://dock.example.com'), isNull);
    expect((await SharedPreferences.getInstance()).getKeys(),
        isNot(contains('password')));
    expect(tester.takeException(), isNull);
  });
}
