import 'package:hive/hive.dart';
import 'meeting.dart';

part 'pending_sync_item.g.dart';

@HiveType(typeId: 1)
enum SyncStatus {
  @HiveField(0) pending,
  @HiveField(1) uploading,
  @HiveField(2) synced,
  @HiveField(3) failed,
}

@HiveType(typeId: 2)
class PendingSyncItem extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String meetingTitle;

  @HiveField(2)
  String language;

  @HiveField(3)
  String source;

  @HiveField(4)
  int durationSeconds;

  @HiveField(5)
  String audioFilePath;

  @HiveField(6)
  String transcriptionText;

  @HiveField(7)
  SyncStatus status;

  @HiveField(8)
  DateTime createdAt;

  @HiveField(9)
  DateTime? lastAttemptAt;

  @HiveField(10)
  int retryCount;

  PendingSyncItem({
    required this.id,
    required this.meetingTitle,
    required this.language,
    required this.source,
    required this.durationSeconds,
    required this.audioFilePath,
    required this.transcriptionText,
    this.status = SyncStatus.pending,
    required this.createdAt,
    this.lastAttemptAt,
    this.retryCount = 0,
  });

  factory PendingSyncItem.fromMeeting(Meeting meeting, {String language = 'es', String source = 'mic', String transcriptionText = ''}) {
    return PendingSyncItem(
      id: meeting.id,
      meetingTitle: meeting.title,
      language: language,
      source: source,
      durationSeconds: meeting.durationSeconds,
      audioFilePath: meeting.filePath,
      transcriptionText: transcriptionText,
      createdAt: DateTime.now(),
    );
  }
}
