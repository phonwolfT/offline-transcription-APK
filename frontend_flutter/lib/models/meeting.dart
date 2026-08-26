import 'package:hive/hive.dart';
import 'meeting_segment.dart';

part 'meeting.g.dart';

@HiveType(typeId: 0)
class Meeting extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  final DateTime date;

  @HiveField(3)
  final int durationSeconds;

  @HiveField(4)
  String filePath;

  @HiveField(5)
  String? transcription;

  @HiveField(6)
  String? summary;

  @HiveField(7)
  String? backendMeetingId;

  @HiveField(8)
  List<MeetingSegment>? segments;

  Meeting({
    required this.id,
    required this.title,
    required this.date,
    required this.durationSeconds,
    required this.filePath,
    this.transcription,
    this.summary,
    this.backendMeetingId,
    this.segments,
  });

  String get durationFormatted {
    final hours = (durationSeconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((durationSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (durationSeconds % 60).toString().padLeft(2, '0');
    return "$hours:$minutes:$seconds";
  }

  String get shortDurationFormatted {
    if (durationSeconds >= 3600) {
      final hours = durationSeconds ~/ 3600;
      final minutes = (durationSeconds % 3600) ~/ 60;
      return "${hours}h ${minutes}m";
    } else {
      final minutes = durationSeconds ~/ 60;
      final seconds = durationSeconds % 60;
      return "${minutes}m ${seconds}s";
    }
  }
}
