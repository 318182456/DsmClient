import 'dart:math';

import 'package:dsm_client/providers/audio_player_provider.dart';
import 'package:dsm_client/themes/app_theme.dart';
import 'package:dsm_client/widgets/neu_back_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart' as ja;

import 'package:provider/provider.dart';

class AudioPlayer extends StatefulWidget {
  AudioPlayer({this.name, this.url, Key key}) : super(key: key);
  final String name;
  final String url;
  @override
  State<AudioPlayer> createState() => _AudioPlayerState();
}

class _AudioPlayerState extends State<AudioPlayer> {
  ja.AudioPlayer player;
  String title = "";
  String playbackError = '';
  @override
  void initState() {
    var audioPlayerProvider = context.read<AudioPlayerProvider>();
    player = audioPlayerProvider.player;
    if (widget.url != null) {
      title = widget.name ?? "";
      if (audioPlayerProvider.url != widget.url ||
          player.processingState == ja.ProcessingState.idle) {
        audioPlayerProvider.setUrl(widget.url, title);
        setSource();
      }
    } else {
      title = audioPlayerProvider.name;
    }
    setState(() {});
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  setSource() async {
    final provider = context.read<AudioPlayerProvider>();
    try {
      await player.setUrl(widget.url);
      await player.play();
    } catch (_) {
      if (provider.url == widget.url) provider.setUrl(null, title);
      if (mounted) setState(() => playbackError = '无法播放此音频，请检查连接、访问权限或音频格式');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(leading: AppBackButton(context), title: Text('正在播放')),
      body: SafeArea(
          child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, 20, 24, 32),
                  child: Center(
                      child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: 420),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('NAS 音乐资料库',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.caption),
                                SizedBox(height: 24),
                                Center(
                                    child: Container(
                                        constraints: BoxConstraints(
                                            maxWidth: min(300.0,
                                                constraints.maxWidth - 48)),
                                        decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(28),
                                            color: Theme.of(context).cardColor,
                                            border: Border.all(
                                                color: Theme.of(context)
                                                    .dividerColor)),
                                        padding: EdgeInsets.all(28),
                                        child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            child: AspectRatio(
                                                aspectRatio: 1,
                                                child: ColoredBox(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primaryContainer,
                                                    child: Center(
                                                        child: Icon(Icons.album_outlined,
                                                            size: 100,
                                                            color: Theme.of(context)
                                                                .colorScheme
                                                                .onPrimaryContainer))))))),
                                SizedBox(height: 28),
                                Text(title ?? '音乐',
                                    textAlign: TextAlign.center,
                                    style:
                                        Theme.of(context).textTheme.headline5),
                                SizedBox(height: 8),
                                Text('Audio Station',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.caption),
                                SizedBox(height: 24),
                                if (playbackError.isNotEmpty)
                                  Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Text(playbackError,
                                          style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error))),
                                SeekBar(
                                    player: player,
                                    onChangeEnd: (position) =>
                                        player.seek(position)),
                                SizedBox(height: 20),
                                Center(child: ControlButtons(player)),
                              ])))))));
}

class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  PositionData(this.position, this.bufferedPosition, this.duration);
}

class ControlButtons extends StatelessWidget {
  final ja.AudioPlayer player;

  const ControlButtons(this.player, {Key key}) : super(key: key);
  void showSliderDialog({
    @required BuildContext context,
    @required String title,
    @required int divisions,
    @required double min,
    @required double max,
    String valueSuffix = '',
    // TODO: Replace these two by ValueStream.
    @required double value,
    @required Stream<double> stream,
    @required ValueChanged<double> onChanged,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, textAlign: TextAlign.center),
        content: StreamBuilder<double>(
          stream: stream,
          builder: (context, snapshot) => SizedBox(
            height: 100.0,
            child: Column(
              children: [
                Text('${snapshot.data?.toStringAsFixed(1)}$valueSuffix',
                    style: const TextStyle(
                        fontFamily: 'Fixed',
                        fontWeight: FontWeight.bold,
                        fontSize: 24.0)),
                Slider(
                  divisions: divisions,
                  min: min,
                  max: max,
                  value: snapshot.data ?? value,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 24,
          runSpacing: 16,
          children: [
            IconButton(
                tooltip: '调整音量',
                icon: Icon(Icons.volume_up_outlined),
                iconSize: 26,
                onPressed: () => showSliderDialog(
                    context: context,
                    title: '音量',
                    divisions: 10,
                    min: 0,
                    max: 1,
                    value: player.volume,
                    stream: player.volumeStream,
                    onChanged: player.setVolume)),
            StreamBuilder<ja.PlayerState>(
                stream: player.playerStateStream,
                builder: (context, snapshot) {
                  final state = snapshot.data;
                  final waiting = state?.processingState ==
                          ja.ProcessingState.loading ||
                      state?.processingState == ja.ProcessingState.buffering;
                  final playing = state?.playing == true &&
                      state?.processingState != ja.ProcessingState.completed;
                  return SizedBox(
                      width: 76,
                      height: 76,
                      child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              shape: CircleBorder(), padding: EdgeInsets.zero),
                          onPressed: waiting
                              ? null
                              : () async {
                                  if (playing) {
                                    await player.pause();
                                  } else {
                                    if (state?.processingState ==
                                        ja.ProcessingState.completed)
                                      await player.seek(Duration.zero);
                                    await player.play();
                                  }
                                },
                          child: waiting
                              ? SizedBox(
                                  width: 26,
                                  height: 26,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : Icon(
                                  playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 38,
                                  semanticLabel: playing ? '暂停' : '播放')));
                }),
            StreamBuilder<double>(
                stream: player.speedStream,
                builder: (context, snapshot) => TextButton(
                    onPressed: () => showSliderDialog(
                        context: context,
                        title: '播放速度',
                        divisions: 15,
                        min: .5,
                        max: 2,
                        value: player.speed,
                        stream: player.speedStream,
                        valueSuffix: '×',
                        onChanged: player.setSpeed),
                    child:
                        Text('${(snapshot.data ?? 1).toStringAsFixed(1)}×'))),
          ]);
}

class SeekBar extends StatefulWidget {
  final ja.AudioPlayer player;
  final ValueChanged<Duration> onChanged;
  final ValueChanged<Duration> onChangeEnd;

  const SeekBar({
    Key key,
    @required this.player,
    this.onChanged,
    this.onChangeEnd,
  }) : super(key: key);

  @override
  SeekBarState createState() => SeekBarState();
}

class HiddenThumbComponentShape extends SliderComponentShape {
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.zero;

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    @required Animation<double> activationAnimation,
    @required Animation<double> enableAnimation,
    @required bool isDiscrete,
    @required TextPainter labelPainter,
    @required RenderBox parentBox,
    @required SliderThemeData sliderTheme,
    @required TextDirection textDirection,
    @required double value,
    @required double textScaleFactor,
    @required Size sizeWithOverflow,
  }) {}
}

class SeekBarState extends State<SeekBar> {
  double _dragValue;
  SliderThemeData _sliderThemeData;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _sliderThemeData = SliderTheme.of(context).copyWith(
      trackHeight: 2.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SliderTheme(
          data: _sliderThemeData.copyWith(
            thumbShape: HiddenThumbComponentShape(),
            activeTrackColor: Colors.blue.shade100,
            inactiveTrackColor: Colors.grey.shade300,
          ),
          child: ExcludeSemantics(
            child: StreamBuilder(
              stream: widget.player.bufferedPositionStream,
              builder:
                  (BuildContext context, AsyncSnapshot<Duration> snapshot) {
                Duration _duration = widget.player.duration ?? Duration.zero;
                Duration _position = snapshot.data ?? Duration.zero;
                return Slider(
                  min: 0.0,
                  max: _duration.inMilliseconds.toDouble(),
                  value: min(_position.inMilliseconds.toDouble(),
                      _duration.inMilliseconds.toDouble()),
                  onChanged: (value) {
                    setState(() {
                      _dragValue = value;
                    });
                    widget.onChanged
                        ?.call(Duration(milliseconds: value.round()));
                  },
                  onChangeEnd: (value) {
                    widget.onChangeEnd
                        ?.call(Duration(milliseconds: value.round()));
                    _dragValue = null;
                  },
                );
              },
            ),
          ),
        ),
        StreamBuilder(
          stream: widget.player.positionStream,
          builder: (BuildContext context, AsyncSnapshot<Duration> snapshot) {
            Duration _duration = widget.player.duration ?? Duration.zero;
            Duration _position = snapshot.data ?? Duration.zero;
            Duration _remaining = _duration - _position;
            return Column(
              children: [
                Slider(
                  min: 0.0,
                  max: _duration.inMilliseconds.toDouble(),
                  value: min(_dragValue ?? _position.inMilliseconds.toDouble(),
                      _duration.inMilliseconds.toDouble()),
                  onChanged: (value) {
                    setState(() {
                      _dragValue = value;
                    });
                    widget.onChanged
                        ?.call(Duration(milliseconds: value.round()));
                  },
                  onChangeEnd: (value) {
                    widget.onChangeEnd
                        ?.call(Duration(milliseconds: value.round()));
                    _dragValue = null;
                  },
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                          RegExp(r'((^0*[1-9]\d*:)?\d{2}:\d{2})\.\d+$')
                                  .firstMatch("$_position")
                                  ?.group(1) ??
                              '$_position',
                          style: TextStyle(
                              color: AppTheme.of(context).placeholderColor,
                              fontSize: 12)),
                      Text(
                          RegExp(r'((^0*[1-9]\d*:)?\d{2}:\d{2})\.\d+$')
                                  .firstMatch("$_remaining")
                                  ?.group(1) ??
                              '$_remaining',
                          style: TextStyle(
                              color: AppTheme.of(context).placeholderColor,
                              fontSize: 12))
                    ],
                  ),
                )
              ],
            );
          },
        ),
      ],
    );
  }
}
