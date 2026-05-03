import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../services/image_search_service.dart';
import 'bench_csv_io.dart';
import 'bench_memory_probe.dart';
import 'bench_models.dart';

/// Asset path for the input CSV. Drop your file at this path; pubspec already
/// declares `assets/bench/`.
const String kBenchInputAsset = 'assets/bench/test_ch4_100.csv';

/// Top-K results to record per query. Matches the app default.
const int kBenchTopK = 20;

/// Pause between queries to let GC settle.
const Duration kBenchInterQueryDelay = Duration(milliseconds: 200);

/// PSS poll interval during a query.
const Duration kBenchPssPollInterval = Duration(milliseconds: 100);

/// Three caption columns × N input rows = 3N queries total.
enum CaptionColumn { en, fil, tag }

extension on CaptionColumn {
  String get key => switch (this) {
        CaptionColumn.en => 'en',
        CaptionColumn.fil => 'fil',
        CaptionColumn.tag => 'tag',
      };
}

class BenchRunner {
  final ImageSearchService searchService;
  final BenchMemoryProbe probe;

  BenchRunner({
    required this.searchService,
    BenchMemoryProbe? probe,
  }) : probe = probe ?? BenchMemoryProbe();

  bool _cancelRequested = false;
  bool _running = false;

  bool get isRunning => _running;
  void cancel() => _cancelRequested = true;

  /// Runs the full benchmark. Yields progress updates via [onProgress].
  /// Returns the path of the written CSV (and side-by-side summary file).
  Future<({File csv, File summary, BenchSummary summary2})> run({
    required void Function(BenchProgress) onProgress,
  }) async {
    if (_running) {
      throw StateError('Bench is already running');
    }
    _running = true;
    _cancelRequested = false;

    try {
      // ── Load input CSV ──────────────────────────────────────────────────
      final csvText = await rootBundle.loadString(kBenchInputAsset);
      final inputRows = BenchCsvParser.parse(csvText);
      if (inputRows.isEmpty) {
        throw StateError('Input CSV is empty: $kBenchInputAsset');
      }

      // ── Resolve output paths ────────────────────────────────────────────
      // Android: getExternalStorageDirectory() → /sdcard/Android/data/<pkg>/files
      // (no permissions needed; visible via adb pull and Files app).
      // Other platforms: fall back to docs dir.
      Directory baseDir;
      if (Platform.isAndroid) {
        baseDir = await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory();
      } else {
        baseDir = await getApplicationDocumentsDirectory();
      }
      final benchDir = Directory('${baseDir.path}/bench');
      if (!benchDir.existsSync()) benchDir.createSync(recursive: true);

      final ts = _timestamp(DateTime.now());
      final csvFile = File('${benchDir.path}/kitako_bench_$ts.csv');
      final summaryFile = File('${benchDir.path}/kitako_bench_${ts}_summary.txt');

      final writer = BenchCsvWriter(csvFile);
      await writer.writeHeader();

      // ── Plan queries ────────────────────────────────────────────────────
      final plan = <(BenchInputRow, CaptionColumn, String)>[];
      for (final row in inputRows) {
        if (row.enCaption.isNotEmpty) {
          plan.add((row, CaptionColumn.en, row.enCaption));
        }
        if (row.filCaption.isNotEmpty) {
          plan.add((row, CaptionColumn.fil, row.filCaption));
        }
        if (row.tagCaption.isNotEmpty) {
          plan.add((row, CaptionColumn.tag, row.tagCaption));
        }
      }
      final total = plan.length;

      // ── Warm-up ─────────────────────────────────────────────────────────
      // First ONNX run loads weights into accelerator caches; skip its timing.
      try {
        await searchService.searchImages('warm up', topK: kBenchTopK);
      } catch (e) {
        debugPrint('BenchRunner: warm-up failed (continuing): $e');
      }

      // ── Run loop ────────────────────────────────────────────────────────
      final startedAt = DateTime.now();
      final overallSw = Stopwatch()..start();
      final latencies = <int>[];
      final peakPsses = <double>[];
      var maxPssRun = 0.0;
      var succeeded = 0;
      var failed = 0;

      var trimBaseline = await probe.trimSnapshot();
      final trimAtStart = trimBaseline;

      for (var i = 0; i < total; i++) {
        if (_cancelRequested) break;

        final (inputRow, col, caption) = plan[i];

        onProgress(BenchProgress(
          completed: i,
          total: total,
          currentCaption: caption,
          lastRow: null,
        ));

        final row = await _runOne(
          rowIdx: i + 1,
          input: inputRow,
          col: col,
          caption: caption,
          trimBefore: trimBaseline,
        );

        await writer.writeRow(row);

        if (row.error == null) {
          succeeded += 1;
          latencies.add(row.latencyMs);
        } else {
          failed += 1;
        }
        peakPsses.add(row.pssPeakMb);
        if (row.pssPeakMb > maxPssRun) maxPssRun = row.pssPeakMb;

        // Refresh trim baseline AFTER capturing this row's delta so the next
        // row only sees its own callbacks.
        trimBaseline = await probe.trimSnapshot();

        onProgress(BenchProgress(
          completed: i + 1,
          total: total,
          currentCaption: null,
          lastRow: row,
        ));

        // Inter-query delay — gives GC a window without blowing total runtime.
        if (i + 1 < total && !_cancelRequested) {
          await Future<void>.delayed(kBenchInterQueryDelay);
        }
      }

      overallSw.stop();
      await writer.close();

      // ── Summary ─────────────────────────────────────────────────────────
      final endedAt = DateTime.now();
      final trimAtEnd = await probe.trimSnapshot();

      final summary = BenchSummary(
        totalQueries: total,
        succeeded: succeeded,
        failed: failed,
        totalRuntimeMs: overallSw.elapsedMilliseconds,
        meanLatencyMs: _mean(latencies.map((e) => e.toDouble()).toList()),
        medianLatencyMs: _percentile(
            latencies.map((e) => e.toDouble()).toList(), 0.50),
        p95LatencyMs: _percentile(
            latencies.map((e) => e.toDouble()).toList(), 0.95),
        maxLatencyMs: latencies.isEmpty
            ? 0
            : latencies.reduce((a, b) => a > b ? a : b).toDouble(),
        meanPssMb: _mean(peakPsses),
        peakPssMb: maxPssRun,
        totalTrimEvents: trimAtEnd.count - trimAtStart.count,
        maxTrimLevelSeen: trimAtEnd.maxLevel,
        startedAt: startedAt,
        endedAt: endedAt,
        cancelled: _cancelRequested,
      );
      await writeSummaryFile(summaryFile, summary);

      return (csv: csvFile, summary: summaryFile, summary2: summary);
    } finally {
      _running = false;
      _cancelRequested = false;
    }
  }

  Future<BenchQueryRow> _runOne({
    required int rowIdx,
    required BenchInputRow input,
    required CaptionColumn col,
    required String caption,
    required ({int count, int maxLevel}) trimBefore,
  }) async {
    final pssBefore = await probe.pssBytes();
    final poller = PssWatermarkPoller(probe, interval: kBenchPssPollInterval);
    await poller.start();

    final sw = Stopwatch()..start();
    String? error;
    List<String> filenames = const [];
    List<double> scores = const [];
    int? embeddingTimeMs;
    int? searchTimeMs;
    int resultCount = 0;

    try {
      await searchService.searchImages(caption, topK: kBenchTopK);
      final state = searchService.currentState;
      final result = state.result;
      if (result != null) {
        embeddingTimeMs = result.embeddingTimeMs;
        searchTimeMs = result.searchTimeMs;
        resultCount = result.images.length;
        filenames = result.images.map((img) => img.name).toList();
        scores = result.scores ?? const [];
      }
      if (state.status.toString().endsWith('error')) {
        error = state.error ?? 'unknown error';
      }
    } catch (e) {
      error = e.toString();
    } finally {
      sw.stop();
    }

    final peakBytes = poller.stop();
    final pssAfter = await probe.pssBytes();
    final peak = peakBytes > pssAfter ? peakBytes : pssAfter;

    final trimAfter = await probe.trimSnapshot();

    return BenchQueryRow(
      rowIdx: rowIdx,
      imageId: input.imageId,
      category: input.category,
      source: input.source,
      captionColumn: col.key,
      captionText: caption,
      latencyMs: sw.elapsedMilliseconds,
      embeddingTimeMs: embeddingTimeMs,
      searchTimeMs: searchTimeMs,
      resultCount: resultCount,
      pssBeforeMb: pssBefore / (1024 * 1024),
      pssPeakMb: peak / (1024 * 1024),
      pssDeltaMb: (peak - pssBefore) / (1024 * 1024),
      trimCount: trimAfter.count - trimBefore.count,
      trimMaxLevel: trimAfter.maxLevel > trimBefore.maxLevel
          ? trimAfter.maxLevel
          : 0,
      topFilenames: filenames,
      topScores: scores,
      error: error,
    );
  }

  static String _timestamp(DateTime t) {
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${pad(t.month)}${pad(t.day)}_'
        '${pad(t.hour)}${pad(t.minute)}${pad(t.second)}';
  }

  static double _mean(List<double> xs) {
    if (xs.isEmpty) return 0;
    var sum = 0.0;
    for (final v in xs) {
      sum += v;
    }
    return sum / xs.length;
  }

  static double _percentile(List<double> xs, double p) {
    if (xs.isEmpty) return 0;
    final sorted = [...xs]..sort();
    final rank = (p * (sorted.length - 1)).clamp(0, sorted.length - 1);
    final lo = rank.floor();
    final hi = rank.ceil();
    if (lo == hi) return sorted[lo];
    final frac = rank - lo;
    return sorted[lo] + (sorted[hi] - sorted[lo]) * frac;
  }
}
