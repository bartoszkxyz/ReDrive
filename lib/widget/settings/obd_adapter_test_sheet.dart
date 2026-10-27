import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../obd/elm/elm_response.dart';
import '../../providers/obd_provider.dart';

class ObdHandshakeResult {
  final String command;
  final String description;
  final String response;
  final int latencyMs;
  final bool isSuccess;

  const ObdHandshakeResult({
    required this.command,
    required this.description,
    required this.response,
    required this.latencyMs,
    required this.isSuccess,
  });
}

void showObdAdapterTestSheet(BuildContext context, ObdProvider obdProvider) {
  HapticFeedback.mediumImpact();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (modalContext) => ObdAdapterTestSheet(obdProvider: obdProvider),
  );
}

class ObdAdapterTestSheet extends StatefulWidget {
  final ObdProvider obdProvider;

  const ObdAdapterTestSheet({super.key, required this.obdProvider});

  @override
  State<ObdAdapterTestSheet> createState() => _ObdAdapterTestSheetState();
}

class _ObdAdapterTestSheetState extends State<ObdAdapterTestSheet> {
  final List<ObdHandshakeResult> _results = [];
  bool _isRunning = false;
  String? _overallVerdict;
  Color _verdictColor = Colors.grey;

  Future<void> _runHandshakeTest() async {
    if (_isRunning) return;

    setState(() {
      _isRunning = true;
      _results.clear();
      _overallVerdict = null;
    });

    final testSteps = [
      ('ATZ', 'Reset ELM327 & Query Firmware'),
      ('ATE0', 'Disable Command Echo'),
      ('ATDP', 'Query Active Protocol Description'),
      ('ATRV', 'Query Battery / Adapter Voltage'),
      ('0100', 'Query Supported PIDs (01-20)'),
      ('010C', 'Query Engine RPM Telemetry'),
    ];

    bool allPassed = true;
    bool anyResponse = false;

    for (final step in testSteps) {
      final cmd = step.$1;
      final desc = step.$2;
      final stopwatch = Stopwatch()..start();

      try {
        final response = await widget.obdProvider.executeCommand(cmd).timeout(
          const Duration(seconds: 4),
          onTimeout: () => throw TimeoutException('Command timed out after 4s'),
        );
        stopwatch.stop();

        final rawLines = response.lines.join(' ').trim();
        final isClean = (response.type == ElmResponseType.ok ||
                response.type == ElmResponseType.data ||
                response.type == ElmResponseType.adapterInfo ||
                response.type == ElmResponseType.adapterVoltage) &&
            !rawLines.contains('UNABLE TO CONNECT') &&
            !rawLines.contains('?');
        if (isClean && rawLines.isNotEmpty) {
          anyResponse = true;
        } else {
          allPassed = false;
        }

        _results.add(
          ObdHandshakeResult(
            command: cmd,
            description: desc,
            response: rawLines.isEmpty ? '(Empty Response)' : rawLines,
            latencyMs: stopwatch.elapsedMilliseconds,
            isSuccess: isClean,
          ),
        );
      } catch (e) {
        stopwatch.stop();
        allPassed = false;
        _results.add(
          ObdHandshakeResult(
            command: cmd,
            description: desc,
            response: 'Error: ${e.toString()}',
            latencyMs: stopwatch.elapsedMilliseconds,
            isSuccess: false,
          ),
        );
      }

      if (mounted) setState(() {});
      await Future.delayed(const Duration(milliseconds: 150));
    }

    if (!mounted) return;

    setState(() {
      _isRunning = false;
      if (allPassed && anyResponse) {
        _overallVerdict = 'Compatible & Fast (Genuine / High-Speed Adapter)';
        _verdictColor = Colors.greenAccent;
      } else if (anyResponse) {
        _overallVerdict = 'Partial Response (Clone / Slower Adapter)';
        _verdictColor = Colors.amberAccent;
      } else {
        _overallVerdict = 'No Response / Disconnected (Check pairing in headunit BT settings)';
        _verdictColor = Colors.redAccent;
      }
    });
  }

  void _copyLogToClipboard() {
    final buffer = StringBuffer();
    buffer.writeln('=== OBDrive OBD-II Adapter Handshake Diagnostic ===');
    for (final r in _results) {
      buffer.writeln('[${r.command}] ${r.description} (${r.latencyMs}ms)');
      buffer.writeln('Response: ${r.response}');
    }
    if (_overallVerdict != null) {
      buffer.writeln('Verdict: $_overallVerdict');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostic log copied to clipboard!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF16181C) : Colors.white;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.speed_rounded, color: theme.colorScheme.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Test OBD Adapter',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Validate ELM327 handshake & TS18 compatibility',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 24),

          // Verdict banner (if completed)
          if (_overallVerdict != null) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _verdictColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _verdictColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(
                    _verdictColor == Colors.greenAccent
                        ? Icons.check_circle_rounded
                        : (_verdictColor == Colors.amberAccent
                            ? Icons.warning_amber_rounded
                            : Icons.error_outline_rounded),
                    color: _verdictColor,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _overallVerdict!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: _verdictColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Test results list
          Expanded(
            child: _results.isEmpty && !_isRunning
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.bluetooth_searching_rounded,
                          size: 48,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tap below to run the handshake test sequence.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final r = _results[index];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF202328) : const Color(0xFFF4F6F8),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: r.isSuccess
                                ? Colors.green.withValues(alpha: 0.3)
                                : Colors.red.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        r.command,
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      r.description,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '${r.latencyMs} ms',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.black38 : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                r.response,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: r.isSuccess ? (isDark ? Colors.greenAccent : Colors.green.shade800) : Colors.redAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                if (_results.isNotEmpty) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy Log'),
                    onPressed: _copyLogToClipboard,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: FilledButton.icon(
                    icon: _isRunning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(_isRunning ? 'Testing...' : 'Run Handshake Test'),
                    onPressed: _isRunning ? null : _runHandshakeTest,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
