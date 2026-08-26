// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pending_sync_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PendingSyncItemAdapter extends TypeAdapter<PendingSyncItem> {
  @override
  final int typeId = 2;

  @override
  PendingSyncItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PendingSyncItem(
      id: fields[0] as String,
      meetingTitle: fields[1] as String,
      language: fields[2] as String,
      source: fields[3] as String,
      durationSeconds: fields[4] as int,
      audioFilePath: fields[5] as String,
      transcriptionText: fields[6] as String,
      status: fields[7] as SyncStatus,
      createdAt: fields[8] as DateTime,
      lastAttemptAt: fields[9] as DateTime?,
      retryCount: fields[10] as int,
    );
  }

  @override
  void write(BinaryWriter writer, PendingSyncItem obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.meetingTitle)
      ..writeByte(2)
      ..write(obj.language)
      ..writeByte(3)
      ..write(obj.source)
      ..writeByte(4)
      ..write(obj.durationSeconds)
      ..writeByte(5)
      ..write(obj.audioFilePath)
      ..writeByte(6)
      ..write(obj.transcriptionText)
      ..writeByte(7)
      ..write(obj.status)
      ..writeByte(8)
      ..write(obj.createdAt)
      ..writeByte(9)
      ..write(obj.lastAttemptAt)
      ..writeByte(10)
      ..write(obj.retryCount);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingSyncItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SyncStatusAdapter extends TypeAdapter<SyncStatus> {
  @override
  final int typeId = 1;

  @override
  SyncStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return SyncStatus.pending;
      case 1:
        return SyncStatus.uploading;
      case 2:
        return SyncStatus.synced;
      case 3:
        return SyncStatus.failed;
      default:
        return SyncStatus.pending;
    }
  }

  @override
  void write(BinaryWriter writer, SyncStatus obj) {
    switch (obj) {
      case SyncStatus.pending:
        writer.writeByte(0);
        break;
      case SyncStatus.uploading:
        writer.writeByte(1);
        break;
      case SyncStatus.synced:
        writer.writeByte(2);
        break;
      case SyncStatus.failed:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
