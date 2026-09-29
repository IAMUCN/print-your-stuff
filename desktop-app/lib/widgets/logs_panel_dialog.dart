import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/logger_service.dart';
import '../theme/app_theme.dart';

class LogsPanelDialog extends StatefulWidget {
  const LogsPanelDialog({super.key});

  static Future<void> show(BuildContext context) {
    LoggerService.instance.markErrorsAsRead();
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const LogsPanelDialog(),
    );
  }

  @override
  State<LogsPanelDialog> createState() => _LogsPanelDialogState();
}

class _LogsPanelDialogState extends State<LogsPanelDialog> {
  final LoggerService _logger = LoggerService.instance;
  String _selectedFilter = 'ALL';
  String _searchQuery = '';
  final Set<String> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _logger.addListener(_onLogsChanged);
  }

  @override
  void dispose() {
    _logger.removeListener(_onLogsChanged);
    super.dispose();
  }

  void _onLogsChanged() {
    if (mounted) setState(() {});
  }

  List<LogEntry> get _filteredEntries {
    final entries = _logger.entries;
    return entries.where((entry) {
      if (_selectedFilter == 'ERRORS' && entry.level != LogLevel.error) {
        return false;
      }
      if (_selectedFilter == 'WARNINGS' && entry.level != LogLevel.warning) {
        return false;
      }
      if (_selectedFilter == 'PRINT' && entry.category != LogCategory.print) {
        return false;
      }
      if (_selectedFilter == 'DOWNLOADS' && entry.category != LogCategory.download) {
        return false;
      }

      if (_searchQuery.trim().isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesTitle = entry.title.toLowerCase().contains(query);
        final matchesMsg = entry.message.toLowerCase().contains(query);
        final matchesDetails = entry.details?.toLowerCase().contains(query) ?? false;
        final matchesJob = entry.jobCode?.toLowerCase().contains(query) ?? false;
        return matchesTitle || matchesMsg || matchesDetails || matchesJob;
      }

      return true;
    }).toList();
  }

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return Colors.redAccent;
      case LogLevel.warning:
        return Colors.amber;
      case LogLevel.success:
        return Colors.greenAccent;
      case LogLevel.info:
        return Colors.lightBlueAccent;
    }
  }

  IconData _getLevelIcon(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return Icons.error_outline;
      case LogLevel.warning:
        return Icons.warning_amber_outlined;
      case LogLevel.success:
        return Icons.check_circle_outline;
      case LogLevel.info:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEntries;
    final totalErrors = _logger.entries.where((e) => e.level == LogLevel.error).length;
    final totalWarnings = _logger.entries.where((e) => e.level == LogLevel.warning).length;

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 36),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 780),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.receipt_long_outlined, color: Colors.redAccent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'System Activity & Error Logs',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Inspect real-time print spooler errors, download diagnostics, and API activity',
                          style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.launch, size: 14),
                    label: const Text('Open in Notepad'),
                    onPressed: () => _logger.openLogInNotepad(),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy_all, size: 14),
                    label: const Text('Copy All'),
                    onPressed: () async {
                      await _logger.copyLogsToClipboard();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('📋 Copied all logs to clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_sweep_outlined, size: 14, color: Colors.redAccent),
                    label: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
                    onPressed: () {
                      _logger.clear();
                      setState(() {});
                    },
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    tooltip: 'Close (Esc)',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Controls & Filters Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              color: AppTheme.background,
              child: Row(
                children: [
                  // Filter Chips
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildFilterChip('ALL', 'All (${_logger.entries.length})'),
                      _buildFilterChip(
                        'ERRORS',
                        'Errors ($totalErrors)',
                        badgeColor: totalErrors > 0 ? Colors.redAccent : null,
                      ),
                      _buildFilterChip('WARNINGS', 'Warnings ($totalWarnings)'),
                      _buildFilterChip('PRINT', 'Print Spooler'),
                      _buildFilterChip('DOWNLOADS', 'Downloads'),
                    ],
                  ),
                  const Spacer(),
                  // Search Box
                  SizedBox(
                    width: 260,
                    height: 36,
                    child: TextField(
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search logs or job #...',
                        hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
                        prefixIcon: const Icon(Icons.search, size: 16, color: Colors.grey),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 14),
                                onPressed: () => setState(() => _searchQuery = ''),
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        filled: true,
                        fillColor: AppTheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                  ),
                ],
              ),
            ),

            // Log List
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline, size: 48, color: Colors.grey[700]),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isNotEmpty ? 'No logs matching "$_searchQuery"' : 'No logs recorded yet',
                            style: TextStyle(color: Colors.grey[500], fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : Scrollbar(
                      thumbVisibility: true,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final entry = filtered[index];
                          final isExpanded = _expandedIds.contains(entry.id);
                          final levelColor = _getLevelColor(entry.level);
                          final hasDetails = entry.details != null && entry.details!.trim().isNotEmpty;

                          return Container(
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: entry.level == LogLevel.error
                                    ? Colors.redAccent.withValues(alpha: 0.4)
                                    : AppTheme.border,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: hasDetails
                                      ? () {
                                          setState(() {
                                            if (isExpanded) {
                                              _expandedIds.remove(entry.id);
                                            } else {
                                              _expandedIds.add(entry.id);
                                            }
                                          });
                                        }
                                      : null,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(_getLevelIcon(entry.level), color: levelColor, size: 18),
                                        const SizedBox(width: 10),
                                        // Timestamp
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.06),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            entry.formattedTime,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontFamily: 'Consolas',
                                              color: Colors.grey[400],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Category badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: levelColor.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: levelColor.withValues(alpha: 0.3)),
                                          ),
                                          child: Text(
                                            entry.category.name.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: levelColor,
                                            ),
                                          ),
                                        ),
                                        if (entry.jobCode != null) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.4)),
                                            ),
                                            child: Text(
                                              '#${entry.jobCode}',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.deepPurpleAccent,
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(width: 10),
                                        // Title & Message
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                entry.title,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                entry.message,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[300],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (hasDetails) ...[
                                          const SizedBox(width: 8),
                                          Icon(
                                            isExpanded ? Icons.expand_less : Icons.expand_more,
                                            color: Colors.grey[400],
                                            size: 20,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                if (isExpanded && hasDetails) ...[
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppTheme.border),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'DIAGNOSTIC DETAILS / STACK TRACE',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Consolas',
                                                color: Colors.grey[500],
                                              ),
                                            ),
                                            InkWell(
                                              onTap: () {
                                                Clipboard.setData(ClipboardData(text: entry.details!));
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                    content: Text('Copied error details to clipboard'),
                                                    duration: Duration(seconds: 2),
                                                  ),
                                                );
                                              },
                                              child: Row(
                                                children: [
                                                  Icon(Icons.copy, size: 12, color: Colors.grey[400]),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'Copy Details',
                                                    style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        SelectableText(
                                          entry.details!,
                                          style: const TextStyle(
                                            fontFamily: 'Consolas',
                                            fontSize: 11,
                                            color: Color(0xFFE2E8F0),
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  Icon(Icons.folder_outlined, size: 16, color: Colors.grey[500]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _logger.logFilePath ?? 'Local app logs',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500], fontFamily: 'Consolas'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String filterKey, String label, {Color? badgeColor}) {
    final isSelected = _selectedFilter == filterKey;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: badgeColor ?? (isSelected ? Colors.white : Colors.grey[400]),
        ),
      ),
      selected: isSelected,
      selectedColor: (badgeColor ?? AppTheme.accent).withValues(alpha: 0.25),
      backgroundColor: AppTheme.surface,
      side: BorderSide(
        color: isSelected ? (badgeColor ?? AppTheme.accent) : AppTheme.border,
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedFilter = filterKey);
        }
      },
    );
  }
}
