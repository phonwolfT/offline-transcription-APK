// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meeting.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MeetingAdapter extends TypeAdapter<Meeting> {
  @override
  final int typeId = 0;

  @override
  Meeting read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Meeting(
      id: fields[0] as String,
      title: fields[1] as String,
      date: fields[2] as DateTime,
      durationSeconds: fields[3] as int,
      filePath: fields[4] as String,
      transcription: fields[5] as String?,
      summary: fields[6] as String?,
      backendMeetingId: fields[7] as String?,
      segments: (fields[8] as List?)?.cast<MeetingSegment>(),
      notionSynced: fields[9] == null ? false : fields[9] as bool,
      notionPageId: fields[10] as String?,
      notionSyncStatus: fields[11] == null ? 'pending' : fields[11] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Meeting obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.date)
      ..writeByte(3)
      ..write(obj.durationSeconds)
      ..writeByte(4)
      ..write(obj.filePath)
      ..writeByte(5)
      ..write(obj.transcription)
      ..writeByte(6)
      ..write(obj.summary)
      ..writeByte(7)
      ..write(obj.backendMeetingId)
      ..writeByte(8)
      ..write(obj.segments)
      ..writeByte(9)
      ..write(obj.notionSynced)
      ..writeByte(10)
      ..write(obj.notionPageId)
      ..writeByte(11)
      ..write(obj.notionSyncStatus);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeetingAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
