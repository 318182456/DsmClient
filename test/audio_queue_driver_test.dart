// @dart=2.10
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:dsm_client/models/media_queue.dart';
import 'package:dsm_client/providers/audio_player_provider.dart';

class QueuePlatform extends JustAudioPlatform {
  QueueDriver driver;
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async =>
      driver = QueueDriver(request.id);
  @override
  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    await driver?.dispose(DisposeRequest());
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
          DisposeAllPlayersRequest request) async =>
      DisposeAllPlayersResponse();
}

class QueueDriver extends AudioPlayerPlatform {
  final events = StreamController<PlaybackEventMessage>.broadcast();
  final done = Completer<void>();
  LoadRequest loaded;
  int index = 0;
  int plays = 0;
  bool closed = false;
  QueueDriver(String id) : super(id);
  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => events.stream;
  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => Stream.empty();
  void emit(int value) {
    index = value;
    events.add(PlaybackEventMessage(
        processingState: ProcessingStateMessage.ready,
        updatePosition: Duration.zero,
        updateTime: DateTime.now(),
        bufferedPosition: Duration.zero,
        duration: Duration(minutes: 2),
        currentIndex: value));
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    loaded = request;
    emit(request.initialIndex ?? 0);
    return LoadResponse(duration: Duration(minutes: 2));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    plays++;
    await done.future;
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();
  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    emit(request.index ?? index);
    return SeekResponse();
  }

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    if (!closed) {
      closed = true;
      if (!done.isCompleted) done.complete();
      await events.close();
    }
    return DisposeResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();
  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();
  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async =>
      SetPitchResponse();
  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
          SetSkipSilenceRequest request) async =>
      SetSkipSilenceResponse();
  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();
  @override
  Future<SetShuffleModeResponse> setShuffleMode(
          SetShuffleModeRequest request) async =>
      SetShuffleModeResponse();
  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
          SetShuffleOrderRequest request) async =>
      SetShuffleOrderResponse();
  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
          SetAndroidAudioAttributesRequest request) async =>
      SetAndroidAudioAttributesResponse();
  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
              SetAutomaticallyWaitsToMinimizeStallingRequest request) async =>
          SetAutomaticallyWaitsToMinimizeStallingResponse();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'Real audio adapter loads concatenated tracks from zero and updates title on native next event',
      () async {
    final original = JustAudioPlatform.instance;
    final platform = QueuePlatform();
    JustAudioPlatform.instance = platform;
    const session = MethodChannel('com.ryanheise.audio_session');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(session, (call) async => null);
    final provider = AudioPlayerProvider(
        player: ja.AudioPlayer(
            handleAudioSessionActivation: false,
            handleInterruptions: false,
            androidApplyAudioAttributes: false));
    try {
      await provider.playQueue([
        MediaTrack(id: 'a', name: '第一首', url: 'https://example.test/a.mp3'),
        MediaTrack(id: 'b', name: '第二首', url: 'https://example.test/b.mp3')
      ]).timeout(Duration(seconds: 3));
      expect(provider.player.sequence.length, 2);
      expect(platform.driver.loaded.audioSourceMessage,
          isA<ConcatenatingAudioSourceMessage>());
      expect(platform.driver.loaded.initialPosition, Duration.zero);
      expect(platform.driver.loaded.initialIndex, 0);
      platform.driver.emit(1);
      await Future.delayed(Duration(milliseconds: 20));
      expect(platform.driver.plays, 1);
      expect(provider.name, '第二首');
      expect(provider.index, 1);
      expect(provider.url, 'https://example.test/b.mp3');
      await provider.player.seekToPrevious();
      await Future.delayed(Duration(milliseconds: 20));
      expect(provider.name, '第一首');
    } finally {
      await provider.player.dispose();
      provider.dispose();
      JustAudioPlatform.instance = original;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(session, null);
    }
  });
}
