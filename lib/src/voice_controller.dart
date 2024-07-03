import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:just_audio/just_audio.dart';
import 'package:voice_message_package/src/helpers/play_status.dart';
import 'package:voice_message_package/src/helpers/utils.dart';

class VoiceController extends MyTicker {
  static VoiceController? _currentPlayingController;

  final String audioSrc;
  late Duration maxDuration;
  Duration currentDuration = Duration.zero;
  final Function() onComplete;
  final Function() onPlaying;
  final Function() onPause;
  final Function(Object)? onError;
  final double noiseWidth = 50.5.w();
  late AnimationController animController;
  final AudioPlayer _player = AudioPlayer();
  final bool isFile;
  final String? cacheKey;
  PlayStatus playStatus = PlayStatus.init;
  PlaySpeed speed = PlaySpeed.x1;
  ValueNotifier updater = ValueNotifier(null);
  List<double>? randoms;
  StreamSubscription? positionStream;
  StreamSubscription? playerStateStream;
  double? downloadProgress = 0;
  final int noiseCount;

  double get currentMillSeconds {
    final c = currentDuration.inMilliseconds.toDouble();
    if (c >= maxMillSeconds) {
      return maxMillSeconds;
    }
    return c;
  }

  bool isSeeking = false;

  bool get isPlaying => playStatus == PlayStatus.playing;

  bool get isInit => playStatus == PlayStatus.init;

  bool get isDownloading => playStatus == PlayStatus.downloading;

  bool get isDownloadError => playStatus == PlayStatus.downloadError;

  bool get isStop => playStatus == PlayStatus.stop;

  bool get isPause => playStatus == PlayStatus.pause;

  double get maxMillSeconds => maxDuration.inMilliseconds.toDouble();

  StreamSubscription<FileResponse>? downloadStreamSubscription;

  VoiceController({
    required this.audioSrc,
    required this.maxDuration,
    required this.isFile,
    required this.onComplete,
    required this.onPause,
    required this.onPlaying,
    this.noiseCount = 24,
    this.onError,
    this.randoms,
    this.cacheKey,
  }) {
    if (randoms?.isEmpty ?? true) _setRandoms();
    animController = AnimationController(
      vsync: this,
      upperBound: noiseWidth,
      duration: maxDuration,
    );
    init();
    _listenToRemindingTime();
    _listenToPlayerState();
  }

  Future init() async {
    await setMaxDuration(audioSrc);
    _updateUi();
  }

  Future play() async {
    if (VoiceController._currentPlayingController != null &&
        VoiceController._currentPlayingController != this) {
      await VoiceController._currentPlayingController!.stopPlaying();
    }
    VoiceController._currentPlayingController = this;

    try {
      playStatus = PlayStatus.downloading;
      _updateUi();
      if (isFile) {
        final path = await _getFileFromCache();
        await startPlaying(path);
        onPlaying();
      } else {
        downloadStreamSubscription = _getFileFromCacheWithProgress()
            .listen((FileResponse fileResponse) async {
          if (fileResponse is FileInfo) {
            await startPlaying(fileResponse.file.path);
            onPlaying();
          } else if (fileResponse is DownloadProgress) {
            _updateUi();
            downloadProgress = fileResponse.progress;
          }
        });
      }
    } catch (err) {
      playStatus = PlayStatus.downloadError;
      _updateUi();
      if (onError != null) {
        onError!(err);
      } else {
        rethrow;
      }
    }
  }

  void _listenToRemindingTime() {
    positionStream = _player.positionStream.listen((Duration p) async {
      if (!isDownloading) currentDuration = p;

      final value = (noiseWidth * currentMillSeconds) / maxMillSeconds;
      animController.value = value;
      _updateUi();
      if (p.inMilliseconds >= maxMillSeconds) {
        await _player.stop();
        currentDuration = Duration.zero;
        playStatus = PlayStatus.init;
        animController.reset();
        _updateUi();
        onComplete();
      }
    });
  }

  void _updateUi() {
    updater.notifyListeners();
  }

  Future stopPlaying() async {
    _player.pause();
    playStatus = PlayStatus.stop;
  }

  Future startPlaying(String path) async {
    await _player.setAudioSource(
      AudioSource.uri(Uri.file(path)),
      initialPosition: currentDuration,
    );
    _player.play();
    _player.setSpeed(speed.getSpeed);
  }

  Future<void> dispose() async {
    await _player.dispose();
    positionStream?.cancel();
    playerStateStream?.cancel();
    animController.dispose();
  }

  void onSeek(Duration duration) {
    isSeeking = false;
    currentDuration = duration;
    _updateUi();
    _player.seek(duration);
  }

  void pausePlaying() {
    _player.pause();
    playStatus = PlayStatus.pause;
    _updateUi();
    onPause();
  }

  Future<String> _getFileFromCache() async {
    if (isFile) {
      return audioSrc;
    }
    final p =
    await DefaultCacheManager().getSingleFile(audioSrc, key: cacheKey);
    return p.path;
  }

  Stream<FileResponse> _getFileFromCacheWithProgress() {
    if (isFile) {
      throw Exception("This method is not applicable for local files.");
    }
    return DefaultCacheManager()
        .getFileStream(audioSrc, key: cacheKey, withProgress: true);
  }

  void cancelDownload() {
    downloadStreamSubscription?.cancel();
    playStatus = PlayStatus.init;
    _updateUi();
  }

  void _listenToPlayerState() {
    playerStateStream = _player.playerStateStream.listen((event) async {
      if (event.processingState == ProcessingState.completed) {
      } else if (event.playing) {
        playStatus = PlayStatus.playing;
        _updateUi();
      }
    });
  }

  void changeSpeed() {
    switch (speed) {
      case PlaySpeed.x1:
        speed = PlaySpeed.x1_5;
        break;
      // case PlaySpeed.x1_25:
      //   speed = PlaySpeed.x1_5;
      //   break;
      case PlaySpeed.x1_5:
        speed = PlaySpeed.x2;
        break;
      // case PlaySpeed.x1_75:
      //   speed = PlaySpeed.x2;
      //   break;
      case PlaySpeed.x2:
        speed = PlaySpeed.x1;
        break;
      // case PlaySpeed.x2_25:
      //   speed = PlaySpeed.x1;
      //   break;
    }
    _player.setSpeed(speed.getSpeed);
    _updateUi();
  }

  void onChangeSliderStart(double value) {
    isSeeking = true;
    pausePlaying();
  }

  void _setRandoms() {
    randoms = [];
    for (var i = 0; i < noiseCount; i++) {
      randoms!.add(5.74.w() * Random().nextDouble() + .26.w());
    }
  }

  void onChanging(double d) {
    currentDuration = Duration(milliseconds: d.toInt());
    final value = (noiseWidth * d) / maxMillSeconds;
    animController.value = value;
    _updateUi();
  }

  String get remindingTime {
    if (currentDuration == Duration.zero) {
      return maxDuration.formattedTime;
    }
    if (isSeeking || isPause) {
      return currentDuration.formattedTime;
    }
    if (isInit) {
      return maxDuration.formattedTime;
    }
    return currentDuration.formattedTime;
  }

  Future setMaxDuration(String path) async {
    try {
      final maxDuration =
      isFile ? await _player.setFilePath(path) : await _player.setUrl(path);
      if (maxDuration != null) {
        this.maxDuration = maxDuration;
        animController.duration = maxDuration;
      }
    } catch (err) {
      if (kDebugMode) {
        debugPrint("cant get the max duration from the path $path");
      }
      if (onError != null) {
        onError!(err);
      }
    }
  }
}

class MyTicker extends TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) {
    return Ticker(onTick);
  }
}
