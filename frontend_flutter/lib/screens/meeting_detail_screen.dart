import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vosk_flutter/vosk_flutter.dart';
import '../models/meeting.dart';
import '../models/meeting_segment.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/summary_view.dart';
import '../services/recording_service.dart';
import '../services/llm_service.dart';
import '../services/api_service.dart';
import '../services/vosk_service.dart';
import '../services/model_download_service.dart';
import '../widgets/summary_view.dart';
import '../services/websocket_service.dart';
import '../models/transcript_update.dart';
import '../models/pending_sync_item.dart';
import '../services/sync_manager.dart';
import '../services/sync_queue_service.dart';

class MeetingDetailScreen extends StatefulWidget {
  final Meeting meeting;
  final bool autoStartRecording;
  final String? initialLanguage;
  final AudioCaptureSource? initialAudioSource;

  const MeetingDetailScreen({
    super.key,
    required this.meeting,
    this.autoStartRecording = false,
    this.initialLanguage,
    this.initialAudioSource,
  });

  @override
  State<MeetingDetailScreen> createState() => _MeetingDetailScreenState();
}

class _MeetingDetailScreenState extends State<MeetingDetailScreen> {
  String? _liveTranscriptText;

  Map<String, dynamic>? _buildSummaryData(String? summaryText) {
    if (summaryText == null || summaryText.isEmpty) return null;
    final lines = summaryText.split('\n').where((s) => s.trim().isNotEmpty).toList();
    final blocks = lines.map((line) {
      String content = line;
      String type = 'text';
      if (line.trim().startsWith('-') || line.trim().startsWith('*')) {
        type = 'bullet';
        content = line.replaceFirst(RegExp(r'^[-*]\s*'), '');
      }
      return {'type': type, 'content': content};
    }).toList();

    final summaryTitle = _selectedLanguage == 'en'
        ? 'Local Summary (Qwen 1.5B)'
        : _selectedLanguage == 'pt'
        ? 'Resumo Local (Qwen 1.5B)'
        : 'Resumen Local (Qwen 1.5B)';

    return {
      '_section_order': ['local_summary'],
      'local_summary': {'title': summaryTitle, 'blocks': blocks},
    };
  }


  bool _isUploading = false;
  bool _isProcessing = false;
  String? _statusMessage;
  String? _partialTranscriptText;
  Timer? _transcriptPollingTimer;
  Timer? _periodicSummaryTimer;
  StreamSubscription<TranscriptUpdate>? _transcriptSubscription;

  final _vosk = VoskFlutterPlugin.instance();
  Model? _voskModel;
  Recognizer? _micRecognizer;
  Recognizer? _internalRecognizer;
  bool _isVoskInitialized = false;

  String? _lastInternalText;
  DateTime? _lastInternalTime;

  late String _selectedLanguage;
  bool _isInitializingModel = false;
  late AudioCaptureSource _selectedAudioSource;

  final List<int> _voskAudioBuffer = [];

  @override
  void initState() {
    super.initState();
    _selectedLanguage = widget.initialLanguage ?? 'es';
    _selectedAudioSource =
        widget.initialAudioSource ?? AudioCaptureSource.microphone;

    if (widget.meeting.segments == null) {
      widget.meeting.segments = [];
    }
    
    if (widget.meeting.segments!.isEmpty && (widget.meeting.transcription != null || widget.meeting.summary != null)) {
      widget.meeting.segments!.add(MeetingSegment(
        id: 'legacy_segment',
        filePath: widget.meeting.filePath,
        transcription: widget.meeting.transcription,
        summary: widget.meeting.summary,
        durationSeconds: widget.meeting.durationSeconds,
      ));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<DatabaseService>().updateMeeting(widget.meeting);
      });
    }

    // Load local transcript if it exists

    if (widget.meeting.backendMeetingId != null) {
      _fetchTranscript();
      _startTranscriptPolling();
    }

    _initVosk(_selectedLanguage);

    if (widget.autoStartRecording) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startLiveRecording();
      });
    }
  }

  Future<void> _initVosk(String lang) async {
    if (_isInitializingModel) return;

    if (mounted) {
      setState(() {
        _isInitializingModel = true;
        _isVoskInitialized = false;
      });
    }

    try {
      _micRecognizer?.dispose();
      _internalRecognizer?.dispose();
      _micRecognizer = null;
      _internalRecognizer = null;
      _voskModel = null;

      // Check if it's already preloaded in VoskService
      if (VoskService.instance.loadedLanguage == lang &&
          VoskService.instance.loadedModel != null) {
        _voskModel = VoskService.instance.loadedModel;
        debugPrint('Vosk initialized using preloaded model from VoskService.');
      } else {
        final modelPath = await ModelDownloadService.instance.getModelPath(
          lang,
        );
        if (modelPath == null) {
          debugPrint(
            'Vosk model not found for $lang. Needs to be downloaded in Settings.',
          );
          if (mounted) {
            setState(() {
              _isInitializingModel = false;
            });
          }
          return;
        }
        _voskModel = await _vosk.createModel(modelPath);
      }

      _micRecognizer = await _vosk.createRecognizer(
        model: _voskModel!,
        sampleRate: 16000,
      );
      _internalRecognizer = await _vosk.createRecognizer(
        model: _voskModel!,
        sampleRate: 16000,
      );

      if (mounted) {
        setState(() {
          _isVoskInitialized = true;
          _isInitializingModel = false;
        });
      }
    } catch (e) {
      debugPrint('Error initializing Vosk: $e');
      if (mounted) {
        setState(() {
          _isInitializingModel = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _transcriptPollingTimer?.cancel();
    _periodicSummaryTimer?.cancel();
    _transcriptSubscription?.cancel();
    _micRecognizer?.dispose();
    _internalRecognizer?.dispose();
    super.dispose();
  }

  Future<void> _startLiveRecording() async {
    final recordingService = context.read<RecordingService>();

    if (!recordingService.isRecording) {
      _periodicSummaryTimer?.cancel();
      _periodicSummaryTimer = Timer.periodic(const Duration(minutes: 30), (_) {
        // _generateLocalSummary();
      });

      await recordingService.startRecording(
        source: _selectedAudioSource,
        onAudioBytes: (List<int> bytes, AudioCaptureSource source) async {
          if (source == AudioCaptureSource.microphone) {
            // wsService.sendAudioChunk(bytes);
          }

          if (!_isVoskInitialized) {
            if (_isInitializingModel) {
              _voskAudioBuffer.addAll(bytes);
            }
            return;
          }

          try {
            final recognizer = (source == AudioCaptureSource.internal)
                ? _internalRecognizer
                : _micRecognizer;
            if (recognizer == null) return;

            Uint8List bytesToProcess;
            if (_voskAudioBuffer.isNotEmpty) {
              _voskAudioBuffer.addAll(bytes);
              bytesToProcess = Uint8List.fromList(_voskAudioBuffer);
              _voskAudioBuffer.clear();
            } else {
              bytesToProcess = Uint8List.fromList(bytes);
            }

            final isReady = await recognizer.acceptWaveformBytes(
              bytesToProcess,
            );
            if (isReady) {
              final resultStr = await recognizer.getResult();
              final map = jsonDecode(resultStr) as Map<String, dynamic>;
              String? text = map['text'] as String?;
              if (text != null && text.isNotEmpty) {
                // Basic Echo filtering
                if (source == AudioCaptureSource.microphone) {
                  if (_lastInternalText != null && _lastInternalTime != null) {
                    final diff = DateTime.now().difference(_lastInternalTime!);
                    if (diff.inSeconds < 4 &&
                        _lastInternalText!.toLowerCase() ==
                            text.toLowerCase()) {
                      debugPrint('Echo detected and filtered: $text');
                      return; // Skip this text
                    }
                  }
                } else if (source == AudioCaptureSource.internal) {
                  _lastInternalText = text;
                  _lastInternalTime = DateTime.now();
                }

                final newSegment = text;

                if (mounted) {
                  setState(() {
                    if (_liveTranscriptText == null ||
                        _liveTranscriptText!.isEmpty) {
                      _liveTranscriptText = newSegment;
                    } else {
                      _liveTranscriptText =
                          '$_liveTranscriptText\n\n$newSegment';
                    }
                    _partialTranscriptText = null;
                  });

                  context.read<DatabaseService>().updateMeeting(widget.meeting);
                }
              }
            } else {
              final partialStr = await recognizer.getPartialResult();
              final map = jsonDecode(partialStr) as Map<String, dynamic>;
              final partial = map['partial'] as String?;
              if (partial != null && partial.isNotEmpty) {
                if (mounted) {
                  setState(() {
                    if (_selectedAudioSource == AudioCaptureSource.meeting) {
                      _partialTranscriptText = partial;
                    } else {
                      _partialTranscriptText = partial;
                    }
                  });
                }
              }
            }
          } catch (e) {
            // Ignore vosk errors during processing
          }
        },
      );
    }
  }

  void _startTranscriptPolling() {
    // Disabled polling because backend does not have a get-transcript endpoint yet.
    // _transcriptPollingTimer?.cancel();
    // _transcriptPollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
    //   if (widget.meeting.backendMeetingId != null && !_isVoskInitialized) {
    //     _fetchTranscript();
    //   }
    // });
  }

  Future<void> _fetchTranscript() async {
    if (widget.meeting.backendMeetingId == null) return;
    try {
      final apiService = context.read<ApiService>();
      final text = await apiService.getTranscript(
        widget.meeting.backendMeetingId!,
      );
      if (text != null && text.isNotEmpty && mounted) {
        setState(() {
          _liveTranscriptText = text;
        });
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _uploadAndProcess() async {
    final apiService = context.read<ApiService>();

    setState(() {
      _isUploading = true;
      _statusMessage = 'Uploading audio to server...';
    });

    // Check connectivity first
    final isHealthy = await apiService.checkHealth();
    if (!isHealthy) {
      setState(() {
        _isUploading = false;
        _statusMessage =
            'Cannot reach the backend server. Check your settings.';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Cannot connect to backend server'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
      return;
    }

    // Upload audio file
    final uploadResult = await apiService.uploadAudio(
      widget.meeting.filePath,
      meetingTitle: widget.meeting.title,
    );

    if (uploadResult == null) {
      setState(() {
        _isUploading = false;
        _statusMessage = 'Failed to upload audio file.';
      });
      return;
    }

    final backendMeetingId = uploadResult['meeting_id'] as String;

    // Update local meeting with backend ID
    widget.meeting.backendMeetingId = backendMeetingId;
    final dbService = context.read<DatabaseService>();
    await dbService.updateMeeting(widget.meeting);

    setState(() {
      _isUploading = false;
      _statusMessage = 'Audio uploaded! Meeting ID: $backendMeetingId';
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Audio uploaded successfully!'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Future<void> _checkSummary() async {
    if (widget.meeting.backendMeetingId == null) return;

    final apiService = context.read<ApiService>();
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Checking summary status...';
    });

    final result = await apiService.getSummary(
      widget.meeting.backendMeetingId!,
    );
    if (result != null) {
      final status = result['status'];
      if (status == 'completed') {
        setState(() {
          // _summaryData = result['data']; // TODO support backend summary
          _statusMessage = 'Summary ready!';
          _isProcessing = false;
        });
      } else if (status == 'processing') {
        setState(() {
          _statusMessage = 'Summary is still being generated...';
          _isProcessing = false;
        });
      } else {
        setState(() {
          _statusMessage = 'Status: $status - ${result['error'] ?? 'Unknown'}';
          _isProcessing = false;
        });
      }
    } else {
      setState(() {
        _statusMessage = 'Failed to check summary status.';
        _isProcessing = false;
      });
    }
  }

  Future<void> _generateLocalSummary(MeetingSegment segment) async {
    if (segment.transcription == null || segment.transcription!.isEmpty) return;

    if (mounted) {
      setState(() {
        _isProcessing = true;
        _statusMessage = 'Generating local AI summary for segment...';
      });
    }

    final llmService = LLMService();

    // Remove timestamps like [10:23:10] before sending to the LLM
    final cleanTranscript = segment.transcription!
        .replaceAll(RegExp(r'\[\d{2}:\d{2}:\d{2}\]\s*'), '')
        .trim();

    final summaryText = await llmService.generateSummary(
      cleanTranscript,
      language: _selectedLanguage,
    );

    if (mounted) {
      setState(() {
        segment.summary = summaryText;
        _isProcessing = false;
        _statusMessage = 'Local summary ready!';
      });
      context.read<DatabaseService>().updateMeeting(widget.meeting);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recordingService = context.watch<RecordingService>();
    final fileExists = File(widget.meeting.filePath).existsSync();

    if (recordingService.isRecording || !fileExists) {
      return _buildLiveRecordingView(context);
    }

    return _buildDetailsView(context);
  }

  Widget _buildLiveRecordingView(BuildContext context) {
    final recordingService = context.watch<RecordingService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            LucideIcons.arrowLeft,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.meeting.title,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              LucideIcons.moreVertical,
              color: isDark ? Colors.white : Colors.black87,
            ),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 10),
                // Recording pill
                if (recordingService.isRecording || widget.autoStartRecording)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey.shade800 : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.red.shade400,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Recording • ${recordingService.recordDurationFormatted}',
                          style: TextStyle(
                            color: isDark
                                ? Colors.white70
                                : Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey.shade800 : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.meeting.shortDurationFormatted,
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),

                if (!_isVoskInitialized &&
                    widget.meeting.backendMeetingId == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                LucideIcons.alertTriangle,
                                color: Colors.orange,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Modelo offline no instalado',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.orange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Ve a la configuración para descargar el modelo y habilitar la transcripción sin conexión.',
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonal(
                            onPressed: () => Navigator.pushNamed(
                              context,
                              '/settings',
                            ).then((_) => _initVosk(_selectedLanguage)),
                            child: const Text('Ir a Configuración'),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Transcript ListView
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                    children: [
                      if (_liveTranscriptText != null &&
                          _liveTranscriptText!.isNotEmpty)
                        ..._buildLiveTranscriptBubbles(),

                      if (_partialTranscriptText != null &&
                          _partialTranscriptText!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Text(
                            _partialTranscriptText!,
                            style: const TextStyle(
                              fontSize: 16,
                              height: 1.5,
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),

                      const SizedBox(height: 20),
                      // Listening indicator
                      if (recordingService.isRecording)
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.blue.shade500,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Listening...',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.blue.shade500,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(
                        height: 120,
                      ), // Bottom padding for floating controls
                    ],
                  ),
                ),
              ],
            ),

            // Bottom controls
            if (recordingService.isRecording || widget.autoStartRecording)
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 24,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey.shade800 : Colors.white,
                      borderRadius: BorderRadius.circular(40),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () {
                            if (recordingService.isPaused) {
                              recordingService.resumeRecording();
                            } else {
                              recordingService.pauseRecording();
                            }
                          },
                          icon: Icon(
                            recordingService.isPaused
                                ? LucideIcons.play
                                : LucideIcons.pause,
                          ),
                          color: Colors.grey.shade600,
                          iconSize: 24,
                        ),
                        const SizedBox(width: 16),
                        InkWell(
                          onTap: _handleStopRecording,
                          borderRadius: BorderRadius.circular(30),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade500,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              LucideIcons.square,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey.shade800 : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedLanguage,
                            items: const [
                              DropdownMenuItem(
                                value: 'es',
                                child: Text('Español (ES)'),
                              ),
                              DropdownMenuItem(
                                value: 'en',
                                child: Text('Inglés (EN-US)'),
                              ),
                              DropdownMenuItem(
                                value: 'pt',
                                child: Text('Portugués (PT)'),
                              ),
                            ],
                            onChanged: (String? newValue) {
                              if (newValue != null &&
                                  newValue != _selectedLanguage) {
                                setState(() {
                                  _selectedLanguage = newValue;
                                });
                                _initVosk(newValue);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<AudioCaptureSource>(
                        segments: const [
                          ButtonSegment(
                            value: AudioCaptureSource.microphone,
                            icon: Icon(LucideIcons.mic),
                            label: Text('Micrófono'),
                          ),
                          ButtonSegment(
                            value: AudioCaptureSource.internal,
                            icon: Icon(LucideIcons.smartphone),
                            label: Text('Dispositivo'),
                          ),
                          ButtonSegment(
                            value: AudioCaptureSource.meeting,
                            icon: Icon(LucideIcons.users),
                            label: Text('Reunión'),
                          ),
                        ],
                        selected: <AudioCaptureSource>{_selectedAudioSource},
                        onSelectionChanged:
                            (Set<AudioCaptureSource> newSelection) {
                              setState(() {
                                _selectedAudioSource = newSelection.first;
                              });
                            },
                      ),
                      const SizedBox(height: 12),
                      if (_isInitializingModel)
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        FilledButton.icon(
                          onPressed: () {
                            _startLiveRecording();
                          },
                          icon: const Icon(LucideIcons.mic),
                          label: const Text('Start Recording'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 32,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLiveTranscriptBubbles() {
    if (_liveTranscriptText == null) return [];

    final chunks = _liveTranscriptText!
        .split('\n\n')
        .where((s) => s.trim().isNotEmpty)
        .toList();

    return chunks.map((chunk) {
      final timestampRegex = RegExp(r'^\[(\d{2}:\d{2}:\d{2})\]\s*(.*)');
      final match = timestampRegex.firstMatch(chunk.trim());

      String timestamp = '';
      String text = chunk.trim();

      if (match != null) {
        timestamp = '[${match.group(1)}]';
        text = match.group(2) ?? '';
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (timestamp.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 16),
                child: Text(
                  timestamp,
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildDetailsView(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fileExists = File(widget.meeting.filePath).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.meeting.title),
        actions: [
          PopupMenuButton(
            icon: const Icon(LucideIcons.moreVertical),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(LucideIcons.pencil, size: 18),
                    SizedBox(width: 8),
                    Text('Rename'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(LucideIcons.trash2, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'delete') {
                _confirmDelete();
              } else if (value == 'rename') {
                _showRenameDialog();
              }
            },
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: (widget.meeting.segments?.length ?? 0) + 1,
        itemBuilder: (context, index) {
          if (index == (widget.meeting.segments?.length ?? 0)) {
            // "Continue Recording" button at the bottom
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: FilledButton.icon(
                onPressed: () {
                  _startLiveRecording();
                },
                icon: const Icon(LucideIcons.mic),
                label: const Text('Continue Recording'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            );
          }

          final segment = widget.meeting.segments![index];
          final summaryMap = _buildSummaryData(segment.summary);

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Session ${index + 1}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Duration: ${segment.durationFormatted}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                  const Divider(height: 32),

                  if (summaryMap != null) ...[
                    SummaryView(data: summaryMap),
                    const Divider(height: 32),
                  ],

                  if (segment.transcription != null &&
                      segment.transcription!.isNotEmpty) ...[
                    const Text(
                      'Transcript',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._buildSegmentTranscriptBubbles(segment.transcription!),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildSegmentTranscriptBubbles(String transcriptText) {
    if (transcriptText.isEmpty) return [];

    // Split by double newline to get chunks
    final chunks = transcriptText
        .split('\n\n')
        .where((s) => s.trim().isNotEmpty)
        .toList();

    return chunks.map((chunk) {
      // Check if chunk starts with [MM:SS]
      final timestampRegex = RegExp(r'^\[(\d{2}:\d{2})\]\s*(.*)');
      final match = timestampRegex.firstMatch(chunk.trim());

      String timestamp = '';
      String text = chunk.trim();

      if (match != null) {
        timestamp = '[${match.group(1)}]';
        text = match.group(2) ?? '';
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (timestamp.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 12),
                child: Text(
                  timestamp,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildBottomControls() {
    final recordingService = context.watch<RecordingService>();
    final isRecording = recordingService.isRecording;

    if (!isRecording) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: FilledButton.icon(
            onPressed: () {
              _startLiveRecording();
            },
            icon: const Icon(LucideIcons.mic),
            label: const Text('Continue Recording'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16.0),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () {
                if (recordingService.isPaused) {
                  recordingService.resumeRecording();
                } else {
                  recordingService.pauseRecording();
                }
              },
              icon: Icon(
                recordingService.isPaused
                    ? LucideIcons.play
                    : LucideIcons.pause,
              ),
              color: Colors.grey.shade700,
              iconSize: 28,
            ),
            const SizedBox(width: 16),
            InkWell(
              onTap: _handleStopRecording,
              borderRadius: BorderRadius.circular(30),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.square,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      recordingService.recordDurationFormatted,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleStopRecording() async {
    final recordingService = context.read<RecordingService>();
    final path = await recordingService.stopRecording();
    _periodicSummaryTimer?.cancel();

    if (_isVoskInitialized) {
      try {
        final recognizers = [
          _micRecognizer,
          _internalRecognizer,
        ].whereType<Recognizer>();
        for (final recognizer in recognizers) {
          final finalResultStr = await recognizer.getResult();
          final map = jsonDecode(finalResultStr) as Map<String, dynamic>;
          final text = map['text'] as String?;
          if (text != null && text.isNotEmpty) {
            final newSegment = text;

            if (mounted) {
              setState(() {
                if (_liveTranscriptText == null ||
                    _liveTranscriptText!.isEmpty) {
                  _liveTranscriptText = newSegment;
                } else {
                  _liveTranscriptText = '$_liveTranscriptText\n\n$newSegment';
                }
                _partialTranscriptText = null;
              });

              await context.read<DatabaseService>().updateMeeting(
                widget.meeting,
              );
            }
          }
        }
      } catch (e) {
        // Ignore
      }
    }

    if (path != null) {
      final newSegment = MeetingSegment(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        filePath: path,
        transcription: _liveTranscriptText,
        durationSeconds: recordingService.lastRecordDuration,
      );

      setState(() {
        widget.meeting.segments ??= [];
        widget.meeting.segments!.add(newSegment);
        _liveTranscriptText = null; // Reset for next session
      });
      
      await context.read<DatabaseService>().updateMeeting(widget.meeting);

      // We still update the meeting's main filePath for backward compatibility
      // with SyncQueueService, which currently expects one file per meeting.
      // But we can also just let it sync the last segment for now.
      widget.meeting.filePath = path;

      // Enqueue to SyncQueueService for background upload
      await SyncQueueService().enqueue(
        PendingSyncItem.fromMeeting(widget.meeting),
      );
      SyncManager.instance.processPendingQueue();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Audio guardado. Generando resumen...'),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // Generate summary for the new segment
      if (newSegment.transcription != null && newSegment.transcription!.length > 10) {
        _generateLocalSummary(newSegment);
      }
    }
  }

  Future<void> _appendRecording(
    String filePath, {
    bool isChunk = false,
    int? elapsedSeconds,
  }) async {
    final apiService = context.read<ApiService>();

    if (mounted) {
      setState(() {
        _isUploading = true;
        if (!isChunk) {
          _statusMessage = 'Appending audio...';
        }
      });
    }

    final isHealthy = await apiService.checkHealth();
    if (!isHealthy) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _statusMessage = 'Cannot reach backend server (Timeout).';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Cannot connect to backend server. Check Wi-Fi.',
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final uploadResult = await apiService.uploadAudio(
      filePath,
      meetingTitle: widget.meeting.title,
      meetingId: widget.meeting.backendMeetingId,
      elapsedSeconds: elapsedSeconds,
    );

    if (uploadResult == null) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _statusMessage = 'Failed to append audio.';
        });
      }
      return;
    }

    if (widget.meeting.backendMeetingId == null) {
      widget.meeting.backendMeetingId = uploadResult['meeting_id'];
      await context.read<DatabaseService>().updateMeeting(widget.meeting);
      _startTranscriptPolling();
    }

    if (!isChunk) {
      setState(() {
        _isUploading = false;
        _statusMessage = 'Audio appended! Processing transcription...';
      });
    } else {
      // Chunk silently uploads
      File(
        filePath,
      ).delete().catchError((_) {}); // Delete local chunk file after upload
      _statusMessage = 'Chunk uploaded. Processing...';
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Meeting?'),
        content: const Text(
          'This will permanently delete this meeting and its recording.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final dbService = context.read<DatabaseService>();
              await dbService.deleteMeeting(widget.meeting.id);
              if (mounted) {
                Navigator.pop(ctx);
                Navigator.pop(context);
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog() {
    final controller = TextEditingController(text: widget.meeting.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Rename Meeting'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            labelText: 'Meeting Title',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                widget.meeting.title = controller.text;
                final dbService = context.read<DatabaseService>();
                await dbService.updateMeeting(widget.meeting);
                if (mounted) {
                  Navigator.pop(ctx);
                  setState(() {});
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = date.hour > 12 ? date.hour - 12 : date.hour;
    final amPm = date.hour >= 12 ? 'PM' : 'AM';
    return '${months[date.month - 1]} ${date.day}, ${date.year} at $hour:${date.minute.toString().padLeft(2, '0')} $amPm';
  }
}
