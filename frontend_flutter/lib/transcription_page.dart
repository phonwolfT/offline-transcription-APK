import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/model_download_service.dart';

class TranscriptionPage extends StatefulWidget {
  const TranscriptionPage({Key? key}) : super(key: key);

  @override
  State<TranscriptionPage> createState() => _TranscriptionPageState();
}

class _TranscriptionPageState extends State<TranscriptionPage> {
  final _vosk = VoskFlutterPlugin.instance();
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;

  bool _recognitionStarted = false;
  String? _error; 

  @override
  void initState() {
    super.initState();
    _initVosk();
  }

  Future<void> _initVosk() async {
    try {
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        setState(() => _error = 'Permiso de micrófono denegado');
        return;
      }

      final modelPath = await ModelDownloadService.instance.getModelPath();

      if (modelPath == null) {
         setState(() => _error = 'Modelo offline no encontrado.\nPor favor, ve a la Configuración y descarga el modelo (1.48 GB).');
         return;
      }

      _model = await _vosk.createModel(modelPath);
      _recognizer = await _vosk.createRecognizer(model: _model!, sampleRate: 16000);
      
      if (Platform.isAndroid) {
        _speechService = await _vosk.initSpeechService(_recognizer!);
      }
      
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Error inicializando Vosk: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transcripción Offline')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 16), textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    if (_error!.contains('Configuración')) {
                      Navigator.pushNamed(context, '/settings');
                    } else {
                      setState(() => _error = null);
                      _initVosk();
                    }
                  },
                  icon: Icon(_error!.contains('Configuración') ? Icons.settings : Icons.refresh),
                  label: Text(_error!.contains('Configuración') ? 'Ir a Configuración' : 'Reintentar'),
                )
              ],
            ),
          ),
        ),
      );
    }

    if (_speechService == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transcripción Offline')),
        body: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Cargando modelo offline...')
        ])),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Transcripción Offline')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder(
                stream: _speechService!.onPartial(),
                builder: (context, snapshot) {
                  return Text(
                    "Parcial:\n${snapshot.data ?? ''}",
                    style: const TextStyle(fontSize: 18, color: Colors.grey),
                  );
                }
              ),
            ),
            const Divider(),
            Expanded(
              child: StreamBuilder(
                stream: _speechService!.onResult(),
                builder: (context, snapshot) {
                  return Text(
                    "Resultado Final:\n${snapshot.data ?? ''}",
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  );
                }
              ),
            ),
            ElevatedButton.icon(
              icon: Icon(_recognitionStarted ? Icons.stop : Icons.mic),
              label: Text(_recognitionStarted ? "Detener Transcripción" : "Iniciar Transcripción"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                backgroundColor: _recognitionStarted ? Colors.red : Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (_recognitionStarted) {
                  await _speechService!.stop();
                } else {
                  await _speechService!.start();
                }
                setState(() => _recognitionStarted = !_recognitionStarted);
              },
            ),
          ],
        ),
      ),
    );
  }
}
