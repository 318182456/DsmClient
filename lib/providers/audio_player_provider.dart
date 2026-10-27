import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:dsm_client/models/media_queue.dart';

class AudioPlayerProvider with ChangeNotifier {
  AudioPlayer _player;
  String _url, _name;
  String error = '';
  List<MediaTrack> _queue = [];
  StreamSubscription<int> _indexSubscription;
  bool _disposed = false;
  int _generation = 0;
  AudioPlayer get player => _player;
  String get url => _url;
  String get name => _name;
  List<MediaTrack> get queue => List.unmodifiable(_queue);
  int get index => _player.currentIndex ?? 0;
  AudioPlayerProvider() {
    _player = AudioPlayer();
    _observe();
  }
  void _observe() {
    _indexSubscription = _player.currentIndexStream.listen((value) {
      if (value != null && value >= 0 && value < _queue.length) {
        _url = _queue[value].url;
        _name = _queue[value].name;
        if (!_disposed) notifyListeners();
      }
    }, onError: (Object exception) {
      playbackFailed();
    });
  }

  void playbackFailed() {
    if (!_disposed) {
      error = '音频播放失败，请检查连接、权限或格式';
      notifyListeners();
    }
  }

  void setPlayer(AudioPlayer player) {
    _indexSubscription?.cancel();
    _player = player;
    _observe();
    if (!_disposed) notifyListeners();
  }

  void setUrl(String url, String name) {
    _url = url;
    _name = name;
  }

  Future<void> playQueue(List<MediaTrack> tracks) async {
    if (tracks.isEmpty) return;
    final generation = ++_generation;
    error = '';
    _queue = List.from(tracks);
    _url = tracks.first.url;
    _name = tracks.first.name;
    await _player.setAudioSource(
        ConcatenatingAudioSource(
            children: tracks
                .map((track) => AudioSource.uri(Uri.parse(track.url)))
                .toList()),
        initialIndex: 0,
        initialPosition: Duration.zero);
    if (_disposed || generation != _generation) return;
    notifyListeners();
    _player.play().catchError((Object error) {
      playbackFailed();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _indexSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }
}
