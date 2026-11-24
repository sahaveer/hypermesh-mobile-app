import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import '../providers/hypermesh_provider.dart';
import '../models/video_item.dart';
import '../theme/app_theme.dart';
import '../widgets/download_destination_sheet.dart';
import '../services/device_controls_service.dart';

enum _ActiveGesture { none, brightness, volume, seek }

class VideoPlayerScreen extends StatefulWidget {
  final VideoItem video;
  final String hostUrl;

  const VideoPlayerScreen({
    super.key,
    required this.video,
    required this.hostUrl,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  bool _hasError = false;
  bool _isLandscape = false;

  // Gestures & HUD State
  _ActiveGesture _activeGesture = _ActiveGesture.none;
  Offset _panStartPosition = Offset.zero;
  bool _isLeftTouch = false;

  double _currentBrightness = 0.5;
  double _initialBrightness = 0.5;

  double _currentVolume = 0.5;
  double _initialVolume = 0.5;

  Duration _initialSeekPosition = Duration.zero;
  Duration _targetSeekPosition = Duration.zero;
  int _seekDeltaSeconds = 0;

  bool _showGestureHud = false;
  Timer? _gestureHudTimer;
  Timer? _hideControlsTimer;

  // Double Tap 10s Skip Feedback
  bool _showDoubleTapForward = false;
  bool _showDoubleTapRewind = false;
  Timer? _doubleTapTimer;

  @override
  void initState() {
    super.initState();
    _initPlayer();
    _loadInitialDeviceLevels();
    _startHideControlsTimer();
  }

  Future<void> _loadInitialDeviceLevels() async {
    final b = await DeviceControlsService.getScreenBrightness();
    final v = await DeviceControlsService.getDeviceVolume();
    if (mounted) {
      setState(() {
        _currentBrightness = b;
        _currentVolume = v;
      });
    }
  }

  Future<void> _initPlayer() async {
    final localPath = widget.video.localFilePath;
    final asset = widget.video.demoAsset;
    if (asset != null) {
      _controller = VideoPlayerController.asset(asset);
    } else if (localPath != null && File(localPath).existsSync()) {
      _controller = VideoPlayerController.file(File(localPath));
    } else {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.video.getStreamUrl(widget.hostUrl)),
      );
    }
    _controller.addListener(() {
      if (!mounted) return;
      setState(() => _hasError = _controller.value.hasError);
    });
    try {
      await _controller.initialize();
      if (!mounted) return;
      setState(() => _isInitialized = true);
      await _controller.play();
      if (mounted) _startHideControlsTimer();
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _gestureHudTimer?.cancel();
    _doubleTapTimer?.cancel();
    DeviceControlsService.resetScreenBrightness();
    // Strictly lock orientation back to portrait for the rest of the app
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    _controller.dispose();
    super.dispose();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_showControls) {
      _hideControlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _showControls && _controller.value.isPlaying) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _togglePlayPause() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
    });
    _startHideControlsTimer();
  }

  void _toggleOrientation() {
    setState(() {
      _isLandscape = !_isLandscape;
    });
    if (_isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
    _startHideControlsTimer();
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return "$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
    }
    return "$minutes:${seconds.toString().padLeft(2, '0')}";
  }

  // --- GESTURE PROCESSING ---

  void _onPanStart(DragStartDetails details, Size screenSize) {
    if (!_isInitialized) return;

    _panStartPosition = details.localPosition;
    _isLeftTouch = details.localPosition.dx < (screenSize.width / 2);
    _initialBrightness = _currentBrightness;
    _initialVolume = _currentVolume;
    _initialSeekPosition = _controller.value.position;
    _targetSeekPosition = _initialSeekPosition;
    _seekDeltaSeconds = 0;
    _activeGesture = _ActiveGesture.none;
    _gestureHudTimer?.cancel();
  }

  void _onPanUpdate(DragUpdateDetails details, Size screenSize) {
    if (!_isInitialized) return;

    final totalDelta = details.localPosition - _panStartPosition;

    // Disambiguate after 15px threshold
    if (_activeGesture == _ActiveGesture.none) {
      if (totalDelta.dx.abs() > 15 && totalDelta.dx.abs() > totalDelta.dy.abs()) {
        _activeGesture = _ActiveGesture.seek;
      } else if (totalDelta.dy.abs() > 15 && totalDelta.dy.abs() > totalDelta.dx.abs()) {
        _activeGesture = _isLeftTouch ? _ActiveGesture.brightness : _ActiveGesture.volume;
      }
    }

    if (_activeGesture == _ActiveGesture.none) return;

    // Hide standard controls during active gesture scrubbing
    if (_showControls) {
      setState(() => _showControls = false);
    }

    switch (_activeGesture) {
      case _ActiveGesture.brightness:
        final dragDistance = screenSize.height * 0.65;
        final deltaFraction = -totalDelta.dy / dragDistance;
        final newBrightness = (_initialBrightness + deltaFraction).clamp(0.01, 1.0);
        _currentBrightness = newBrightness;
        DeviceControlsService.setScreenBrightness(newBrightness);
        setState(() {
          _showGestureHud = true;
        });
        break;

      case _ActiveGesture.volume:
        final dragDistance = screenSize.height * 0.65;
        final deltaFraction = -totalDelta.dy / dragDistance;
        final newVolume = (_initialVolume + deltaFraction).clamp(0.0, 1.0);
        _currentVolume = newVolume;
        DeviceControlsService.setDeviceVolume(newVolume);
        _controller.setVolume(newVolume);
        setState(() {
          _showGestureHud = true;
        });
        break;

      case _ActiveGesture.seek:
        final totalDuration = _controller.value.duration;
        final maxSeekWindow = totalDuration.inSeconds > 600 ? 180 : 90;
        final fraction = totalDelta.dx / screenSize.width;
        final deltaSec = (fraction * maxSeekWindow).toInt();

        final targetSec = (_initialSeekPosition.inSeconds + deltaSec).clamp(0, totalDuration.inSeconds);
        _targetSeekPosition = Duration(seconds: targetSec);
        _seekDeltaSeconds = targetSec - _initialSeekPosition.inSeconds;
        setState(() {
          _showGestureHud = true;
        });
        break;

      case _ActiveGesture.none:
        break;
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (!_isInitialized) return;

    if (_activeGesture == _ActiveGesture.seek) {
      _controller.seekTo(_targetSeekPosition);
    }

    _activeGesture = _ActiveGesture.none;

    _gestureHudTimer?.cancel();
    _gestureHudTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() {
          _showGestureHud = false;
        });
      }
    });
  }

  void _handleDoubleTap(TapDownDetails details, Size screenSize) {
    if (!_isInitialized) return;

    final x = details.localPosition.dx;
    final totalDuration = _controller.value.duration;
    final currentPos = _controller.value.position;

    if (x < screenSize.width * 0.35) {
      // Left side: Rewind 10 seconds
      final target = currentPos - const Duration(seconds: 10);
      _controller.seekTo(target < Duration.zero ? Duration.zero : target);
      _showDoubleTapIndicator(isForward: false);
    } else if (x > screenSize.width * 0.65) {
      // Right side: Forward 10 seconds
      final target = currentPos + const Duration(seconds: 10);
      _controller.seekTo(target > totalDuration ? totalDuration : target);
      _showDoubleTapIndicator(isForward: true);
    } else {
      // Center: Toggle Play/Pause
      _togglePlayPause();
    }
  }

  void _showDoubleTapIndicator({required bool isForward}) {
    _doubleTapTimer?.cancel();
    setState(() {
      if (isForward) {
        _showDoubleTapForward = true;
        _showDoubleTapRewind = false;
      } else {
        _showDoubleTapRewind = true;
        _showDoubleTapForward = false;
      }
    });
    _doubleTapTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() {
          _showDoubleTapForward = false;
          _showDoubleTapRewind = false;
        });
      }
    });
  }

  // --- HUD WIDGET BUILDERS ---

  Widget _buildBrightnessHud() {
    IconData icon;
    if (_currentBrightness > 0.66) {
      icon = Icons.brightness_7;
    } else if (_currentBrightness > 0.33) {
      icon = Icons.brightness_6;
    } else {
      icon = Icons.brightness_4;
    }

    final percent = (_currentBrightness * 100).toInt();

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 32),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.82),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.cyanAccent.withOpacity(0.4)),
            boxShadow: [
              BoxShadow(
                color: AppTheme.cyanAccent.withOpacity(0.2),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppTheme.cyanAccent, size: 26),
              const SizedBox(height: 10),
              Container(
                width: 6,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: 6,
                  height: 90 * _currentBrightness,
                  decoration: BoxDecoration(
                    color: AppTheme.cyanAccent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "$percent%",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVolumeHud() {
    IconData icon;
    if (_currentVolume <= 0.01) {
      icon = Icons.volume_off;
    } else if (_currentVolume < 0.5) {
      icon = Icons.volume_down;
    } else {
      icon = Icons.volume_up;
    }

    final percent = (_currentVolume * 100).toInt();

    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 32),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.82),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.purpleAccent.withOpacity(0.4)),
            boxShadow: [
              BoxShadow(
                color: AppTheme.purpleAccent.withOpacity(0.2),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppTheme.purpleAccent, size: 26),
              const SizedBox(height: 10),
              Container(
                width: 6,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: 6,
                  height: 90 * _currentVolume,
                  decoration: BoxDecoration(
                    color: AppTheme.purpleAccent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "$percent%",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeekHud() {
    final isForward = _seekDeltaSeconds >= 0;
    final totalDuration = _controller.value.duration;
    final progressFraction = totalDuration.inSeconds > 0
        ? (_targetSeekPosition.inSeconds / totalDuration.inSeconds).clamp(0.0, 1.0)
        : 0.0;

    final deltaStr = "${isForward ? '+' : '-'}${_formatDuration(Duration(seconds: _seekDeltaSeconds.abs()))}";

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isForward ? AppTheme.cyanAccent.withOpacity(0.5) : Colors.orangeAccent.withOpacity(0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: (isForward ? AppTheme.cyanAccent : Colors.orangeAccent).withOpacity(0.25),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isForward ? Icons.fast_forward : Icons.fast_rewind,
                  color: isForward ? AppTheme.cyanAccent : Colors.orangeAccent,
                  size: 26,
                ),
                const SizedBox(width: 8),
                Text(
                  "[$deltaStr]",
                  style: TextStyle(
                    color: isForward ? AppTheme.cyanAccent : Colors.orangeAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "${_formatDuration(_targetSeekPosition)} / ${_formatDuration(totalDuration)}",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: 140,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
              alignment: Alignment.centerLeft,
              child: Container(
                width: 140 * progressFraction,
                height: 4,
                decoration: BoxDecoration(
                  color: isForward ? AppTheme.cyanAccent : Colors.orangeAccent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoubleTapSkipHud({required bool isForward}) {
    return Align(
      alignment: isForward ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          right: isForward ? 48.0 : 0.0,
          left: !isForward ? 48.0 : 0.0,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.cyanAccent.withOpacity(0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isForward ? Icons.fast_forward : Icons.fast_rewind,
                color: AppTheme.cyanAccent,
                size: 28,
              ),
              const SizedBox(height: 4),
              Text(
                isForward ? "+10s" : "-10s",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _showControls = !_showControls);
              _startHideControlsTimer();
            },
            onDoubleTapDown: (details) => _handleDoubleTap(details, screenSize),
            onPanStart: (details) => _onPanStart(details, screenSize),
            onPanUpdate: (details) => _onPanUpdate(details, screenSize),
            onPanEnd: _onPanEnd,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Video Surface
                Center(
                  child: _isInitialized
                      ? AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        )
                      : _hasError
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                                const SizedBox(height: 12),
                                Text(
                                  "Could not stream '${widget.video.title}'",
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            )
                          : const CircularProgressIndicator(color: AppTheme.cyanAccent),
                ),

                // Active Gesture HUDs (Volume, Brightness, Seeking)
                if (_showGestureHud) ...[
                  if (_activeGesture == _ActiveGesture.brightness) _buildBrightnessHud(),
                  if (_activeGesture == _ActiveGesture.volume) _buildVolumeHud(),
                  if (_activeGesture == _ActiveGesture.seek) _buildSeekHud(),
                ],

                // Double Tap Skip Overlays (+10s / -10s)
                if (_showDoubleTapForward) _buildDoubleTapSkipHud(isForward: true),
                if (_showDoubleTapRewind) _buildDoubleTapSkipHud(isForward: false),

                // Standard Overlay Controls
                if (_showControls) ...[
                  // Top Bar
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.black.withOpacity(0.85), Colors.transparent],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () {
                              SystemChrome.setPreferredOrientations([
                                DeviceOrientation.portraitUp,
                              ]);
                              Navigator.pop(context);
                            },
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.video.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (widget.video.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent).withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      widget.video.resolution,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: widget.video.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    widget.video.sourceNodeName,
                                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            _isLandscape ? Icons.screen_lock_landscape : Icons.screen_rotation,
                            color: Colors.white,
                          ),
                          tooltip: "Toggle Rotation",
                          onPressed: _toggleOrientation,
                        ),
                        if (!context.watch<HypermeshProvider>().isLocalSharedMedia(widget.video.id))
                          IconButton(
                            icon: const Icon(Icons.download, color: AppTheme.cyanAccent),
                            tooltip: 'Download options',
                            onPressed: () => DownloadDestinationSheet.show(context, widget.video),
                          ),
                      ],
                    ),
                  ),
                ),

                // Center Play/Pause
                if (_isInitialized)
                  IconButton(
                    iconSize: 64,
                    icon: Icon(
                      _controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                      color: Colors.white.withOpacity(0.85),
                    ),
                    onPressed: _togglePlayPause,
                  ),

                // Bottom Scrubber Bar
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isInitialized)
                          VideoProgressIndicator(
                            _controller,
                            allowScrubbing: true,
                            colors: VideoProgressColors(
                              playedColor: widget.video.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent,
                              bufferedColor: AppTheme.border,
                              backgroundColor: AppTheme.surfaceLight,
                            ),
                          ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _isInitialized ? _formatDuration(_controller.value.position) : "0:00",
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                            ),
                            Text(
                              _isInitialized ? _formatDuration(_controller.value.duration) : widget.video.formattedDuration,
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    );
  }
}
