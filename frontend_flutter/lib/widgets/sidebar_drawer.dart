import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:file_selector/file_selector.dart';
import '../services/database_service.dart';
import '../models/meeting.dart';
import '../screens/meeting_detail_screen.dart';

class SidebarDrawer extends StatelessWidget {
  const SidebarDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final dbService = context.watch<DatabaseService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.indigo.shade400, Colors.indigo.shade600],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(LucideIcons.mic, size: 24, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Meetily',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        '${dbService.meetingCount} meetings',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const SizedBox(height: 8),
                  _DrawerItem(
                    icon: LucideIcons.home,
                    title: 'Home',
                    selected: _isCurrentRoute(context, '/'),
                    onTap: () {
                      Navigator.pop(context);
                      if (!_isCurrentRoute(context, '/')) {
                        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
                      }
                    },
                  ),
                  _DrawerItem(
                    icon: LucideIcons.mic,
                    title: 'Record',
                    iconColor: Colors.red.shade400,
                    onTap: () {
                      Navigator.pop(context);
                      if (!_isCurrentRoute(context, '/')) {
                        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
                      }
                    },
                  ),
                  _DrawerItem(
                    icon: LucideIcons.upload,
                    title: 'Import Audio',
                    iconColor: Colors.blue.shade400,
                    onTap: () async {
                      Navigator.pop(context); // Close drawer
                      try {
                        final XTypeGroup typeGroup = XTypeGroup(
                          label: 'Audio',
                          extensions: <String>['mp3', 'wav', 'm4a', 'flac', 'aac'],
                        );
                        final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);

                        if (file != null) {
                          final path = file.path;
                          final name = file.name;
                          
                          // We need to create a meeting object and navigate to MeetingDetailScreen
                          final newMeeting = Meeting(
                            id: DateTime.now().millisecondsSinceEpoch.toString(),
                            title: 'Imported: $name',
                            date: DateTime.now(),
                            filePath: path,
                            durationSeconds: 0,
                          );
                          
                          await dbService.saveMeeting(newMeeting);
                          
                          if (context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MeetingDetailScreen(meeting: newMeeting, autoStartRecording: false),
                              ),
                            );
                            
                            // Automatically trigger upload and process if we are connected
                            // We can let the user click "Process Transcript" on the MeetingDetailScreen, 
                            // which is better UX as they might want to change model settings.
                          }
                        }
                      } catch (e) {
                        debugPrint('Error picking file: $e');
                      }
                    },
                  ),
                  _DrawerItem(
                    icon: LucideIcons.fileText,
                    title: 'Meeting Notes',
                    selected: _isCurrentRoute(context, '/history'),
                    trailing: dbService.meetingCount > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${dbService.meetingCount}',
                              style: TextStyle(
                                color: Colors.indigo.shade600,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/history');
                    },
                  ),
                  _DrawerItem(
                    icon: LucideIcons.settings,
                    title: 'Settings',
                    selected: _isCurrentRoute(context, '/settings'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/settings');
                    },
                  ),
                  _DrawerItem(
                    icon: LucideIcons.info,
                    title: 'About',
                    onTap: () {
                      Navigator.pop(context);
                      // TODO: Implement About screen or dialog
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Meetily v1.0.0',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isCurrentRoute(BuildContext context, String route) {
    return ModalRoute.of(context)?.settings.name == route;
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool selected;
  final Widget? trailing;
  final VoidCallback onTap;
  final Color? iconColor;

  const _DrawerItem({
    required this.icon,
    required this.title,
    this.selected = false,
    this.trailing,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? Colors.indigo : iconColor,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? Colors.indigo : null,
        ),
      ),
      trailing: trailing,
      selected: selected,
      selectedTileColor: Colors.indigo.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      onTap: onTap,
    );
  }
}
