import 'package:dsm_client/util/media_delete.dart';
import 'package:dsm_client/models/media_queue.dart';
import 'package:dsm_client/widgets/media_actions.dart';
import 'package:dsm_client/widgets/adaptive_tab_bar.dart';
import 'package:dsm_client/models/program_section.dart';
import 'package:dsm_client/pages/common/audio_player.dart';
import 'package:dsm_client/util/function.dart';
import 'package:dsm_client/util/program_api.dart';
import 'package:flutter/material.dart';
import 'program_page.dart';
import 'package:dsm_client/widgets/workspace.dart';
import 'package:dsm_client/widgets/nas_app_icon.dart';
import 'package:dsm_client/models/nas_package.dart';

typedef AudioLibraryLoader = Future<Map> Function(
    ProgramSection section, Map<String, dynamic> params);

class AudioStation extends StatelessWidget {
  final AudioLibraryLoader loader;
  const AudioStation({this.loader});
  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: 5,
      child: Scaffold(
          appBar: AppBar(title: Text('Audio Station'), actions: [
            IconButton(
                tooltip: '搜索音乐',
                icon: Icon(Icons.search),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => AudioLibrary('搜索', 'Search', 'songs',
                            search: true, loader: loader))))
          ]),
          body:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            WorkspaceHeader(
                title: '音乐资料库',
                subtitle: '属于你的音乐，随时聆听。',
                leading: NasAppIcon(
                    NasPackage.fromJson(
                        {'id': 'AudioStation', 'name': 'Audio Station'}),
                    size: 48)),
            Container(
                margin: EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16)),
                child: AdaptiveTabBar(
                    isScrollable: true,
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor:
                        Theme.of(context).colorScheme.onPrimaryContainer,
                    unselectedLabelColor:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                    indicator: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12)),
                    tabs: [
                      Tab(text: '歌曲'),
                      Tab(text: '专辑'),
                      Tab(text: '歌手'),
                      Tab(text: '播放列表'),
                      Tab(text: '文件夹')
                    ])),
            Expanded(
                child: TabBarView(children: [
              AudioLibrary('歌曲', 'Song', 'songs',
                  embedded: true, loader: loader),
              AudioLibrary('专辑', 'Album', 'albums',
                  embedded: true, loader: loader),
              AudioLibrary('歌手', 'Artist', 'artists',
                  embedded: true, loader: loader),
              AudioLibrary('播放列表', 'Playlist', 'playlists',
                  embedded: true, loader: loader),
              AudioLibrary('文件夹', 'Folder', 'items',
                  embedded: true, loader: loader),
            ])),
          ])));
}

class AudioLibrary extends StatefulWidget {
  final String title, kind, listKey, method;
  final Map<String, dynamic> filter;
  final bool embedded, search;
  final AudioLibraryLoader loader;
  const AudioLibrary(this.title, this.kind, this.listKey,
      {this.loader,
      this.filter = const {},
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
      final section = ProgramSection(
          '', 'SYNO.AudioStation.${widget.kind}', widget.method,
          version: widget.kind == 'Artist' ? 4 : 3);
      final params = <String, dynamic>{
        'offset': next ? offset : 0,
        'limit': 100,
        'library': 'all',
        if (widget.kind == 'Song')
          'additional': 'song_tag,song_audio,song_rating',
        if (widget.kind == 'Playlist' && widget.method == 'getinfo')
          'additional': 'songs',
        if (widget.search) 'keyword': keyword,
        ...widget.filter,
      };
      final result = widget.loader != null
          ? await widget.loader(section, params)
          : await ProgramApi.call(section, params: params);
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
                filter: filter, method: method, loader: widget.loader)));
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

  MediaTrack track(Map song) => MediaTrack(
      id: '${song['id']}',
      name: '${song['title'] ?? song['name'] ?? '音乐'}',
      path: song['path'],
      url: ProgramApi.url(
          ProgramSection('', 'SYNO.AudioStation.Stream', 'stream', version: 2),
          {'id': song['id'], 'format': 'raw'}));
  Future<void> mediaMenu(Map song) async {
    final playable = widget.kind == 'Song' ||
        widget.kind == 'Search' ||
        widget.kind == 'Folder' ||
        widget.method == 'getinfo';
    if (!playable || song['type'] == 'folder' || song['id'] == null) {
      showInfo(song);
      return;
    }
    final path = '${song['path'] ?? ''}';
    final deletable = path.startsWith('/') &&
        !path.startsWith('/volume') &&
        !path.split('/').contains('..');
    final action = await showMediaActions(
        context, '${song['title'] ?? song['name'] ?? '音乐'}',
        canDelete: deletable);
    if (!mounted || action == null) return;
    if (action == 'details') {
      showInfo(song);
      return;
    }
    if (action == 'delete') {
      final yes = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
                  title: Text('删除音乐文件'),
                  content: Text(
                      '将删除 NAS 上的原始音乐文件“${song['title'] ?? song['name']}”，是否继续？'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialog, false),
                        child: Text('取消')),
                    TextButton(
                        onPressed: () => Navigator.pop(dialog, true),
                        child: Text('确认删除'))
                  ]));
      if (yes != true || !mounted) return;
      try {
        await deleteMediaFile(path);
        if (mounted)
          setState(() => items.removeWhere((item) => item['id'] == song['id']));
      } catch (_) {
        if (mounted) setState(() => error = '删除请求失败，请检查文件权限');
      }
      return;
    }
    final selected = track(song);
    final queue = MediaQueue.from(
        items
            .where((s) => s['id'] != null && s['type'] != 'folder')
            .map(track)
            .toList(),
        selected,
        continuous: action == 'continuous');
    if (mounted)
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => AudioPlayer(
                  name: selected.name,
                  url: selected.url,
                  tracks: queue,
                  restart: true)));
  }

  void showInfo(Map song) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => Scaffold(
              appBar: AppBar(title: Text('音乐信息')),
              body: SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Card(child: NativeProperties(song))))));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final songs = widget.kind == 'Song' ||
        widget.kind == 'Search' ||
        widget.method == 'getinfo';
    final grid = widget.kind == 'Album' || widget.kind == 'Artist';
    final content = Column(children: [
      if (widget.search)
        Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
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
                    hintText: '歌曲、专辑或歌手',
                    prefixIcon: Icon(Icons.search),
                    suffixIcon: IconButton(
                        tooltip: '开始搜索',
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
                  child: CustomScrollView(
                      physics: AlwaysScrollableScrollPhysics(),
                      slivers: [
                        if (error.isNotEmpty)
                          SliverToBoxAdapter(
                              child: WorkspaceEmpty('曲库暂时无法加载',
                                  icon: Icons.wifi_off_rounded,
                                  detail: error,
                                  action: TextButton.icon(
                                      onPressed: () => load(),
                                      icon: Icon(Icons.refresh),
                                      label: Text('重新加载')))),
                        if (error.isEmpty && items.isEmpty)
                          SliverToBoxAdapter(
                              child: WorkspaceEmpty(
                                  widget.search && keyword.isEmpty
                                      ? '找到想听的那首歌'
                                      : '这里还没有音乐',
                                  icon: Icons.library_music_outlined,
                                  detail: widget.search && keyword.isEmpty
                                      ? '输入歌曲、专辑或歌手名称，搜索 NAS 曲库。'
                                      : '下拉刷新，或检查 Audio Station 的音乐资料库。')),
                        if (items.isNotEmpty)
                          SliverToBoxAdapter(
                              child: Padding(
                                  padding: EdgeInsets.fromLTRB(20, 18, 20, 12),
                                  child: Row(children: [
                                    Expanded(
                                        child: Text(
                                            widget.search
                                                ? '搜索结果'
                                                : '全部${widget.title}',
                                            style: theme.textTheme.subtitle1)),
                                    Text('$total ${songs ? '首' : '项'}',
                                        style: theme.textTheme.caption)
                                  ]))),
                        if (grid)
                          SliverPadding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              sliver: SliverGrid(
                                  gridDelegate:
                                      SliverGridDelegateWithMaxCrossAxisExtent(
                                          maxCrossAxisExtent: 240,
                                          mainAxisSpacing: 12,
                                          crossAxisSpacing: 12,
                                          mainAxisExtent: 200),
                                  delegate: SliverChildBuilderDelegate(
                                      (context, i) => AudioCollectionCard(
                                          items[i],
                                          artist: widget.kind == 'Artist',
                                          onTap: () => select(items[i])),
                                      childCount: items.length)))
                        else
                          SliverPadding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                      (context, i) => AudioTrackTile(items[i],
                                          index: i + 1,
                                          song: songs,
                                          onTap: () => select(items[i]),
                                          onInfo: () => mediaMenu(items[i]),
                                          onLongPress: () =>
                                              mediaMenu(items[i])),
                                      childCount: items.length))),
                        if (offset < total)
                          SliverToBoxAdapter(
                              child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: TextButton(
                                      onPressed:
                                          busy ? null : () => load(next: true),
                                      child: Text(busy
                                          ? '正在加载…'
                                          : '加载更多（$offset / $total）')))),
                        SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ]))),
    ]);
    return widget.embedded
        ? content
        : Scaffold(appBar: AppBar(title: Text(widget.title)), body: content);
  }
}

class AudioTrackTile extends StatelessWidget {
  final Map item;
  final int index;
  final bool song;
  final VoidCallback onTap, onInfo, onLongPress;
  const AudioTrackTile(this.item,
      {this.index = 1,
      this.song = true,
      this.onTap,
      this.onInfo,
      this.onLongPress});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tags = (item['additional'] ?? {})['song_tag'] ?? {};
    final artist =
        '${tags['artist'] ?? item['display_artist'] ?? item['artist'] ?? ''}';
    final album = '${tags['album'] ?? ''}';
    final detail = [artist, album].where((v) => v.isNotEmpty).join(' · ');
    final audio = (item['additional'] ?? {})['song_audio'] ?? {};
    final seconds = num.tryParse('${audio['duration'] ?? ''}')?.toInt() ?? 0;
    return Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: Material(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                onLongPress: onLongPress,
                child: Padding(
                    padding: EdgeInsets.fromLTRB(14, 12, 4, 12),
                    child: Row(children: [
                      Container(
                          width: 42,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer
                                  .withOpacity(.55),
                              borderRadius: BorderRadius.circular(12)),
                          child: song
                              ? Text('$index'.padLeft(2, '0'),
                                  style: theme.textTheme.subtitle2.copyWith(
                                      color:
                                          theme.colorScheme.onPrimaryContainer))
                              : Icon(
                                  item['type'] == 'folder'
                                      ? Icons.folder_outlined
                                      : Icons.queue_music,
                                  color: theme.colorScheme.onPrimaryContainer)),
                      SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('${item['title'] ?? item['name'] ?? '未命名'}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.subtitle1),
                            if (detail.isNotEmpty) ...[
                              SizedBox(height: 4),
                              Text(detail,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.caption)
                            ],
                          ])),
                      if (seconds > 0 &&
                          MediaQuery.of(context).textScaleFactor <= 1.3)
                        Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Text(
                                '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                                style: theme.textTheme.caption)),
                      IconButton(
                          tooltip: '音乐操作',
                          onPressed: onInfo,
                          icon: Icon(Icons.more_horiz, size: 22)),
                    ])))));
  }
}

class AudioCollectionCard extends StatelessWidget {
  final Map item;
  final bool artist;
  final VoidCallback onTap;
  const AudioCollectionCard(this.item, {this.artist = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
                padding: EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          child: Center(
                              child: Container(
                                  width: 88,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(
                                          artist ? 60 : 16)),
                                  child: Icon(
                                      artist
                                          ? Icons.person_outline
                                          : Icons.album_outlined,
                                      size: 42,
                                      color: theme
                                          .colorScheme.onPrimaryContainer)))),
                      SizedBox(height: 12),
                      Text('${item['name'] ?? '未命名'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.subtitle2),
                      if ((item['display_artist'] ?? item['album_artist'] ?? '')
                          .toString()
                          .isNotEmpty)
                        Text(
                            '${item['display_artist'] ?? item['album_artist']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.caption),
                    ]))));
  }
}
