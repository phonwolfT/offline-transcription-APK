import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/meeting.dart';
import '../services/api_service.dart';
import 'meeting_detail_screen.dart';

class MeetingHistoryScreen extends StatefulWidget {
  const MeetingHistoryScreen({super.key});

  @override
  State<MeetingHistoryScreen> createState() => _MeetingHistoryScreenState();
}

class _MeetingHistoryScreenState extends State<MeetingHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];

  Timer? _debounce;

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (query.trim().isEmpty) {
        setState(() {
          _isSearching = false;
          _searchResults = [];
        });
        return;
      }
      
      setState(() => _isSearching = true);
      final results = await context.read<ApiService>().searchTranscripts(query);
      
      if (mounted) {
        setState(() {
          _searchResults = results;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dbService = context.watch<DatabaseService>();
    final meetings = dbService.meetings;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meeting History'),
        actions: [
          if (meetings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${meetings.length} meetings',
                    style: TextStyle(
                      color: Colors.indigo.shade600,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search transcripts...',
                prefixIcon: const Icon(LucideIcons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(LucideIcons.x),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ),
        ),
      ),
      body: _isSearching || _searchController.text.isNotEmpty
          ? _buildSearchResults()
          : (meetings.isEmpty
              ? _buildEmptyState(isDark)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: meetings.length,
                  itemBuilder: (context, index) {
                    final meeting = meetings[index];
                    return _MeetingCard(
                      meeting: meeting,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MeetingDetailScreen(meeting: meeting),
                          ),
                        );
                      },
                      onDelete: () => _confirmDelete(context, dbService, meeting),
                    );
                  },
                )),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return const Center(child: Text('No results found'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final result = _searchResults[index];
        final meetingId = result['meeting_id'];
        final snippet = result['snippet'] ?? result['transcript']; // Adjust based on backend response
        final timestamp = result['timestamp'] ?? '';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text('Meeting: $meetingId'),
            subtitle: Text(
              '$timestamp - $snippet',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              // Try to find the local meeting
              final meeting = context.read<DatabaseService>().meetings.where((m) => m.backendMeetingId == meetingId).firstOrNull;
              if (meeting != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MeetingDetailScreen(meeting: meeting),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Meeting not found locally')),
                );
              }
            },
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, DatabaseService dbService, Meeting meeting) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Meeting?'),
        content: Text('Are you sure you want to delete "${meeting.title}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              dbService.deleteMeeting(meeting.id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${meeting.title} deleted'),
                  backgroundColor: Colors.red.shade600,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.history,
              size: 64,
              color: isDark ? Colors.white24 : Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No meetings recorded yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white54 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your recorded meetings will appear here',
            style: TextStyle(
              color: isDark ? Colors.white30 : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}

class _MeetingCard extends StatelessWidget {
  final Meeting meeting;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _MeetingCard({
    required this.meeting,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Simulate selected state if we want (for now just using standard colors)
    final bool isSelected = false; // Add logic if needed

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected 
            ? (isDark ? Colors.blue.withValues(alpha: 0.2) : Colors.blue.shade50)
            : (isDark ? Colors.white10 : Colors.white),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Document Icon
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    LucideIcons.fileText, 
                    color: isDark ? Colors.grey.shade400 : Colors.blueGrey.shade700, 
                    size: 18
                  ),
                ),
                const SizedBox(width: 16),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meeting.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                          color: isSelected ? Colors.blue.shade700 : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatDate(meeting.date)} - ${meeting.shortDurationFormatted}',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // Actions (Edit and Delete)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.pencil, size: 18),
                      color: Colors.grey.shade600,
                      onPressed: onTap,
                      splashRadius: 20,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(LucideIcons.trash2, size: 18),
                      color: Colors.grey.shade600,
                      onPressed: onDelete,
                      splashRadius: 20,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
