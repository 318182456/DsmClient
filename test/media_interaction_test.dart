// @dart=2.10
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dsm_client/widgets/surfaces.dart' as surfaces;
import 'package:dsm_client/widgets/adaptive_tab_bar.dart';
import 'package:dsm_client/models/media_queue.dart';
import 'package:dsm_client/widgets/media_actions.dart';
import 'package:dsm_client/pages/packages/audio_station.dart';
import 'package:dsm_client/util/media_delete.dart';
import 'package:dsm_client/themes/light.dart';

void main() {
  testWidgets('Shared button content is centered in wide and round buttons',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: lightTheme,
        home: Scaffold(
            body: Column(children: [
          SizedBox(
              width: 280,
              height: 64,
              child: surfaces.NeuButton(
                  key: ValueKey('wide'),
                  padding: EdgeInsets.zero,
                  onPressed: () {},
                  child: Text('确认操作'))),
          SizedBox(
              width: 96,
              height: 96,
              child: surfaces.NeuButton(
                  key: ValueKey('round'),
                  padding: EdgeInsets.zero,
                  decoration:
                      surfaces.NeumorphicDecoration(shape: BoxShape.circle),
                  onPressed: () {},
                  child: Text('取消'))),
        ]))));
    for (final pair in {'wide': '确认操作', 'round': '取消'}.entries) {
      final button = tester.getRect(find.byKey(ValueKey(pair.key)));
      final text = tester.getRect(find.text(pair.value));
      expect((button.center - text.center).distance, lessThan(1));
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets('Tabs fit without scrolling and overflow only when necessary',
      (tester) async {
    Future<void> show(double width, List<String> labels) async {
      await tester.pumpWidget(MaterialApp(
          theme: lightTheme,
          home: DefaultTabController(
              length: labels.length,
              child: Scaffold(
                  body: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                          width: width,
                          child: AdaptiveTabBar(
                              isScrollable: true,
                              tabs: labels
                                  .map((s) => Tab(text: s))
                                  .toList())))))));
      await tester.pumpAndSettle();
    }

    await show(390, ['文件', '任务', '日志']);
    expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isFalse);
    await show(180, ['名称很长的第一个分类', '另一个完整分类']);
    expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isTrue);
    expect(tester.takeException(), isNull);
  });
  test(
      'Continuous queues start at selected item, keep order and do not mix audio/video',
      () {
    const a = MediaTrack(id: 'a', name: 'a', url: 'https://example.test/a');
    const b = MediaTrack(id: 'b', name: 'b', url: 'https://example.test/b');
    const v = MediaTrack(
        id: 'v', name: 'v', url: 'https://example.test/v', video: true);
    const c = MediaTrack(id: 'c', name: 'c', url: 'https://example.test/c');
    expect(MediaQueue.from([a, v, b, c], b, continuous: true).map((t) => t.id),
        ['b', 'c']);
    expect(MediaQueue.from([a, b, c], b).map((t) => t.id), ['b']);
    expect(
        MediaQueue.from([a, b], v, continuous: true).map((t) => t.id), ['v']);
  });
  testWidgets(
      'Audio list long press exposes playback menu and cancel does not delete',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: lightTheme,
        home: AudioLibrary('歌曲', 'Song', 'songs',
            loader: (section, params) async => {
                  'success': true,
                  'data': {
                    'total': 2,
                    'songs': [
                      {'id': 'a', 'title': '测试歌曲'},
                      {'id': 'b', 'title': '下一首'}
                    ]
                  }
                })));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('测试歌曲'));
    await tester.pumpAndSettle();
    expect(find.text('从头播放'), findsOneWidget);
    expect(find.text('从这里连续播放'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AudioLibrary), findsOneWidget);
    expect(find.text('测试歌曲'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Media action sheet offers explicit deletion without executing it',
      (tester) async {
    String action;
    await tester.pumpWidget(MaterialApp(
        theme: lightTheme,
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      action = await showMediaActions(context, 'movie.mp4',
                          canDelete: true, more: true);
                    },
                    child: Text('打开'))))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(action, 'delete');
    expect(tester.takeException(), isNull);
  });
  test('Deletion waits for task completion and reports a failed task',
      () async {
    var polls = 0;
    await deleteMediaFile('/music/test.mp3',
        start: (paths) async => {
              'success': true,
              'data': {'taskid': 'demo'}
            },
        status: (id) async => {
              'success': true,
              'data': {'finished': ++polls == 2}
            },
        wait: () async {});
    expect(polls, 2);
    await expectLater(
        deleteMediaFile('/music/test.mp3',
            start: (paths) async => {
                  'success': true,
                  'data': {'taskid': 'demo'}
                },
            status: (id) async => {
                  'success': true,
                  'data': {'finished': true, 'has_fail': true}
                },
            wait: () async {}),
        throwsStateError);
  });
}
