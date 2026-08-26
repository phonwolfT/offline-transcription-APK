import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:llamadart/llamadart.dart';

class LLMService {
  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;
  LLMService._internal();

  LlamaEngine? _engine;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. Copy model from assets to local file system
      final modelFile = await _copyAssetToLocalFile(
        'assets/models/qwen2.5-1.5b-instruct-q3_k_m.gguf',
        'qwen2.5_1.5b.gguf',
      );

      // 2. Initialize the Llama engine
      _engine = LlamaEngine(LlamaBackend());
      await _engine!.loadModel(
        modelFile.path, 
        modelParams: const ModelParams(contextSize: 2048),
      );

      _isInitialized = true;
      print("LLM Initialized at ${modelFile.path}");
    } catch (e) {
      print("Error initializing LLM: $e");
    }
  }

  Future<File> _copyAssetToLocalFile(String assetPath, String localFilename) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$localFilename');
    
    // Si ya existe, no lo volvemos a copiar para ahorrar tiempo
    if (await file.exists()) {
      return file;
    }

    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<String> generateSummary(String transcription, {String language = 'es'}) async {
    if (!_isInitialized || _engine == null) {
      await initialize();
      if (!_isInitialized) {
        return "Error: Could not initialize local LLM.";
      }
    }

    try {
      final String systemPrompt = language == 'en' 
          ? 'You are a highly capable AI meeting assistant. Create a detailed and comprehensive summary of the provided transcript. Extract all dates, times, schedules, tasks, and key decisions. DO NOT repeat or quote the transcript. ONLY output the summary. Write the summary in English.'
          : language == 'pt'
          ? 'Você é um assistente de IA especialista em reuniões. Crie um resumo muito detalhado da transcrição. Extraia datas, horários, tarefas e decisões. NÃO repita ou cite a transcrição. Escreva APENAS o resumo em português.'
          : 'Eres un asistente de IA experto en reuniones. Crea un resumen detallado y completo de la transcripción. Extrae todas las fechas, horarios, compromisos, tareas y decisiones importantes. NO repitas ni transcribas el texto original. Escribe SOLO el resumen en español.';

      final String userPrompt = language == 'en'
          ? 'Write a detailed summary of this transcript. DO NOT repeat the transcript:\n\n<transcript>\n$transcription\n</transcript>'
          : language == 'pt'
          ? 'Escreva um resumo detalhado desta transcrição. NÃO repita a transcrição:\n\n<transcript>\n$transcription\n</transcript>'
          : 'Escribe un resumen detallado de esta transcripción. NO repitas la transcripción, solo genera el resumen:\n\n<transcript>\n$transcription\n</transcript>';

      final session = ChatSession(
        _engine!, 
        systemPrompt: systemPrompt
      );
      final responseBuffer = StringBuffer();

      final parts = [LlamaTextContent(userPrompt)];

      await for (final chunk in session.create(
        parts,
        params: const GenerationParams(
          maxTokens: 512,
          temp: 0.1,
        ),
      )) {
        final text = chunk.choices.first.delta.content;
        if (text != null) {
          responseBuffer.write(text);
        }
      }
      
      return responseBuffer.toString().trim();
    } catch (e) {
      return "Error generating summary: $e";
    }
  }

  void dispose() {
    _engine?.dispose();
    _isInitialized = false;
  }
}
