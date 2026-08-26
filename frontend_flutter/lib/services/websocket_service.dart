import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../models/transcript_update.dart';
import 'settings_service.dart';

class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  final SettingsService _settingsService;
  
  // Stream controller for incoming transcript updates
  final _transcriptStreamController = StreamController<TranscriptUpdate>.broadcast();
  Stream<TranscriptUpdate> get transcriptStream => _transcriptStreamController.stream;

  bool get isConnected => _isConnected;

  WebSocketService(this._settingsService);

  String _getWsUrl(String backendUrl, String meetingId) {
    // Convert http:// to ws:// and https:// to wss://
    String wsUrl = backendUrl.replaceAll('http://', 'ws://').replaceAll('https://', 'wss://');
    if (wsUrl.endsWith('/')) {
      wsUrl = wsUrl.substring(0, wsUrl.length - 1);
    }
    return '$wsUrl/ws/transcribe/$meetingId';
  }

  void connect(String meetingId) {
    if (_isConnected) return;
    
    final wsUrl = _getWsUrl(_settingsService.backendUrl, meetingId);
    
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;
      notifyListeners();

      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            if (data['type'] == 'transcript_update') {
              final update = TranscriptUpdate.fromJson(data);
              _transcriptStreamController.add(update);
            } else if (data['type'] == 'error') {
              debugPrint('WebSocket error message from server: ${data['message']}');
            }
          } catch (e) {
            debugPrint('Error parsing websocket message: $e');
          }
        },
        onDone: () {
          _isConnected = false;
          notifyListeners();
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _isConnected = false;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('Failed to connect to WebSocket: $e');
      _isConnected = false;
    }
  }

  void sendAudioChunk(List<int> audioBytes) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(audioBytes);
    } else {
      debugPrint('Cannot send audio chunk: WebSocket is not connected.');
    }
  }

  void disconnect() {
    if (_isConnected && _channel != null) {
      _channel!.sink.close(status.goingAway);
      _isConnected = false;
      notifyListeners();
    }
  }
  
  @override
  void dispose() {
    disconnect();
    _transcriptStreamController.close();
    super.dispose();
  }
}
