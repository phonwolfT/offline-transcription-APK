// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meeting_segment.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MeetingSegmentAdapter extends TypeAdapter<MeetingSegment> {
  @override
  final int typeId = 3;

  @override
  MeetingSegment read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MeetingSegment(
      id: fields[0] as String,
      filePath: fields[1] as String,
      transcription: fields[2] as String?,
      summary: fields[3] as String?,
      durationSeconds: fields[4] as int,
    );
  }

  @override
  void write(BinaryWriter writer, MeetingSegment obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.filePath)
      ..writeByte(2)
      ..write(obj.transcription)
      ..writeByte(3)
      ..write(obj.summary)
      ..writeByte(4)
      ..write(obj.durationSeconds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeetingSegmentAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
