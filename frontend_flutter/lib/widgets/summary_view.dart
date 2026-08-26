import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class SummaryView extends StatelessWidget {
  final Map<String, dynamic> data;

  const SummaryView({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final meetingName = data['MeetingName'] as String? ?? '';
    final sectionOrder = data['_section_order'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (meetingName.isNotEmpty) ...[
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: Colors.indigo.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(LucideIcons.fileText, color: Colors.indigo.shade600),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      meetingName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.indigo.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        ...sectionOrder.map((key) {
          final section = data[key];
          if (section == null || section is! Map<String, dynamic>) {
            return const SizedBox.shrink();
          }
          return _SectionCard(
            title: section['title'] as String? ?? key.toString(),
            blocks: (section['blocks'] as List<dynamic>?) ?? [],
            isDark: isDark,
          );
        }),
      ],
    );
  }
}

class _SectionCard extends StatefulWidget {
  final String title;
  final List<dynamic> blocks;
  final bool isDark;

  const _SectionCard({
    required this.title,
    required this.blocks,
    required this.isDark,
  });

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    if (widget.blocks.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(LucideIcons.chevronDown, size: 20),
                  ),
                ],
              ),
            ),
          ),
          // Blocks
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.blocks.map((block) {
                  if (block is! Map<String, dynamic>) return const SizedBox.shrink();
                  return _buildBlock(block);
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBlock(Map<String, dynamic> block) {
    final type = block['type'] as String? ?? 'text';
    final content = block['content'] as String? ?? '';
    final color = block['color'] as String? ?? '';
    final isGray = color == 'gray';

    switch (type) {
      case 'heading1':
        return Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            content,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isGray ? Colors.grey : null,
            ),
          ),
        );
      case 'heading2':
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            content,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isGray ? Colors.grey : null,
            ),
          ),
        );
      case 'bullet':
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isGray ? Colors.grey.shade400 : Colors.indigo.shade400,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  content,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: isGray ? Colors.grey : null,
                  ),
                ),
              ),
            ],
          ),
        );
      case 'text':
      default:
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            content,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: isGray ? Colors.grey : null,
            ),
          ),
        );
    }
  }
}
