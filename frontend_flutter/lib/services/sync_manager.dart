import 'package:flutter/foundation.dart';
import '../models/pending_sync_item.dart';
import 'sync_queue_service.dart';
import 'api_service.dart';
import 'api_service_sync_extension.dart';

class SyncManager {
  static final SyncManager instance = SyncManager._internal();
  
  SyncManager._internal();

  final SyncQueueService _queueService = SyncQueueService();
  bool _isSyncing = false;
  ApiService? _apiService;
  
  void init(ApiService apiService) {
    _apiService = apiService;
  }

  Future<void> processPendingQueue() async {
    if (_isSyncing) return;
    if (_apiService == null) {
      debugPrint('SyncManager: ApiService not initialized.');
      return;
    }
    
    _isSyncing = true;
    try {
      final pendingItems = await _queueService.getPendingItems();
      
      for (final item in pendingItems) {
        if (item.retryCount >= 5) continue; // Max retries reached

        try {
          // 1. Create meeting metadata
          final remoteId = await _apiService!.createMeetingRemote(item);
          
          // 2. Upload audio
          if (item.audioFilePath.isNotEmpty) {
            await _apiService!.uploadAudioFile(remoteId, item.audioFilePath);
          }
          
          // 3. Send transcription
          if (item.transcriptionText.isNotEmpty) {
            await _apiService!.sendTranscriptionText(remoteId, item.transcriptionText);
          }
          
          await _queueService.markAsSynced(item.id);
        } on SyncException catch (e) {
          debugPrint('SyncManager: Sync failed for item ${item.id}: ${e.message}');
          await _queueService.markAsFailed(item.id);
        } catch (e) {
          debugPrint('SyncManager: Unexpected error for item ${item.id}: $e');
          await _queueService.markAsFailed(item.id);
        }
      }
    } finally {
      _isSyncing = false;
    }
  }
}
