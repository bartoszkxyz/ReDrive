import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obdrive/services/logging/log_service.dart';

void showLogViewerSheet(BuildContext context) {
  HapticFeedback.mediumImpact();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (modalContext) {
      return const LogViewerSheet();
    },
  );
}

class LogViewerSheet extends StatefulWidget {
  const LogViewerSheet({super.key});

  @override
  State<LogViewerSheet> createState() => _LogViewerSheetState();
}

class _LogViewerSheetState extends State<LogViewerSheet> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  StreamSubscription<LogEntry>? _logSubscription;
  List<LogEntry> _entries = [];
  String _selectedFilter = 'All';
  String _searchQuery = '';
  int _fileSizeBytes = 0;
  bool _autoScroll = true;
  String? _mirrorPath;

  @override
  void initState() {
    super.initState();
    _entries = LogService.getEntries();
    _mirrorPath = LogService.publicMirrorDirOverride?.path;
    _loadLogs();

    _logSubscription = LogService.onNewEntry.listen((_) {
      if (mounted) {
        setState(() {
          _entries = LogService.getEntries();
        });
        _updateFileSize();
        if (_autoScroll && _scrollController.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    final entries = LogService.getEntries();
    final size = await LogService.getLogFileSize();
    final mirrorDir = await LogService.getPublicOBDriveDirectory();
    if (mounted) {
      setState(() {
        _entries = entries;
        _fileSizeBytes = size;
        _mirrorPath = mirrorDir?.path;
      });
      if (_autoScroll && _scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
    }
  }

  Future<void> _updateFileSize() async {
    final size = await LogService.getLogFileSize();
    if (mounted) {
      setState(() => _fileSizeBytes = size);
    }
  }

  List<LogEntry> get _filteredEntries {
    return _entries.where((e) {
      // 1. Tag / level filter
      if (_selectedFilter == 'OBD' && !e.tag.toLowerCase().contains('obd')) return false;
      if (_selectedFilter == 'Bluetooth' && !e.tag.toLowerCase().contains('blue')) return false;
      if (_selectedFilter == 'Trip' && !e.tag.toLowerCase().contains('trip')) return false;
      if (_selectedFilter == 'Errors' && e.level != LogLevel.error && e.level != LogLevel.warning) {
        return false;
      }

      // 2. Search query filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesMsg = e.message.toLowerCase().contains(query);
        final matchesTag = e.tag.toLowerCase().contains(query);
        final matchesErr = e.error?.toString().toLowerCase().contains(query) ?? false;
        return matchesMsg || matchesTag || matchesErr;
      }

      return true;
    }).toList();
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return const Color(0xFFFF5252); // Red accent
      case LogLevel.warning:
        return const Color(0xFFFFAB00); // Amber
      case LogLevel.info:
        return const Color(0xFF69F0AE); // Green
      case LogLevel.debug:
        return const Color(0xFF40C4FF); // Cyan
    }
  }

  Future<void> _copyAllLogs() async {
    final fullLog = await LogService.exportLogs();
    await Clipboard.setData(ClipboardData(text: fullLog));

    if (mounted) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All logs copied to clipboard'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222B),
        title: const Text('Clear All Logs?'),
        content: const Text(
          'This will permanently delete the collected debug log file and clear in-memory history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await LogService.clearLogs();
      await _loadLogs();
      if (mounted) {
        setState(() {
          _entries = LogService.getEntries();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logs cleared successfully'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final filtered = _filteredEntries;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          height: size.height * 0.90,
          decoration: BoxDecoration(
            color: const Color(0xFF13171F).withValues(alpha: 0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: [
              // ── Drag Handle ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),

              // ── Header ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.bug_report_rounded, color: colorScheme.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Diagnostic Logs',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: LogService.isEnabled ? const Color(0xFF00E676) : Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                LogService.isEnabled ? 'Logging Active' : 'Logging Inactive',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: LogService.isEnabled
                                      ? const Color(0xFF00E676)
                                      : Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '• ${_entries.length} entries (${_formatFileSize(_fileSizeBytes)})',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.4),
                                ),
                              ),
                            ],
                          ),
                          if (_mirrorPath != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Mirror: $_mirrorPath',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // ── Toolbar: Actions & Search ────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    // Search bar
                    Expanded(
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(fontSize: 13, color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Search logs (e.g. timeout, ATZ, OBD)...',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white54),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16, color: Colors.white54),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onChanged: (val) => setState(() => _searchQuery = val),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Copy All Button
                    IconButton(
                      tooltip: 'Copy all logs',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.white),
                      onPressed: _copyAllLogs,
                    ),
                    const SizedBox(width: 6),

                    // Clear Logs Button
                    IconButton(
                      tooltip: 'Clear logs',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                      onPressed: _clearLogs,
                    ),
                  ],
                ),
              ),

              // ── Category Filter Chips ────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['All', 'OBD', 'Bluetooth', 'Trip', 'Errors'].map((filter) {
                      final isSelected = _selectedFilter == filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            filter,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? Colors.black : Colors.white70,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: colorScheme.primary,
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() => _selectedFilter = filter),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              const Divider(color: Colors.white12, height: 1),

              // ── Log Console Output ───────────────────────────────────────
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.article_outlined,
                              size: 48,
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              LogService.isEnabled
                                  ? 'No logs recorded for this filter'
                                  : 'Debug logging is currently disabled.\nEnable it in Settings to record telemetry.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        color: Colors.black.withValues(alpha: 0.4),
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final entry = filtered[index];
                            final color = _getLevelColor(entry.level);

                            final timeStr =
                                '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}.${entry.timestamp.millisecond.toString().padLeft(3, '0')}';

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.5),
                              child: SelectableText.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '$timeStr ',
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        color: Colors.white.withValues(alpha: 0.35),
                                      ),
                                    ),
                                    TextSpan(
                                      text: '[${entry.levelLabel}] ',
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: color,
                                      ),
                                    ),
                                    TextSpan(
                                      text: '[${entry.tag}] ',
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        color: Colors.white.withValues(alpha: 0.7),
                                      ),
                                    ),
                                    TextSpan(
                                      text: entry.message,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        color: Colors.white,
                                      ),
                                    ),
                                    if (entry.error != null)
                                      TextSpan(
                                        text: '\n   → ${entry.error}',
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 11,
                                          color: Colors.redAccent.withValues(alpha: 0.9),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),

              // ── Footer: Auto-Scroll & File Path ──────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFF181C26),
                  border: Border(top: BorderSide(color: Colors.white10)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Log file: obdrive_debug.log',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          'Auto-scroll',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Transform.scale(
                          scale: 0.7,
                          child: CupertinoSwitch(
                            value: _autoScroll,
                            activeTrackColor: colorScheme.primary,
                            onChanged: (val) => setState(() => _autoScroll = val),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
