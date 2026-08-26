import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class ApiService extends ChangeNotifier {
  String _baseUrl = 'http://192.168.0.191:5167';
  bool _isConnected = false;

  String get baseUrl => _baseUrl;
  bool get isConnected => _isConnected;

  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    notifyListeners();
  }

  /// Check if the backend is reachable
  Future<bool> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      _isConnected = response.statusCode == 200;
      notifyListeners();
      return _isConnected;
    } catch (e) {
      _isConnected = false;
      notifyListeners();
      if (kDebugMode) {
        print('Backend health check failed: $e');
      }
      return false;
    }
  }

  /// Upload audio file to the backend
  Future<Map<String, dynamic>?> uploadAudio(String filePath, {String? meetingTitle, String? meetingId, int? elapsedSeconds}) async {
    try {
      final String url = '$_baseUrl/api/meetings/upload-audio/';
      final uri = Uri.parse(url);
      final request = http.MultipartRequest('POST', uri);

      request.files.add(await http.MultipartFile.fromPath(
        'audio_file',
        filePath,
        filename: p.basename(filePath),
      ));

      if (meetingTitle != null) {
        request.fields['meeting_title'] = meetingTitle;
      }
      
      if (meetingId != null) {
        request.fields['meeting_id'] = meetingId;
      }
      
      if (elapsedSeconds != null) {
        request.fields['elapsed_seconds'] = elapsedSeconds.toString();
      }

      final streamedResponse = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        if (kDebugMode) {
          print('Upload failed: ${response.statusCode} - ${response.body}');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error uploading audio: $e');
      }
      return null;
    }
  }

  /// Request transcription processing for a meeting
  Future<Map<String, dynamic>?> requestTranscription({
    required String meetingId,
    required String text,
    String model = 'ollama',
    String modelName = 'llama3.2',
    String? customPrompt,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/process-transcript'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'meeting_id': meetingId,
              'text': text,
              'model': model,
              'model_name': modelName,
              'custom_prompt': customPrompt ?? 'Generate a summary of the meeting transcript.',
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error requesting transcription: $e');
      }
      return null;
    }
  }

  /// Get the transcript text for a meeting
  Future<String?> getTranscript(String meetingId) async {
    try {
      final uri = Uri.parse('$_baseUrl/get-transcript/$meetingId');
      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          return data['text'];
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting transcript: $e');
      }
      return null;
    }
  }

  /// Get the summary for a meeting
  Future<Map<String, dynamic>?> getSummary(String meetingId) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/get-summary/$meetingId'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 202 || response.statusCode == 400) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting summary: $e');
      }
      return null;
    }
  }

  /// Get all meetings from the backend
  Future<List<Map<String, dynamic>>> getMeetings() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/get-meetings'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      if (kDebugMode) {
        print('Error getting meetings: $e');
      }
      return [];
    }
  }

  /// Save model configuration
  Future<bool> saveModelConfig({
    required String provider,
    required String model,
    required String whisperModel,
    String? apiKey,
  }) async {
    try {
      final body = {
        'provider': provider,
        'model': model,
        'whisperModel': whisperModel,
      };
      if (apiKey != null) body['apiKey'] = apiKey;

      final response = await http
          .post(
            Uri.parse('$_baseUrl/save-model-config'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print('Error saving model config: $e');
      }
      return false;
    }
  }

  /// Get model configuration
  Future<Map<String, dynamic>?> getModelConfig() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/get-model-config'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting model config: $e');
      }
      return null;
    }
  }

  /// Delete a meeting from the backend
  Future<bool> deleteMeeting(String meetingId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/delete-meeting'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'meeting_id': meetingId}),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting meeting: $e');
      }
      return false;
    }
  }
  // ==========================================
  // Search
  // ==========================================
  Future<List<Map<String, dynamic>>> searchTranscripts(String query) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/search-transcripts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': query}),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      debugPrint('Error searching transcripts: $e');
      return [];
    }
  }
  // Model Management
  // ==========================================
  Future<Map<String, dynamic>?> getAvailableModels() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/models/available'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting models: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> downloadModel(String modelName) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/models/download'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'model_name': modelName}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Error downloading model: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> loadModel(String modelName) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/models/load'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'model_name': modelName}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Error loading model: $e');
      return null;
    }
  }
}
