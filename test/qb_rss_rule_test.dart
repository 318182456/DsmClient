// @dart=2.10
import '../lib/models/qb_rss_rule.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  final original = {
    'previouslyMatchedEpisodes': ['1x01'],
    'lastMatch': 'fixture',
    'priority': 4,
    'smartFilter': true,
    'torrentParams': {
      'download_limit': 123,
      'content_layout': 'Subfolder',
      'stopped': true
    }
  };
  final rule = QbRssRule.build(original,
      feeds: ['https://feed.test/rss', 'https://feed.test/rss'],
      category: ' Linux ',
      tags: ['test', ' test ', '', 'iso'],
      savePath: '/data/linux',
      include: 'Ubuntu*',
      exclude: 'beta',
      ignoreDays: 2,
      stopped: false);
  check(
      rule['previouslyMatchedEpisodes'] ==
              original['previouslyMatchedEpisodes'] &&
          rule['lastMatch'] == 'fixture' &&
          rule['priority'] == 4 &&
          rule['smartFilter'] == true,
      'Preserve server history and unknown rule options');
  final p = rule['torrentParams'];
  check(p['download_limit'] == 123 && p['content_layout'] == 'Subfolder',
      'Preserve unrelated per-torrent parameters');
  check(
      p['category'] == 'Linux' &&
          p['tags'].length == 2 &&
          p['save_path'] == '/data/linux' &&
          p['stopped'] == false,
      'qB native parameters and normalized tags');
  check(
      rule['assignedCategory'] == 'Linux' &&
          rule['savePath'] == '/data/linux' &&
          rule['addPaused'] == false,
      'Legacy API mirrors remain compatible');
  check(
      rule['affectedFeeds'].length == 1 &&
          rule['mustContain'] == 'Ubuntu*' &&
          rule['mustNotContain'] == 'beta',
      'Feed deduplication and match filters');
  final automatic = QbRssRule.build(rule,
      feeds: ['https://feed.test/rss'], automaticPath: true);
  check(
      automatic['torrentParams']['use_auto_tmm'] == true &&
          QbRssRule.path(automatic).isEmpty &&
          !automatic['torrentParams'].containsKey('stopped'),
      'Automatic category directory and default start behavior');
  check(
      QbRssRule.category({'assignedCategory': 'old'}) == 'old' &&
          QbRssRule.stopped({'addPaused': 1}) == true,
      'Legacy rules can be edited');
  for (final invoke in [
    () => QbRssRule.build({}),
    () => QbRssRule.build({}, feeds: ['a'], ignoreDays: -1),
    () => QbRssRule.build({}, feeds: ['a'], savePath: '/data\ninvalid')
  ]) {
    var failed = false;
    try {
      invoke();
    } on FormatException {
      failed = true;
    }
    check(failed, 'Invalid rules rejected before write');
  }
  print(
      'qB RSS native parameters, compatibility and history preservation passed');
}
