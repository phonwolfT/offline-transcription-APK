import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/api_service.dart';
import '../services/model_download_service.dart';
import '../services/notion_service.dart';
import '../services/sync_manager.dart';
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _modelController;
  late TextEditingController _apiKeyController;

  late TextEditingController _notionApiKeyController;
  late TextEditingController _notionDbController;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _modelController = TextEditingController(text: settings.aiModel);
    _apiKeyController = TextEditingController(text: settings.apiKey);
    
    _notionApiKeyController = TextEditingController();
    _notionDbController = TextEditingController();
  }

  @override
  void dispose() {
    _modelController.dispose();
    _apiKeyController.dispose();
    _notionApiKeyController.dispose();
    _notionDbController.dispose();
    super.dispose();
  }

  void _showDeleteModelDialog(BuildContext context, ModelDownloadService modelService, String lang) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Modelo'),
        content: const Text('¿Estás seguro de eliminar el modelo offline? Ya no podrás transcribir sin conexión hasta que lo vuelvas a descargar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              modelService.deleteModel(lang);
              Navigator.pop(ctx);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildModelCard(BuildContext context, ModelDownloadService modelService, String lang, String title, String sizeStr) {
    final bool isReady = modelService.isModelReady(lang);
    final bool isDownloading = modelService.isDownloading(lang);
    final bool isExtracting = modelService.isExtracting(lang);
    final bool isPaused = modelService.isPaused(lang);
    final String? errorMessage = modelService.errorMessage(lang);
    final double progress = modelService.downloadProgress(lang);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            if (isReady)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(LucideIcons.checkCircle2, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Instalado y listo.', style: TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _showDeleteModelDialog(context, modelService, lang),
                      icon: const Icon(LucideIcons.trash2, color: Colors.red),
                      label: const Text('Eliminar Modelo', style: TextStyle(color: Colors.red)),
                      style: FilledButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.1)),
                    ),
                  ),
                ],
              )
            else if (isDownloading || isExtracting || isPaused || errorMessage != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.alertCircle, color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(errorMessage, style: const TextStyle(color: Colors.red, fontSize: 13))),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      if (isDownloading || isExtracting)
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      else if (isPaused || errorMessage != null)
                        const Icon(LucideIcons.pauseCircle, color: Colors.orange, size: 20),
                      
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isExtracting ? 'Extrayendo...' 
                            : isPaused ? 'Pausado'
                            : errorMessage != null ? 'Interrumpido'
                            : 'Descargando ($sizeStr)...',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  if (!isExtracting) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: progress,
                      color: (isPaused || errorMessage != null) ? Colors.orange : null,
                      backgroundColor: (isPaused || errorMessage != null) ? Colors.orange.withOpacity(0.2) : null,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${(progress * 100).toStringAsFixed(1)}% completado', style: const TextStyle(fontSize: 12)),
                        if (isDownloading)
                          TextButton.icon(
                            onPressed: () => modelService.pauseDownload(lang),
                            icon: const Icon(LucideIcons.pause, size: 16),
                            label: const Text('Pausar', style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                          )
                        else if (isPaused || errorMessage != null)
                          TextButton.icon(
                            onPressed: () => modelService.resumeDownload(lang),
                            icon: const Icon(LucideIcons.play, size: 16),
                            label: const Text('Reanudar', style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                          ),
                      ],
                    ),
                  ]
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Se requiere descargar el modelo ($sizeStr) para usar transcripción offline en este idioma.',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => modelService.downloadAndExtractModel(lang),
                      icon: const Icon(LucideIcons.download),
                      label: Text('Descargar ($sizeStr)'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [


          // Integrations Section
          _buildSectionHeader('Integraciones', LucideIcons.link),
          _buildNotionSection(context),

          const SizedBox(height: 24),

          // Vosk Offline Model Section
          _buildSectionHeader('Offline Models (Vosk)', LucideIcons.downloadCloud),
          Consumer<ModelDownloadService>(
            builder: (context, modelService, child) {
              return Column(
                children: [
                  _buildModelCard(context, modelService, 'es', 'Español (ES)', '1.48 GB'),
                  _buildModelCard(context, modelService, 'en', 'Inglés (EN-US)', '1.80 GB'),
                  _buildModelCard(context, modelService, 'pt', 'Portugués (PT)', '1.30 GB'),
                ],
              );
            },
          ),



          const SizedBox(height: 24),

          // Audio Quality Section
          _buildSectionHeader('Audio Quality', LucideIcons.volume2),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: settings.audioQuality,
                decoration: InputDecoration(
                  labelText: 'Recording Quality',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(LucideIcons.sliders),
                ),
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('Low (64 kbps)')),
                  DropdownMenuItem(value: 'medium', child: Text('Medium (128 kbps)')),
                  DropdownMenuItem(value: 'high', child: Text('High (256 kbps)')),
                ],
                onChanged: (value) {
                  if (value != null) settings.setAudioQuality(value);
                },
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Appearance Section
          _buildSectionHeader('Appearance', LucideIcons.palette),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: const Text('System Default'),
                  subtitle: const Text('Follow device settings'),
                  value: ThemeMode.system,
                  groupValue: settings.themeMode,
                  onChanged: (mode) => settings.setThemeMode(mode!),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Light Mode'),
                  value: ThemeMode.light,
                  groupValue: settings.themeMode,
                  onChanged: (mode) => settings.setThemeMode(mode!),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Dark Mode'),
                  value: ThemeMode.dark,
                  groupValue: settings.themeMode,
                  onChanged: (mode) => settings.setThemeMode(mode!),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // About Section
          _buildSectionHeader('About', LucideIcons.info),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Meetily', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('Version 1.0.0', style: TextStyle(color: Colors.grey)),
                  SizedBox(height: 8),
                  Text(
                    'AI-powered meeting recorder and summarizer',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.indigo),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotionSection(BuildContext context) {
    final notionService = context.watch<NotionService>();
    final isConfigured = notionService.isConfigured;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.fileText, size: 20),
                const SizedBox(width: 8),
                const Text('Notion', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isConfigured ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isConfigured ? '🟢 Conectado' : '🟠 Sin configurar',
                    style: TextStyle(
                      fontSize: 12,
                      color: isConfigured ? Colors.green : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!isConfigured) ...[
              TextField(
                controller: _notionApiKeyController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Notion API Key',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notionDbController,
                decoration: InputDecoration(
                  labelText: 'Database ID',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    if (_notionApiKeyController.text.isNotEmpty && _notionDbController.text.isNotEmpty) {
                      await notionService.saveCredentials(
                        _notionApiKeyController.text,
                        _notionDbController.text,
                      );
                      setState(() {});
                      _notionApiKeyController.clear();
                      _notionDbController.clear();
                    }
                  },
                  child: const Text('Guardar configuración'),
                ),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Probando conexión...')));
                    final success = await notionService.testConnection();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    if (success) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Conexión con Notion exitosa')));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ No se pudo conectar con Notion')));
                    }
                  },
                  icon: const Icon(LucideIcons.plug2),
                  label: const Text('Probar conexión'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sincronizando con Notion...')));
                    await SyncManager.instance.processNotionQueue();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sincronización finalizada')));
                  },
                  icon: const Icon(LucideIcons.refreshCw),
                  label: const Text('Sincronizar ahora'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () async {
                    await notionService.clearCredentials();
                    setState(() {});
                  },
                  icon: const Icon(LucideIcons.logOut, color: Colors.red),
                  label: const Text('Desconectar', style: TextStyle(color: Colors.red)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
