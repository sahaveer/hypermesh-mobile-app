import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import '../services/api_service.dart';
import '../services/device_controls_service.dart';

class PlayerProvider extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ApiService apiService;

  Song? _currentSong;
  List<Song> _playlist = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  bool _loadFailed = false;
  int _selection = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isShuffle = false;
  LoopMode _loopMode = LoopMode.off;
  double _volume = 1.0;

  PlayerProvider({required this.apiService}) {
    _initListeners();
    _initVolume();
  }

  Song? get currentSong => _currentSong;
  bool get isPlaying => _isPlaying;
  bool get loadFailed => _loadFailed;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isShuffle => _isShuffle;
  bool get isRepeat => _loopMode == LoopMode.one;
  double get volume => _volume;

  Future<void> _initVolume() async {
    if (Platform.isAndroid) {
      _volume = await DeviceControlsService.getDeviceVolume();
      notifyListeners();
    }
  }

  Future<void> setVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    _volume = clamped;
    notifyListeners();
    if (Platform.isAndroid) {
      await DeviceControlsService.setDeviceVolume(clamped);
    } else {
      await _audioPlayer.setVolume(clamped);
    }
  }

  void _initListeners() {
    _audioPlayer.playerStateStream.listen((state) {
      _isPlaying = !_loadFailed && state.playing &&
          state.processingState == ProcessingState.ready;
      if (state.processingState == ProcessingState.completed) {
        next();
      }
      notifyListeners();
    });

    _audioPlayer.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _audioPlayer.durationStream.listen((dur) {
      if (dur != null) {
        _duration = dur;
        notifyListeners();
      }
    });
  }

  Future<void> playSong(Song song, List<Song> contextPlaylist) async {
    final selection = ++_selection;
    _loadFailed = false;
    _isPlaying = false;
    _currentSong = song;
    _playlist = contextPlaylist;
    _currentIndex = _playlist.indexWhere((s) => s.id == song.id);
    _position = Duration.zero;
    _duration = Duration(seconds: song.duration.toInt());
    notifyListeners();

    try {
      await _audioPlayer.stop();
      if (selection != _selection) return;
      if (song.demoAsset != null) {
        await _audioPlayer.setAsset(song.demoAsset!);
      } else if (song.localFilePath != null && File(song.localFilePath!).existsSync()) {
        await _audioPlayer.setFilePath(song.localFilePath!);
      } else {
        final streamUrl = song.getStreamUrl(apiService.hostUrl);
        await _audioPlayer.setUrl(streamUrl);
      }
      if (selection == _selection) await _audioPlayer.play();
    } catch (_) {
      if (selection != _selection) return;
      _isPlaying = false;
      _loadFailed = true;
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    if (_currentSong == null) return;
    if (_loadFailed) {
      await playSong(_currentSong!, _playlist);
    } else if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  Future<void> seek(Duration newPosition) async {
    await _audioPlayer.seek(newPosition);
  }

  void next() {
    if (_playlist.isEmpty || _currentIndex < 0) return;
    int nextIdx = (_currentIndex + 1) % _playlist.length;
    playSong(_playlist[nextIdx], _playlist);
  }

  void previous() {
    if (_playlist.isEmpty || _currentIndex < 0) return;
    if (_position.inSeconds > 3) {
      seek(Duration.zero);
      return;
    }
    int prevIdx = (_currentIndex - 1 + _playlist.length) % _playlist.length;
    playSong(_playlist[prevIdx], _playlist);
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    _audioPlayer.setShuffleModeEnabled(_isShuffle);
    notifyListeners();
  }

  void toggleRepeat() {
    _loopMode = (_loopMode == LoopMode.off) ? LoopMode.one : LoopMode.off;
    _audioPlayer.setLoopMode(_loopMode);
    notifyListeners();
  }

  @override
  void dispose() {
    _selection++;
    _audioPlayer.dispose();
    super.dispose();
  }
}
