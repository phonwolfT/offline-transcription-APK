import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AudioPlayerWidget extends StatefulWidget {
  final String filePath;

  const AudioPlayerWidget({super.key, required this.filePath});

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final AudioPlayer _player = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();

    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });

    _player.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });

    _player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _position = position);
    });

    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _position = Duration.zero);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _playPause() async {
    if (_playerState == PlayerState.playing) {
      await _player.pause();
    } else {
      await _player.play(DeviceFileSource(widget.filePath));
    }
  }

  Future<void> _stop() async {
    await _player.stop();
    setState(() => _position = Duration.zero);
  }

  void _seek(double value) {
    final position = Duration(milliseconds: value.toInt());
    _player.seek(position);
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(d.inHours);
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return d.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPlaying = _playerState == PlayerState.playing;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.headphones, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Audio Playback',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Seek bar
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: Colors.indigo,
                inactiveTrackColor: isDark ? Colors.white12 : Colors.grey.shade200,
                thumbColor: Colors.indigo,
              ),
              child: Slider(
                min: 0,
                max: _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                value: _position.inMilliseconds.toDouble().clamp(
                      0,
                      _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                    ),
                onChanged: _seek,
              ),
            ),
            // Time labels
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(_position),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  Text(
                    _formatDuration(_duration),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Rewind 10s
                IconButton(
                  onPressed: () {
                    final newPos = _position - const Duration(seconds: 10);
                    _player.seek(newPos > Duration.zero ? newPos : Duration.zero);
                  },
                  icon: const Icon(LucideIcons.rewind),
                  tooltip: 'Rewind 10s',
                ),
                const SizedBox(width: 8),
                // Play/Pause
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.indigo.shade400, Colors.indigo.shade600],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _playPause,
                    icon: Icon(
                      isPlaying ? LucideIcons.pause : LucideIcons.play,
                      color: Colors.white,
                    ),
                    iconSize: 28,
                  ),
                ),
                const SizedBox(width: 8),
                // Forward 10s
                IconButton(
                  onPressed: () {
                    final newPos = _position + const Duration(seconds: 10);
                    _player.seek(newPos < _duration ? newPos : _duration);
                  },
                  icon: const Icon(LucideIcons.fastForward),
                  tooltip: 'Forward 10s',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
