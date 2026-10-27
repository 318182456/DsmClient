// @dart=2.10
import '../lib/models/torrent_presentation.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  final rows = <Map>[
    {
      'id': 'a',
      'name': 'Alpha',
      'size': 300,
      'progress': .2,
      'downloadSpeed': 20,
      'raw': {
        'category': 'linux',
        'tags': 'iso, keep',
        'added_on': 3,
        'save_path': '/data/a',
        'ratio': .5
      },
      'trackers': ['https://one.test/announce?passkey=fixture']
    },
    {
      'id': 'b',
      'name': 'Beta',
      'size': 100,
      'progress': .9,
      'downloadSpeed': 40,
      'raw': {
        'category': 'linux',
        'tags': 'iso',
        'added_on': 1,
        'save_path': '/data/b',
        'ratio': 2
      },
      'trackers': ['udp://two.test:80/announce']
    },
    {
      'id': 'c',
      'name': 'Gamma',
      'size': 200,
      'progress': .7,
      'downloadSpeed': 30,
      'raw': {
        'category': '',
        'tags': '',
        'added_on': 2,
        'save_path': '/data/a',
        'ratio': 1
      },
      'trackers': []
    },
  ];
  String ids(List<Map> value) => value.map((t) => t['id']).join();
  check(
      ids(TorrentPresentation.select(rows,
              categoryFilter: 'linux',
              tagFilter: 'keep',
              trackerFilter: 'one.test')) ==
          'a',
      'Combine category/tag/tracker');
  check(
      ids(TorrentPresentation.select(rows, tagFilter: '', trackerFilter: '')) ==
          'c',
      'Explicitly filter uncategorized dimensions');
  check(
      ids(TorrentPresentation.select(rows,
              directoryFilter: '/data/a', sort: 'size', descending: false)) ==
          'ca',
      'Directory plus ascending size');
  check(ids(TorrentPresentation.select(rows, sort: 'added')) == 'acb',
      'Default newest first');
  check(
      ids(TorrentPresentation.select(rows, sort: 'added', descending: false)) ==
          'bca',
      'Oldest first');
  check(
      ids(TorrentPresentation.select(rows, sort: 'ratio', descending: true)) ==
          'bca',
      'Descending ratio');
  final tr = {
    'id': 9,
    'name': 'tr',
    'state': '4',
    'raw': {
      'labels': ['my,label', 'keep'],
      'downloadDir': '/downloads',
      'addedDate': 8,
      'trackers': [
        {'announce': 'https://one.test/announce'}
      ]
    }
  };
  check(TorrentPresentation.tags(tr).contains('my,label'),
      'Transmission labels preserve embedded commas');
  check(
      TorrentPresentation.select([tr],
                  transmission: true,
                  tagFilter: 'keep',
                  trackerFilter: 'one.test',
                  directoryFilter: '/downloads')
              .length ==
          1,
      'Transmission facets');
  print('Torrent combined filters and ascending/descending sort tests passed');
}
