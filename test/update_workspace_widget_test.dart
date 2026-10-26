// @dart=2.10
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oktoast/oktoast.dart';
import 'package:dsm_client/pages/update/update.dart';
import 'package:dsm_client/pages/docker/workspace.dart';
import 'package:dsm_client/pages/docker/dockhand.dart';
import 'package:dsm_client/pages/docker/docker.dart';
import 'package:dsm_client/themes/app_theme.dart';

void main() {
  testWidgets('Update copies the selected proxy URL and persists direct selection', (tester) async {
    SharedPreferences.setMockInitialValues({});
    String copied;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = call.arguments['text'];
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    const url = 'https://github.com/318182456/DsmClient/releases/download/dev-15/DsmClient-dev-15-arm64.apk';
    await tester.pumpWidget(OKToast(child: MaterialApp(theme: ThemeData(extensions: [AppTheme(placeholderColor: Colors.grey)]),
      home: Update({'buildVersion':'0.1.0','buildVersionNo':'10015','downloadURL':url,'size':1,'sha256':List.filled(64, '0').join()}))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制下载链接'));
    await tester.pump(Duration(seconds: 4)); await tester.pumpAndSettle();
    expect(copied, 'https://edgeone.gh-proxy.org/$url');
    final picker = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(picker); await tester.tap(picker); await tester.pumpAndSettle();
    await tester.tap(find.text('GitHub 直连').last); await tester.pumpAndSettle();
    await tester.tap(find.text('复制下载链接'));
    await tester.pump(Duration(seconds: 4)); await tester.pumpAndSettle();
    expect(copied, url);
    expect((await SharedPreferences.getInstance()).getString('update_proxy_prefix'), '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Docker backend can switch from Dockhand to Synology and save preference', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(home: DockerWorkspace(initialBackend:'dockhand')));
    await tester.pumpAndSettle();
    expect(find.byType(DockhandProgram), findsOneWidget);
    await tester.tap(find.byTooltip('选择容器管理方式')); await tester.pumpAndSettle();
    await tester.tap(find.text('群晖 Container Manager')); await tester.pumpAndSettle();
    expect(find.byType(Docker), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('docker_backend_'), 'synology');
    await tester.pumpWidget(SizedBox()); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
