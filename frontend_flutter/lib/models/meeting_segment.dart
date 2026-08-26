import 'package:hive/hive.dart';

part 'meeting_segment.g.dart';

@HiveType(typeId: 3)
class MeetingSegment extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String filePath;

  @HiveField(2)
  String? transcription;

  @HiveField(3)
  String? summary;

  @HiveField(4)
  final int durationSeconds;

  MeetingSegment({
    required this.id,
    required this.filePath,
    this.transcription,
    this.summary,
    required this.durationSeconds,
  });

  String get durationFormatted {
    final hours = (durationSeconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((durationSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (durationSeconds % 60).toString().padLeft(2, '0');
    return "$hours:$minutes:$seconds";
  }
}
