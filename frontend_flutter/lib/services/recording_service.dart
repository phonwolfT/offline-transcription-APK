import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

enum AudioCaptureSource { microphone, internal, meeting }

class RecordingService extends ChangeNotifier {
  final AudioRecorder _record = AudioRecorder();
  
  bool _isRecording = false;
  bool get isRecording => _isRecording;

  AudioCaptureSource _currentSource = AudioCaptureSource.microphone;
  AudioCaptureSource get currentSource => _currentSource;

  static const MethodChannel _methodChannel = MethodChannel('com.example.meetily/internal_audio');
  static const EventChannel _eventChannel = EventChannel('com.example.meetily/internal_audio_stream');
  StreamSubscription<dynamic>? _internalAudioSubscription;

  bool _isPaused = false;
  bool get isPaused => _isPaused;

  String? _recordingPath;
  String? get recordingPath => _recordingPath;

  String? _lastRecordingPath;
  String? get lastRecordingPath => _lastRecordingPath;

  DateTime? _recordingStartTime;
  DateTime? get recordingStartTime => _recordingStartTime;

  // Timer logic
  Timer? _timer;
  Function(List<int> bytes, AudioCaptureSource source)? _onAudioBytes;
  StreamSubscription<Uint8List>? _audioStreamSubscription;
  File? _audioFile;
  IOSink? _audioFileSink;
  int _audioDataLength = 0;
  
  int _recordDuration = 0;
  int _lastRecordDuration = 0;
  int get lastRecordDuration => _lastRecordDuration;

  String get recordDurationFormatted {
    final String hours = (_recordDuration ~/ 3600).toString().padLeft(2, '0');
    final String minutes = ((_recordDuration % 3600) ~/ 60).toString().padLeft(2, '0');
    final String seconds = (_recordDuration % 60).toString().padLeft(2, '0');
    return "$hours:$minutes:$seconds";
  }

  // Amplitude for waveform
  double _currentAmplitude = 0.0;
  double get currentAmplitude => _currentAmplitude;
  Timer? _amplitudeTimer;
  final List<double> _amplitudeHistory = [];
  List<double> get amplitudeHistory => _amplitudeHistory;

  Future<void> startRecording({
    Function(List<int> bytes, AudioCaptureSource source)? onAudioBytes,
    AudioCaptureSource source = AudioCaptureSource.microphone,
  }) async {
    try {
      _currentSource = source;
      _onAudioBytes = onAudioBytes ?? _onAudioBytes;
      
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'meetily_recording_${DateTime.now().millisecondsSinceEpoch}.wav';
      _recordingPath = '${directory.path}/$fileName';
      
      _audioFile = File(_recordingPath!);
      _audioFileSink = _audioFile!.openWrite();
      _audioDataLength = 0;
      
      // Write placeholder WAV header (44 bytes)
      _audioFileSink!.add(Uint8List(44));

      if (source == AudioCaptureSource.microphone || source == AudioCaptureSource.meeting) {
        if (await _record.hasPermission()) {
          final stream = await _record.startStream(
            const RecordConfig(
              encoder: AudioEncoder.pcm16bits,
              sampleRate: 16000,
              numChannels: 1,
            ),
          );

          _audioStreamSubscription = stream.listen((data) {
            if (!_isPaused) {
              // We'll save the mic audio as the main file recording
              _audioFileSink?.add(data);
              _audioDataLength += data.length;
              if (_onAudioBytes != null) _onAudioBytes!(data, AudioCaptureSource.microphone);
            }
          });
        } else {
          var status = await Permission.microphone.request();
          if (status.isGranted) {
             startRecording(onAudioBytes: onAudioBytes, source: source);
          }
          return;
        }
      } 
      
      if (source == AudioCaptureSource.internal || source == AudioCaptureSource.meeting) {
        // Internal audio via MethodChannel
        try {
          final bool isSupported = await _methodChannel.invokeMethod('isInternalCaptureSupported') ?? false;
          if (!isSupported) {
            if (kDebugMode) print('Internal capture not supported on this Android version.');
            if (source == AudioCaptureSource.internal) return;
          } else {
            await _methodChannel.invokeMethod('startInternalRecording');
            
            _internalAudioSubscription = _eventChannel.receiveBroadcastStream().listen((data) {
               if (!_isPaused && data is Uint8List) {
                 if (source != AudioCaptureSource.meeting) {
                   _audioFileSink?.add(data);
                   _audioDataLength += data.length;
                 }
                 if (_onAudioBytes != null) _onAudioBytes!(data.toList(), AudioCaptureSource.internal);
               }
            }, onError: (error) {
               if (kDebugMode) print('Internal audio error: $error');
               if (source == AudioCaptureSource.internal) stopRecording();
            });
          }
        } catch (e) {
          if (kDebugMode) print('Failed to start internal recording: $e');
          if (source == AudioCaptureSource.internal) return;
        }
      }

      _isRecording = true;
      _isPaused = false;
      
      _recordingStartTime = DateTime.now();
      _amplitudeHistory.clear();
      _recordDuration = 0;
      _startTimer();
      if (source == AudioCaptureSource.microphone) {
        _startAmplitudeMonitor();
      }
      
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error starting recording: $e');
      }
    }
  }

  Future<void> pauseRecording() async {
    try {
      await _record.pause();
      _isPaused = true;
      _timer?.cancel();
      _amplitudeTimer?.cancel();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error pausing recording: $e');
      }
    }
  }

  Future<void> resumeRecording() async {
    try {
      await _record.resume();
      _isPaused = false;
      _startTimer();
      _startAmplitudeMonitor();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error resuming recording: $e');
      }
    }
  }

  Future<String?> stopRecording() async {
    try {
      if (_currentSource == AudioCaptureSource.microphone || _currentSource == AudioCaptureSource.meeting) {
        await _audioStreamSubscription?.cancel();
        await _record.stop();
      } 
      if (_currentSource == AudioCaptureSource.internal || _currentSource == AudioCaptureSource.meeting) {
        await _internalAudioSubscription?.cancel();
        await _methodChannel.invokeMethod('stopInternalRecording');
      }
      
      _isRecording = false;
      _isPaused = false;
      _timer?.cancel();
      _amplitudeTimer?.cancel();
      _lastRecordDuration = _recordDuration;
      _recordDuration = 0;
      _currentAmplitude = 0.0;
      
      if (_audioFile != null && _audioFileSink != null) {
        await _audioFileSink!.close();
        
        // Open file for random access to write real WAV header
        final raf = await _audioFile!.open(mode: FileMode.append);
        await raf.setPosition(0);
        await raf.writeFrom(_buildWavHeader(_audioDataLength));
        await raf.close();
        
        _lastRecordingPath = _audioFile!.path;
        _recordingPath = _audioFile!.path;
        if (kDebugMode) {
          print('Recording stopped and saved to: $_lastRecordingPath');
        }
      }
      notifyListeners();
      return _lastRecordingPath;
    } catch (e) {
      if (kDebugMode) {
        print('Error stopping recording: $e');
      }
      return null;
    }
  }

  Uint8List _buildWavHeader(int dataLength) {
    final channels = 1;
    final sampleRate = 16000;
    final byteRate = 16000 * channels * 2;
    
    final header = ByteData(44);
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, 36 + dataLength, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); //  
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, channels * 2, Endian.little);
    header.setUint16(34, 16, Endian.little); // 16 bits
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataLength, Endian.little);
    
    return header.buffer.asUint8List();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      _recordDuration++;
      notifyListeners();
    });
  }



  void _startAmplitudeMonitor() {
    _amplitudeTimer?.cancel();
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) async {
      try {
        final amplitude = await _record.getAmplitude();
        // Normalize dB value to 0-1 range (-60dB to 0dB)
        final normalizedAmplitude = ((amplitude.current + 60) / 60).clamp(0.0, 1.0);
        _currentAmplitude = normalizedAmplitude;
        _amplitudeHistory.add(normalizedAmplitude);
        if (_amplitudeHistory.length > 50) {
          _amplitudeHistory.removeAt(0);
        }
        notifyListeners();
      } catch (e) {
        // Amplitude may not be available on all platforms
      }
    });
  }

  void clearLastRecording() {
    _lastRecordingPath = null;
    _lastRecordDuration = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioStreamSubscription?.cancel();
    _amplitudeTimer?.cancel();
    _record.dispose();
    super.dispose();
  }
}
