import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/meeting_history_screen.dart';
import 'screens/settings_screen.dart';
import 'services/recording_service.dart';
import 'services/database_service.dart';
import 'services/api_service.dart';
import 'services/settings_service.dart';
import 'services/websocket_service.dart';
import 'services/model_download_service.dart';
import 'models/pending_sync_item.dart';
import 'services/connectivity_watcher.dart';
import 'services/sync_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();
  Hive.registerAdapter(SyncStatusAdapter());
  Hive.registerAdapter(PendingSyncItemAdapter());

  // Initialize services
  final databaseService = DatabaseService();
  await databaseService.init();

  final settingsService = SettingsService();
  await settingsService.init();

  final apiService = ApiService();
  apiService.setBaseUrl(settingsService.backendUrl);

  SyncManager.instance.init(apiService);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RecordingService()),
        ChangeNotifierProvider.value(value: databaseService),
        ChangeNotifierProvider.value(value: settingsService),
        ChangeNotifierProvider.value(value: apiService),
        ChangeNotifierProvider(create: (_) => WebSocketService(settingsService)),
        ChangeNotifierProvider.value(value: ModelDownloadService.instance),
        ChangeNotifierProvider(create: (_) => ConnectivityWatcher()),
      ],
      child: const MeetilyApp(),
    ),
  );
}

class MeetilyApp extends StatelessWidget {
  const MeetilyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return MaterialApp(
      title: 'Meetily',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.themeMode,
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        '/history': (context) => const MeetingHistoryScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
