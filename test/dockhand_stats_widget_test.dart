// @dart=2.10
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dsm_client/pages/docker/dockhand.dart';
import 'package:dsm_client/util/dockhand_client.dart';
import 'package:dsm_client/widgets/docker_stats.dart';
import 'package:dsm_client/themes/light.dart';

class FixtureDockhandClient extends DockhandClient {
  final samples = <String>[];
  Completer<List<Map>> delayed;
  FixtureDockhandClient() : super('https://example.test');
  @override
  Future<void> login({String user = '', String password = '', String mfa = '', String token = ''}) async {}
  @override
  Future<List<Map>> environments() async => [{'id':1,'name':'环境一'},{'id':2,'name':'环境二'}];
  @override
  Future<dynamic> resource(String name, String env) async => [{'id':'c$env','name':'服务 $env','state':'running','image':'example:latest'}];
  @override
  Future<List<Map>> statistics(String env) async {
    samples.add(env);
    if (env == '1' && delayed != null) return delayed.future;
    return [{'id':'c$env','cpuPercent': env == '1' ? 12.5 : 22.0, 'memoryUsage': 268435456,
      'memoryLimit':1073741824,'memoryPercent':25,'networkRx':1024,'networkTx':2048,'blockRead':4096,'blockWrite':8192}];
  }
}

void main() {
  testWidgets('Docker totals never sum host memory limits and support CPU above one core', (tester) async {
    final totals = DockerStatsPanel.totals([
      {'cpuPercent':125,'memoryUsage':1024,'memoryLimit':8192},
      {'cpuPercent':125,'memoryUsage':2048,'memoryLimit':8192},
    ]);
    expect(totals['cpuPercent'],250);
    expect(totals['memoryUsage'],3072);
    expect(totals.containsKey('memoryLimit'),isFalse);
    expect(DockerStatsPanel.percent(double.nan),'—');
    tester.binding.window.physicalSizeTestValue = Size(320,760);
    tester.binding.window.devicePixelRatioTestValue = 1;
    tester.binding.window.textScaleFactorTestValue = 1.6;
    addTearDown(() {tester.binding.window.clearPhysicalSizeTestValue();tester.binding.window.clearDevicePixelRatioTestValue();tester.binding.window.clearTextScaleFactorTestValue();});
    await tester.pumpWidget(MaterialApp(theme:lightTheme,home:Scaffold(body:SingleChildScrollView(child:Padding(padding:EdgeInsets.all(16),child:DockerStatsPanel(totals))))));
    expect(find.text('250.0%'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  testWidgets('Dockhand samples on entry and refresh; pauses in background and rejects stale environments', (tester) async {
    SharedPreferences.setMockInitialValues({'dockhand_url_stats-fixture':'https://example.test'});
    FlutterSecureStorage.setMockInitialValues({});
    final client = FixtureDockhandClient();
    await tester.pumpWidget(MaterialApp(theme:lightTheme,home:DockhandProgram(profile:'stats-fixture',clientFactory:(_)=>client)));
    await tester.pumpAndSettle();await tester.pump(Duration(milliseconds:400));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1),'demo');await tester.enterText(find.byType(TextField).last,'fixture');
    await tester.ensureVisible(find.text('连接 Dockhand'));await tester.tap(find.text('连接 Dockhand'));await tester.pumpAndSettle();
    expect(find.text('容器资源合计'),findsOneWidget);
    expect(find.text('12.5%'),findsWidgets);
    final before=client.samples.length;
    await tester.pump(Duration(seconds:10));await tester.pumpAndSettle();
    expect(client.samples.length,before+1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(Duration(seconds:20));await tester.pumpAndSettle();
    expect(client.samples.length,before+1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await tester.pumpAndSettle();
    client.delayed=Completer<List<Map>>();
    await tester.tap(find.byTooltip('刷新资源'));await tester.pump();
    await tester.tap(find.text('环境一').last);await tester.pumpAndSettle();
    await tester.tap(find.text('环境二').last);await tester.pumpAndSettle();
    expect(find.text('22.0%'),findsWidgets);
    client.delayed.complete([{'id':'c1','cpuPercent':999.0}]);await tester.pumpAndSettle();
    expect(find.text('999.0%'),findsNothing);
    expect(client.samples.last,'2');
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(SizedBox());await tester.pumpAndSettle();
  });
}
