import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../widgets/sidebar_drawer.dart';
import 'package:provider/provider.dart';
import '../services/recording_service.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';
import '../models/meeting.dart';
import '../models/pending_sync_item.dart';
import '../services/sync_queue_service.dart';
import '../services/sync_manager.dart';
import '../services/vosk_service.dart';
import 'meeting_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  String _selectedLanguage = 'es';
  AudioCaptureSource _selectedAudioSource = AudioCaptureSource.microphone;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Start preloading the Vosk model in the background immediately
    VoskService.instance.preloadModel(_selectedLanguage);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleRecording(RecordingService recordingService) async {
    if (recordingService.isRecording) {
      // If it's somehow recording, just stop it
      await recordingService.stopRecording();
    } else {
      // 1. Create a meeting immediately
      final dbService = context.read<DatabaseService>();
      final meetingId = 'meeting_${DateTime.now().millisecondsSinceEpoch}';
      final title = 'Meeting ${_formatDate(DateTime.now())}';
      
      final meeting = Meeting(
        id: meetingId,
        title: title,
        date: DateTime.now(),
        durationSeconds: 0,
        filePath: '', // No final file path yet
      );
      
      await dbService.saveMeeting(meeting);
      
      if (mounted) {
        // 2. Navigate to MeetingDetailScreen and auto-start
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MeetingDetailScreen(
              meeting: meeting, 
              autoStartRecording: true,
              initialLanguage: _selectedLanguage,
              initialAudioSource: _selectedAudioSource,
            ),
          ),
        );
      }
    }
  }

  void _showSaveMeetingDialog(RecordingService recordingService, String filePath) {
    final titleController = TextEditingController(
      text: 'Meeting ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(LucideIcons.checkCircle, color: Colors.green.shade600, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Recording Saved!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Duration: ${_formatDuration(recordingService.lastRecordDuration)}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: 'Meeting Title',
                hintText: 'Enter a name for this recording',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(LucideIcons.pencil),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              recordingService.clearLastRecording();
              Navigator.pop(context);
            },
            child: Text('Discard', style: TextStyle(color: Colors.red.shade400)),
          ),
          FilledButton.icon(
            onPressed: () async {
              final meeting = Meeting(
                id: 'meeting_${DateTime.now().millisecondsSinceEpoch}',
                title: titleController.text.isEmpty ? 'Untitled Meeting' : titleController.text,
                date: DateTime.now(),
                durationSeconds: recordingService.lastRecordDuration,
                filePath: filePath,
              );

              final dbService = context.read<DatabaseService>();
              
              await dbService.saveMeeting(meeting);
              await SyncQueueService().enqueue(PendingSyncItem.fromMeeting(meeting));
              SyncManager.instance.processPendingQueue();
              recordingService.clearLastRecording();

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(LucideIcons.checkCircle, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text('${meeting.title} saved!'),
                      ],
                    ),
                    backgroundColor: Colors.green.shade600,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    action: SnackBarAction(
                      label: 'View',
                      textColor: Colors.white,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MeetingDetailScreen(meeting: meeting),
                          ),
                        );
                      },
                    ),
                  ),
                );
              }
            },
            icon: const Icon(LucideIcons.save),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return "$h:$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    final recordingService = context.watch<RecordingService>();
    final dbService = context.watch<DatabaseService>();
    final isRecording = recordingService.isRecording;
    final isPaused = recordingService.isPaused;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meetily'),
      ),
      drawer: const SidebarDrawer(),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Waveform visualization
                if (isRecording && !isPaused) ...[
                  _buildWaveform(recordingService, isDark),
                  const SizedBox(height: 32),
                ],

                // Main recording button
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: isRecording && !isPaused ? _pulseAnimation.value : 1.0,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: isRecording
                              ? [
                                  BoxShadow(
                                    color: Colors.red.withValues(alpha: 0.4),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  )
                                ]
                              : [],
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: GestureDetector(
                    onTap: () => _toggleRecording(recordingService),
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: isRecording
                              ? [Colors.red.shade400, Colors.red.shade600]
                              : [Colors.indigo.shade400, Colors.indigo.shade600],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        isRecording ? LucideIcons.square : LucideIcons.mic,
                        size: 64,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                if (!isRecording) ...[
                  // Source and Language selectors before starting
                  Container(
                    width: 250,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey.shade800 : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedLanguage,
                        items: const [
                          DropdownMenuItem(value: 'es', child: Text('Español (ES)')),
                          DropdownMenuItem(value: 'en', child: Text('Inglés (EN-US)')),
                          DropdownMenuItem(value: 'pt', child: Text('Portugués (PT)')),
                        ],
                        onChanged: (String? newValue) {
                          if (newValue != null && newValue != _selectedLanguage) {
                            setState(() {
                              _selectedLanguage = newValue;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 320,
                    child: SegmentedButton<AudioCaptureSource>(
                      segments: const [
                        ButtonSegment(
                          value: AudioCaptureSource.microphone,
                          icon: Icon(LucideIcons.mic, size: 18),
                          label: Text('Mic', style: TextStyle(fontSize: 13)),
                        ),
                        ButtonSegment(
                          value: AudioCaptureSource.internal,
                          icon: Icon(LucideIcons.smartphone, size: 18),
                          label: Text('Dispositivo', style: TextStyle(fontSize: 13)),
                        ),
                        ButtonSegment(
                          value: AudioCaptureSource.meeting,
                          icon: Icon(LucideIcons.users, size: 18),
                          label: Text('Reunión', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                      selected: <AudioCaptureSource>{_selectedAudioSource},
                      onSelectionChanged: (Set<AudioCaptureSource> newSelection) {
                        setState(() {
                          _selectedAudioSource = newSelection.first;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Removed Pause/Resume button from home screen since we auto-navigate

                // Status text
                Text(
                  isRecording
                      ? (isPaused ? 'Paused' : 'Recording in progress...')
                      : 'Tap to start recording',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: isRecording
                            ? (isPaused ? Colors.orange : Colors.red)
                            : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                        fontWeight: FontWeight.w500,
                      ),
                ),

                // Timer
                if (isRecording) ...[
                  const SizedBox(height: 16),
                  Text(
                    recordingService.recordDurationFormatted,
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w200,
                      color: isDark ? Colors.white70 : Colors.black87,
                      letterSpacing: 4,
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

  Widget _buildWaveform(RecordingService recordingService, bool isDark) {
    final amplitudes = recordingService.amplitudeHistory;
    return SizedBox(
      height: 60,
      width: 300,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(
          30,
          (index) {
            final ampIndex = amplitudes.length - 30 + index;
            final amplitude = (ampIndex >= 0 && ampIndex < amplitudes.length)
                ? amplitudes[ampIndex]
                : 0.05;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: 4,
              height: (amplitude * 50 + 4).clamp(4.0, 54.0),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: Colors.red.shade400.withValues(alpha: 0.6 + amplitude * 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRecentMeetings(DatabaseService dbService, bool isDark) {
    final recentMeetings = dbService.meetings.take(3).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Meetings',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/history'),
                child: const Text('See all'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...recentMeetings.map((meeting) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(LucideIcons.mic, color: Colors.indigo.shade400, size: 20),
                  ),
                  title: Text(meeting.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${_formatDate(meeting.date)} • ${meeting.shortDurationFormatted}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                  trailing: const Icon(LucideIcons.chevronRight, size: 18),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MeetingDetailScreen(meeting: meeting),
                      ),
                    );
                  },
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: (isDark ? Colors.white10 : Colors.grey.shade100),
            shape: BoxShape.circle,
          ),
          child: Icon(
            LucideIcons.micOff,
            size: 48,
            color: isDark ? Colors.white24 : Colors.grey.shade400,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'No meetings yet',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white54 : Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap the button above to start\nyour first recording',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isDark ? Colors.white30 : Colors.grey.shade400,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
