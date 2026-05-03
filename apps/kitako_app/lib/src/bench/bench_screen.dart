import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/image_search_service.dart';
import 'bench_models.dart';
import 'bench_runner.dart';

class BenchScreen extends StatefulWidget {
  final ImageSearchService searchService;

  const BenchScreen({super.key, required this.searchService});

  @override
  State<BenchScreen> createState() => _BenchScreenState();
}

class _BenchScreenState extends State<BenchScreen> {
  late final BenchRunner _runner;
  BenchProgress _progress =
      const BenchProgress(completed: 0, total: 0, currentCaption: null, lastRow: null);
  String _statusLine = 'Idle. Press Run to start.';
  File? _csvFile;
  File? _summaryFile;
  BenchSummary? _summary;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _runner = BenchRunner(searchService: widget.searchService);
  }

  Future<void> _start() async {
    if (_runner.isRunning) return;
    setState(() {
      _statusLine = 'Loading input CSV…';
      _csvFile = null;
      _summaryFile = null;
      _summary = null;
      _errorMsg = null;
      _progress = const BenchProgress(
          completed: 0, total: 0, currentCaption: null, lastRow: null);
    });

    try {
      final res = await _runner.run(
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _progress = p;
            if (p.currentCaption != null) {
              _statusLine =
                  '[${p.completed + 1}/${p.total}] running: ${_truncate(p.currentCaption!, 60)}';
            } else if (p.lastRow != null) {
              final r = p.lastRow!;
              _statusLine =
                  '[${p.completed}/${p.total}] last: ${r.latencyMs}ms · '
                  'pss ${r.pssPeakMb.toStringAsFixed(1)}MB · '
                  'trim ${r.trimCount}';
            }
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _csvFile = res.csv;
        _summaryFile = res.summary;
        _summary = res.summary2;
        _statusLine = _summary!.cancelled
            ? 'Cancelled after ${_summary!.succeeded + _summary!.failed} queries.'
            : 'Done. ${_summary!.succeeded} succeeded, ${_summary!.failed} failed.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = e.toString();
        _statusLine = 'Failed.';
      });
    }
  }

  void _cancel() {
    if (!_runner.isRunning) return;
    _runner.cancel();
    setState(() => _statusLine = 'Cancel requested — finishing current query…');
  }

  void _copyPath(String path) {
    Clipboard.setData(ClipboardData(text: path));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied: $path'), duration: const Duration(seconds: 2)),
    );
  }

  String _truncate(String s, int n) =>
      s.length <= n ? s : '${s.substring(0, n)}…';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final running = _runner.isRunning;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Caption Benchmark'),
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Description ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1F2A) : const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: isDark ? const Color(0xFF2A3050) : const Color(0xFFBEC8EE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Reads $kBenchInputAsset (en, fil, tag captions × 100 rows = 300 queries).',
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  const Text(
                    'Records latency, PSS peak, and trim-memory events per query. '
                    'Output goes to /sdcard/Android/data/com.example.kitako_app/files/bench/.',
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Run / Cancel ─────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: Text(running ? 'Running…' : 'Run benchmark'),
                    onPressed: running ? null : _start,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.stop),
                  label: const Text('Cancel'),
                  onPressed: running ? _cancel : null,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Progress ─────────────────────────────────────────────────
            if (_progress.total > 0)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(value: _progress.fraction),
                  const SizedBox(height: 4),
                  Text(
                    '${_progress.completed} / ${_progress.total} '
                    '(${(_progress.fraction * 100).toStringAsFixed(1)}%)',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),

            const SizedBox(height: 8),

            // ── Status line ──────────────────────────────────────────────
            Text(_statusLine, style: const TextStyle(fontSize: 12)),

            if (_errorMsg != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                ),
                child: SelectableText(
                  _errorMsg!,
                  style: const TextStyle(
                      color: Colors.red, fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ],

            const SizedBox(height: 12),
            const Divider(height: 1),

            // ── Result file paths ────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_csvFile != null) ...[
                      const SizedBox(height: 8),
                      const Text('Output CSV',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                      _PathRow(path: _csvFile!.path, onCopy: _copyPath),
                    ],
                    if (_summaryFile != null) ...[
                      const SizedBox(height: 8),
                      const Text('Summary',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                      _PathRow(path: _summaryFile!.path, onCopy: _copyPath),
                    ],
                    if (_summary != null) ...[
                      const SizedBox(height: 12),
                      _SummaryView(summary: _summary!, isDark: isDark),
                    ],
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1F1F1F)
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Pull from device with adb:',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          SelectableText(
                            'adb pull /sdcard/Android/data/com.example.kitako_app/files/bench .',
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PathRow extends StatelessWidget {
  final String path;
  final void Function(String) onCopy;

  const _PathRow({required this.path, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SelectableText(
            path,
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
            maxLines: 2,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 16),
          onPressed: () => onCopy(path),
          tooltip: 'Copy path',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _SummaryView extends StatelessWidget {
  final BenchSummary summary;
  final bool isDark;

  const _SummaryView({required this.summary, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final rows = <(String, String)>[
      ('Total queries', '${s.totalQueries}'),
      ('Succeeded', '${s.succeeded}'),
      ('Failed', '${s.failed}'),
      ('Runtime', '${(s.totalRuntimeMs / 1000).toStringAsFixed(1)}s'),
      ('Latency mean', '${s.meanLatencyMs.toStringAsFixed(0)}ms'),
      ('Latency median', '${s.medianLatencyMs.toStringAsFixed(0)}ms'),
      ('Latency p95', '${s.p95LatencyMs.toStringAsFixed(0)}ms'),
      ('Latency max', '${s.maxLatencyMs.toStringAsFixed(0)}ms'),
      ('PSS peak (run)', '${s.peakPssMb.toStringAsFixed(1)}MB'),
      ('PSS peak (mean)', '${s.meanPssMb.toStringAsFixed(1)}MB'),
      ('Trim events', '${s.totalTrimEvents}'),
      ('Max trim level', '${s.maxTrimLevelSeen}'),
    ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2A1A) : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: isDark ? const Color(0xFF2A4A2A) : const Color(0xFFA5D6A7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SUMMARY',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 6),
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Text(r.$1, style: const TextStyle(fontSize: 11)),
                    const Spacer(),
                    Text(r.$2,
                        style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
