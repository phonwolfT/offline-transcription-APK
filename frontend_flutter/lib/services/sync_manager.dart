import 'package:flutter/foundation.dart';
import '../models/pending_sync_item.dart';
import 'sync_queue_service.dart';
import 'api_service.dart';
import 'api_service_sync_extension.dart';
import 'notion_service.dart';
import 'database_service.dart';

class SyncManager {
  static final SyncManager instance = SyncManager._internal();
  
  SyncManager._internal();

  final SyncQueueService _queueService = SyncQueueService();
  bool _isSyncing = false;
  ApiService? _apiService;
  NotionService? _notionService;
  DatabaseService? _databaseService;
  
  void init(ApiService apiService, {NotionService? notionService, DatabaseService? databaseService}) {
    _apiService = apiService;
    _notionService = notionService;
    _databaseService = databaseService;
  }

  Future<void> processPendingQueue() async {
    if (_isSyncing) return;
    
    _isSyncing = true;
    try {
      await _processAudioQueue();
      await processNotionQueue();
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _processAudioQueue() async {
    if (_apiService == null) {
      debugPrint('SyncManager: ApiService not initialized.');
      return;
    }
    final pendingItems = await _queueService.getPendingItems();
    for (final item in pendingItems) {
      if (item.retryCount >= 5) continue;
      try {
        final remoteId = await _apiService!.createMeetingRemote(item);
        if (item.audioFilePath.isNotEmpty) {
          await _apiService!.uploadAudioFile(remoteId, item.audioFilePath);
        }
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
  }

  Future<void> processNotionQueue() async {
    debugPrint('SyncManager: processNotionQueue called.');
    if (_notionService == null || _databaseService == null) {
      debugPrint('SyncManager: processNotionQueue aborted. Services are null.');
      return;
    }
    if (!_notionService!.isConfigured) {
      debugPrint('SyncManager: processNotionQueue aborted. Notion not configured.');
      return;
    }

    final pendingMeetings = _databaseService!.getPendingNotionSyncMeetings();
    debugPrint('SyncManager: Found ${pendingMeetings.length} meetings pending for Notion sync.');
    
    for (final meeting in pendingMeetings) {
      debugPrint('SyncManager: Attempting to sync meeting ${meeting.id} to Notion...');
      try {
        meeting.notionSyncStatus = 'syncing';
        await _databaseService!.updateMeeting(meeting);

        final pageId = await _notionService!.createMeetingPage(meeting);
        
        meeting.notionSynced = true;
        meeting.notionPageId = pageId;
        meeting.notionSyncStatus = 'synced';
        await _databaseService!.updateMeeting(meeting);
        debugPrint('SyncManager: Successfully synced meeting ${meeting.id} to Notion. PageID: $pageId');
      } catch (e) {
        debugPrint('SyncManager: Notion sync failed for meeting ${meeting.id}: $e');
        meeting.notionSyncStatus = 'failed';
        await _databaseService!.updateMeeting(meeting);
      }
    }
  }
}
