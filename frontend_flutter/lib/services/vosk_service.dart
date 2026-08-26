import 'package:flutter/foundation.dart';
import 'package:vosk_flutter/vosk_flutter.dart';
import 'model_download_service.dart';

class VoskService extends ChangeNotifier {
  static final VoskService instance = VoskService._internal();
  
  VoskService._internal();

  final _vosk = VoskFlutterPlugin.instance();
  Model? _loadedModel;
  String? _loadedLanguage;
  bool _isPreloading = false;

  Model? get loadedModel => _loadedModel;
  String? get loadedLanguage => _loadedLanguage;
  bool get isPreloading => _isPreloading;

  /// Preloads the model for the given language into memory.
  /// If it's already loaded or currently loading, it does nothing or waits.
  Future<void> preloadModel(String language) async {
    if (_loadedLanguage == language && _loadedModel != null) {
      return; // Already loaded
    }
    if (_isPreloading) {
      return; // Already preloading (could be the same or different language, keep simple for now)
    }

    _isPreloading = true;
    notifyListeners();

    try {
      final modelPath = await ModelDownloadService.instance.getModelPath(language);
      if (modelPath == null) {
        debugPrint('VoskService: Model not found for $language, cannot preload.');
        _isPreloading = false;
        notifyListeners();
        return;
      }

      // Load into memory
      final model = await _vosk.createModel(modelPath);
      
      _loadedModel = model;
      _loadedLanguage = language;
      debugPrint('VoskService: Successfully preloaded model for $language.');
    } catch (e) {
      debugPrint('VoskService: Error preloading Vosk model: $e');
      _loadedModel = null;
      _loadedLanguage = null;
    } finally {
      _isPreloading = false;
      notifyListeners();
    }
  }

  /// Clears the currently loaded model from memory
  void unloadModel() {
    _loadedModel = null;
    _loadedLanguage = null;
    notifyListeners();
  }
}
