import 'package:dsm_client/models/program_section.dart';
import 'package:dsm_client/pages/common/audio_player.dart';
import 'package:dsm_client/util/function.dart';
import 'package:dsm_client/util/program_api.dart';
import 'package:flutter/material.dart';
import 'program_page.dart';

class AudioStation extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: 5,
      child: Scaffold(
          appBar: AppBar(
              title: Text('Audio Station'),
              actions: [
                IconButton(
                    icon: Icon(Icons.search),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => AudioLibrary(
                                '搜索', 'Search', 'songs',
                                search: true))))
              ],
              bottom: TabBar(isScrollable: true, tabs: [
                Tab(text: '歌曲'),
                Tab(text: '专辑'),
                Tab(text: '歌手'),
                Tab(text: '播放列表'),
                Tab(text: '文件夹')
              ])),
          body: TabBarView(children: [
            AudioLibrary('歌曲', 'Song', 'songs', embedded: true),
            AudioLibrary('专辑', 'Album', 'albums', embedded: true),
            AudioLibrary('歌手', 'Artist', 'artists', embedded: true),
            AudioLibrary('播放列表', 'Playlist', 'playlists', embedded: true),
            AudioLibrary('文件夹', 'Folder', 'items', embedded: true),
          ])));
}

class AudioLibrary extends StatefulWidget {
  final String title, kind, listKey, method;
  final Map<String, dynamic> filter;
  final bool embedded, search;
  const AudioLibrary(this.title, this.kind, this.listKey,
      {this.filter = const {},
      this.method = 'list',
      this.embedded = false,
      this.search = false});
  @override
  State<AudioLibrary> createState() => _AudioLibraryState();
}

class _AudioLibraryState extends State<AudioLibrary>
    with AutomaticKeepAliveClientMixin {
  List<Map> items = [];
  int offset = 0, total = 0, generation = 0;
  bool loading = true, busy = false;
  String error = '', keyword = '';
  final searchController = TextEditingController();
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    if (!widget.search)
      load();
    else
      loading = false;
  }

  @override
  void dispose() {
    generation++;
    searchController.dispose();
    super.dispose();
  }

  Future<void> load({bool next = false}) async {
    if (busy) return;
    final current = ++generation;
    setState(() {
      busy = true;
      error = '';
      if (!next) loading = true;
    });
    try {
      final result = await ProgramApi.call(
          ProgramSection('', 'SYNO.AudioStation.${widget.kind}', widget.method,
              version: widget.kind == 'Artist' ? 4 : 3),
          params: {
            'offset': next ? offset : 0,
            'limit': 100,
            'library': 'all',
            if (widget.kind == 'Song')
              'additional': 'song_tag,song_audio,song_rating',
            if (widget.kind == 'Playlist' && widget.method == 'getinfo')
              'additional': 'songs',
            if (widget.search) 'keyword': keyword,
            ...widget.filter,
          });
      if (!mounted || generation != current) return;
      if (result['success'] != true) {
        setState(() => error = ProgramApi.error(result));
        return;
      }
      final data = result['data'] as Map ?? {};
      dynamic source = data[widget.listKey];
      dynamic count = data['total'] ?? data['songTotal'];
      if (widget.method == 'getinfo' && widget.kind == 'Playlist') {
        final playlists = data['playlists'] as List ?? [];
        final additional =
            playlists.isEmpty ? {} : playlists.first['additional'] ?? {};
        source = additional['songs'];
        count = additional['songs_total'];
      }
      final batch = (source as List ?? []).whereType<Map>().toList();
      setState(() {
        items = next ? [...items, ...batch] : batch;
        offset = items.length;
        total = count is num ? count.toInt() : items.length;
      });
    } catch (_) {
      if (mounted) setState(() => error = '曲库加载失败，请重试');
    } finally {
      if (mounted && generation == current)
        setState(() {
          loading = false;
          busy = false;
        });
    }
  }

  void browse(
      String title, String kind, String key, Map<String, dynamic> filter,
      {String method = 'list'}) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => AudioLibrary(title, kind, key,
                filter: filter, method: method)));
  }

  void select(Map song) {
    final type = '${song['type'] ?? ''}';
    if (widget.kind == 'Album') {
      browse('${song['name']}', 'Song', 'songs',
          {'album': song['name'], 'album_artist': song['album_artist'] ?? ''});
      return;
    }
    if (widget.kind == 'Artist') {
      browse('${song['name']}', 'Song', 'songs', {'artist': song['name']});
      return;
    }
    if (widget.kind == 'Playlist' && widget.method == 'list') {
      browse('${song['name']}', 'Playlist', 'songs', {'id': song['id']},
          method: 'getinfo');
      return;
    }
    if (type == 'folder') {
      browse('${song['title']}', 'Folder', 'items', {'id': song['id']});
      return;
    }
    final id = song['id'];
    if (id == null) return;
    final url = ProgramApi.url(
        ProgramSection('', 'SYNO.AudioStation.Stream', 'stream', version: 2),
        {'id': id, 'format': 'raw'});
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => AudioPlayer(
                name: '${song['title'] ?? song['name'] ?? '音乐'}', url: url)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final content = Column(children: [
      if (widget.search)
        Padding(
            padding: EdgeInsets.all(16),
            child: TextField(
                controller: searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: busy
                    ? null
                    : (v) {
                        keyword = v.trim();
                        load();
                      },
                decoration: InputDecoration(
                    hintText: '搜索 NAS 曲库',
                    prefixIcon: Icon(Icons.search),
                    suffixIcon: IconButton(
                        icon: Icon(Icons.arrow_forward),
                        onPressed: busy
                            ? null
                            : () {
                                keyword = searchController.text.trim();
                                load();
                              })))),
      Expanded(
          child: loading
              ? Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                      physics: AlwaysScrollableScrollPhysics(),
                      children: [
                        if (error.isNotEmpty)
                          ListTile(
                              title: Text(error),
                              trailing: IconButton(
                                  icon: Icon(Icons.refresh),
                                  onPressed: () => load())),
                        if (error.isEmpty && items.isEmpty)
                          ListTile(
                              title: Text(widget.search && keyword.isEmpty
                                  ? '输入歌曲、专辑或歌手名称'
                                  : '暂无音乐')),
                        ...items.map((s) {
                          final tags =
                              (s['additional'] ?? {})['song_tag'] ?? {};
                          final subtitle =
                              '${tags['artist'] ?? s['display_artist'] ?? s['artist'] ?? ''}';
                          return ListTile(
                              leading: Icon(s['type'] == 'folder'
                                  ? Icons.folder
                                  : widget.kind == 'Playlist' &&
                                          widget.method == 'list'
                                      ? Icons.queue_music
                                      : Icons.music_note),
                              title:
                                  Text('${s['title'] ?? s['name'] ?? '未命名'}'),
                              subtitle:
                                  subtitle.isEmpty ? null : Text(subtitle),
                              onTap: () => select(s),
                              trailing: IconButton(
                                  icon: Icon(Icons.info_outline),
                                  onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => Scaffold(
                                              appBar:
                                                  AppBar(title: Text('音乐信息')),
                                              body: SingleChildScrollView(
                                                  child:
                                                      NativeProperties(s)))))));
                        }),
                        if (offset < total)
                          TextButton(
                              onPressed: busy ? null : () => load(next: true),
                              child: Text('加载更多（$offset / $total）')),
                      ]))),
    ]);
    return widget.embedded
        ? content
        : Scaffold(appBar: AppBar(title: Text(widget.title)), body: content);
  }
}
