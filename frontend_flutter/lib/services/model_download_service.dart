import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

// Top-level function for isolate
void _extractZip(List<String> args) {
  final zipPath = args[0];
  final destPath = args[1];
  extractFileToDisk(zipPath, destPath);
}

class VoskModelConfig {
  final String url;
  final String folderName;
  final int totalBytesApprox;

  const VoskModelConfig({
    required this.url,
    required this.folderName,
    required this.totalBytesApprox,
  });
}

class ModelDownloadService extends ChangeNotifier {
  static const Map<String, VoskModelConfig> supportedModels = {
    'es': VoskModelConfig(
      url: 'https://alphacephei.com/vosk/models/vosk-model-es-0.42.zip',
      folderName: 'vosk-model-es-0.42',
      totalBytesApprox: 1480000000,
    ),
    'en': VoskModelConfig(
      url: 'https://alphacephei.com/vosk/models/vosk-model-en-us-0.22.zip',
      folderName: 'vosk-model-en-us-0.22',
      totalBytesApprox: 1800000000,
    ),
    'pt': VoskModelConfig(
      url: 'https://alphacephei.com/vosk/models/vosk-model-pt-fb-v0.1.1-20220516_2113.zip',
      folderName: 'vosk-model-pt-fb-v0.1.1-20220516_2113',
      totalBytesApprox: 1400000000,
    ),
  };

  final Map<String, bool> _isDownloading = {};
  final Map<String, bool> _isPaused = {};
  final Map<String, bool> _isExtracting = {};
  final Map<String, double> _downloadProgress = {};
  final Map<String, bool> _isModelReady = {};
  final Map<String, String?> _errorMessage = {};
  final Map<String, CancelToken> _cancelTokens = {};

  bool isDownloading(String lang) => _isDownloading[lang] ?? false;
  bool isPaused(String lang) => _isPaused[lang] ?? false;
  bool isExtracting(String lang) => _isExtracting[lang] ?? false;
  double downloadProgress(String lang) => _downloadProgress[lang] ?? 0.0;
  bool isModelReady(String lang) => _isModelReady[lang] ?? false;
  String? errorMessage(String lang) => _errorMessage[lang];

  static final ModelDownloadService instance = ModelDownloadService._internal();

  ModelDownloadService._internal() {
    _checkAllReady();
  }

  Future<void> _checkAllReady() async {
    final appDir = await getApplicationDocumentsDirectory();
    for (final lang in supportedModels.keys) {
      final config = supportedModels[lang]!;
      final modelDir = Directory('${appDir.path}/${config.folderName}');
      if (await modelDir.exists()) {
        _isModelReady[lang] = true;
      } else {
        _isModelReady[lang] = false;
      }
    }
    notifyListeners();
  }

  Future<String?> getModelPath(String lang) async {
    final config = supportedModels[lang];
    if (config == null) return null;

    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDir.path}/${config.folderName}');
    
    if (await modelDir.exists()) {
      // FIX para celulares: Eliminar la carpeta 'rescore' y 'rnnlm' si existen.
      final rescoreDir = Directory('${modelDir.path}/rescore');
      if (await rescoreDir.exists()) {
        try { await rescoreDir.delete(recursive: true); } catch (e) { debugPrint('Error deleting rescore: $e'); }
      }
      final rnnlmDir = Directory('${modelDir.path}/rnnlm');
      if (await rnnlmDir.exists()) {
        try { await rnnlmDir.delete(recursive: true); } catch (e) { debugPrint('Error deleting rnnlm: $e'); }
      }
      
      return modelDir.path;
    }
    return null;
  }

  Future<void> deleteModel(String lang) async {
    final path = await getModelPath(lang);
    final config = supportedModels[lang];
    if (path != null && config != null) {
      final dir = Directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        _isModelReady[lang] = false;
        
        final appDir = await getApplicationDocumentsDirectory();
        final zipFile = File('${appDir.path}/${config.folderName}.zip');
        if (await zipFile.exists()) {
          await zipFile.delete();
        }
        
        _downloadProgress[lang] = 0.0;
        _isPaused[lang] = false;
        _errorMessage[lang] = null;
        notifyListeners();
      }
    }
  }

  void pauseDownload(String lang) {
    if (isDownloading(lang)) {
      _cancelTokens[lang]?.cancel('Pausado por el usuario');
      _isPaused[lang] = true;
      _isDownloading[lang] = false;
      notifyListeners();
    }
  }

  void resumeDownload(String lang) {
    if (isPaused(lang) || errorMessage(lang) != null) {
      downloadAndExtractModel(lang);
    }
  }

  Future<void> downloadAndExtractModel(String lang) async {
    if (isDownloading(lang) || isExtracting(lang) || isModelReady(lang)) return;

    final config = supportedModels[lang];
    if (config == null) return;

    try {
      _isDownloading[lang] = true;
      _isPaused[lang] = false;
      _errorMessage[lang] = null;
      notifyListeners();

      WakelockPlus.enable();

      final appDir = await getApplicationDocumentsDirectory();
      final zipPath = '${appDir.path}/${config.folderName}.zip';
      final zipFile = File(zipPath);

      int downloadedBytes = 0;
      if (await zipFile.exists()) {
        downloadedBytes = await zipFile.length();
      }

      final cancelToken = CancelToken();
      _cancelTokens[lang] = cancelToken;
      final dio = Dio();

      final response = await dio.get<ResponseBody>(
        config.url,
        options: Options(
          responseType: ResponseType.stream,
          headers: downloadedBytes > 0 ? {'range': 'bytes=$downloadedBytes-'} : null,
        ),
        cancelToken: cancelToken,
      );

      if (downloadedBytes > 0 && response.statusCode != 206) {
        downloadedBytes = 0;
      }

      int totalBytes = downloadedBytes;
      final contentLengthHeader = response.headers.value(HttpHeaders.contentLengthHeader);
      if (contentLengthHeader != null) {
        totalBytes += int.parse(contentLengthHeader);
      } else {
        totalBytes = config.totalBytesApprox; 
      }

      final fileStream = zipFile.openWrite(mode: downloadedBytes > 0 ? FileMode.append : FileMode.write);

      try {
        await for (final chunk in response.data!.stream) {
          if (cancelToken.isCancelled) break;
          fileStream.add(chunk);
          downloadedBytes += chunk.length;
          _downloadProgress[lang] = downloadedBytes / totalBytes;
          
          notifyListeners();
        }
      } finally {
        await fileStream.close();
      }

      if (cancelToken.isCancelled) {
        return; // Paused
      }

      if (downloadedBytes < totalBytes) {
         throw Exception('Conexión interrumpida antes de terminar.');
      }

      _isDownloading[lang] = false;
      _isExtracting[lang] = true;
      notifyListeners();

      await compute(_extractZip, [zipPath, appDir.path]);

      if (await zipFile.exists()) {
        await zipFile.delete();
      }

      _isExtracting[lang] = false;
      _isModelReady[lang] = true;
      _downloadProgress[lang] = 1.0;
      notifyListeners();

    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        debugPrint('Download paused for $lang');
      } else {
        debugPrint('Network Error: $e');
        _errorMessage[lang] = 'Error de red. Comprueba tu conexión.';
        _isDownloading[lang] = false;
        _isPaused[lang] = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error downloading or extracting model: $e');
      _errorMessage[lang] = 'Error al procesar el archivo.';
      _isDownloading[lang] = false;
      _isExtracting[lang] = false;
      _isPaused[lang] = true;
      notifyListeners();
    } finally {
      final anyActive = _isDownloading.values.any((active) => active) || _isExtracting.values.any((active) => active);
      if (!anyActive) {
        WakelockPlus.disable();
      }
    }
  }
}
