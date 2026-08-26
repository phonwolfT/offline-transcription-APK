import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'api_service.dart';
import '../models/pending_sync_item.dart';

class SyncException implements Exception {
  final String message;
  SyncException(this.message);
  @override
  String toString() => 'SyncException: $message';
}

extension ApiServiceSyncExtension on ApiService {
  Future<String> createMeetingRemote(PendingSyncItem item) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/meetings/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': item.meetingTitle,
          'language': item.language,
          'source': item.source,
          'duration_seconds': item.durationSeconds,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['id'].toString(); // Asumiendo que el backend retorna el ID creado
      } else {
        throw SyncException('Failed to create meeting. Status: ${response.statusCode}');
      }
    } catch (e) {
      if (e is SyncException) rethrow;
      throw SyncException('Network error during createMeetingRemote: $e');
    }
  }

  Future<void> uploadAudioFile(String remoteId, String localFilePath) async {
    try {
      final uri = Uri.parse('$baseUrl/api/meetings/$remoteId/upload-audio/');
      final request = http.MultipartRequest('POST', uri);

      request.files.add(await http.MultipartFile.fromPath(
        'audio_file',
        localFilePath,
        filename: p.basename(localFilePath),
      ));

      final streamedResponse = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw SyncException('Failed to upload audio. Status: ${response.statusCode}');
      }
    } catch (e) {
      if (e is SyncException) rethrow;
      throw SyncException('Network error during uploadAudioFile: $e');
    }
  }

  Future<void> sendTranscriptionText(String remoteId, String text) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/meetings/$remoteId/transcription/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'text': text,
          'engine': 'vosk_offline',
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw SyncException('Failed to send transcription. Status: ${response.statusCode}');
      }
    } catch (e) {
      if (e is SyncException) rethrow;
      throw SyncException('Network error during sendTranscriptionText: $e');
    }
  }
}
