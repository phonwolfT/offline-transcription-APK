import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static const String _keyBackendUrl = 'backend_url';
  static const String _keyAiProvider = 'ai_provider';
  static const String _keyAiModel = 'ai_model';
  static const String _keyApiKey = 'api_key';
  static const String _keyAudioQuality = 'audio_quality';
  static const String _keyThemeMode = 'theme_mode';

  SharedPreferences? _prefs;

  String _backendUrl = 'http://192.168.0.191:5167';
  String _aiProvider = 'ollama';
  String _aiModel = 'llama3.2';
  String _apiKey = '';
  String _audioQuality = 'medium';
  ThemeMode _themeMode = ThemeMode.system;

  String get backendUrl => _backendUrl;
  String get aiProvider => _aiProvider;
  String get aiModel => _aiModel;
  String get apiKey => _apiKey;
  String get audioQuality => _audioQuality;
  ThemeMode get themeMode => _themeMode;

  int get audioBitrate {
    switch (_audioQuality) {
      case 'low':
        return 64000;
      case 'high':
        return 256000;
      case 'medium':
      default:
        return 128000;
    }
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    String savedUrl = _prefs?.getString(_keyBackendUrl) ?? 'http://192.168.0.191:5167';
    if (savedUrl.contains('10.0.2.2')) {
      savedUrl = 'http://192.168.0.191:5167';
      await _prefs?.setString(_keyBackendUrl, savedUrl);
    }
    _backendUrl = savedUrl;
    _aiProvider = _prefs?.getString(_keyAiProvider) ?? 'ollama';
    _aiModel = _prefs?.getString(_keyAiModel) ?? 'llama3.2';
    _apiKey = _prefs?.getString(_keyApiKey) ?? '';
    _audioQuality = _prefs?.getString(_keyAudioQuality) ?? 'medium';
    
    final themeModeStr = _prefs?.getString(_keyThemeMode) ?? 'system';
    _themeMode = _themeModeFromString(themeModeStr);
    
    notifyListeners();
  }

  Future<void> setBackendUrl(String url) async {
    _backendUrl = url;
    await _prefs?.setString(_keyBackendUrl, url);
    notifyListeners();
  }

  Future<void> setAiProvider(String provider) async {
    _aiProvider = provider;
    await _prefs?.setString(_keyAiProvider, provider);
    notifyListeners();
  }

  Future<void> setAiModel(String model) async {
    _aiModel = model;
    await _prefs?.setString(_keyAiModel, model);
    notifyListeners();
  }

  Future<void> setApiKey(String key) async {
    _apiKey = key;
    await _prefs?.setString(_keyApiKey, key);
    notifyListeners();
  }

  Future<void> setAudioQuality(String quality) async {
    _audioQuality = quality;
    await _prefs?.setString(_keyAudioQuality, quality);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs?.setString(_keyThemeMode, _themeModeToString(mode));
    notifyListeners();
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
      default:
        return 'system';
    }
  }

  ThemeMode _themeModeFromString(String str) {
    switch (str) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
}
