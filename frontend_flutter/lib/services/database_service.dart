import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/meeting.dart';
import '../models/meeting_segment.dart';

class DatabaseService extends ChangeNotifier {
  static const String _boxName = 'meetings';
  Box<Meeting>? _box;

  List<Meeting> _meetings = [];
  List<Meeting> get meetings => _meetings;

  Future<void> init() async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(MeetingAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(MeetingSegmentAdapter());
    }
    _box = await Hive.openBox<Meeting>(_boxName);
    _loadMeetings();
  }

  void _loadMeetings() {
    if (_box == null) return;
    _meetings = _box!.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
  }

  Future<void> saveMeeting(Meeting meeting) async {
    if (_box == null) return;
    await _box!.put(meeting.id, meeting);
    _loadMeetings();
  }

  Future<Meeting?> getMeeting(String id) async {
    if (_box == null) return null;
    return _box!.get(id);
  }

  Future<void> deleteMeeting(String id) async {
    if (_box == null) return;
    await _box!.delete(id);
    _loadMeetings();
  }

  Future<void> updateMeeting(Meeting meeting) async {
    if (_box == null) return;
    await _box!.put(meeting.id, meeting);
    _loadMeetings();
  }

  int get meetingCount => _meetings.length;

  List<Meeting> getPendingNotionSyncMeetings() {
    return _meetings.where((m) => 
      !m.notionSynced && 
      (m.notionSyncStatus == 'pending' || m.notionSyncStatus == 'failed') &&
      m.summary != null && 
      m.summary!.isNotEmpty
    ).toList();
  }

  Duration get totalRecordingTime {
    int totalSeconds = 0;
    for (final meeting in _meetings) {
      totalSeconds += meeting.durationSeconds;
    }
    return Duration(seconds: totalSeconds);
  }
}
