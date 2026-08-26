import 'package:hive/hive.dart';
import '../models/pending_sync_item.dart';

class SyncQueueService {
  static const String boxName = 'pending_sync_box';
  
  Future<Box<PendingSyncItem>> _getBox() async {
    if (!Hive.isBoxOpen(boxName)) {
      return await Hive.openBox<PendingSyncItem>(boxName);
    }
    return Hive.box<PendingSyncItem>(boxName);
  }

  Future<void> enqueue(PendingSyncItem item) async {
    final box = await _getBox();
    await box.put(item.id, item);
  }

  Future<List<PendingSyncItem>> getPendingItems() async {
    final box = await _getBox();
    return box.values.where((item) => item.status == SyncStatus.pending || item.status == SyncStatus.failed).toList();
  }

  Future<void> markAsSynced(String id) async {
    final box = await _getBox();
    final item = box.get(id);
    if (item != null) {
      item.status = SyncStatus.synced;
      item.lastAttemptAt = DateTime.now();
      await item.save();
    }
  }

  Future<void> markAsFailed(String id) async {
    final box = await _getBox();
    final item = box.get(id);
    if (item != null) {
      item.status = SyncStatus.failed;
      item.retryCount += 1;
      item.lastAttemptAt = DateTime.now();
      await item.save();
    }
  }
}
