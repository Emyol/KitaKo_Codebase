// Bench data structures. Self-contained — no app imports.

/// One row from the input CSV/TSV. Captures the full input record so the
/// output keeps id/category/source for traceability.
class BenchInputRow {
  final String imageId;
  final String category;
  final String source;
  final String enCaption;
  final String filCaption;
  final String tagCaption;

  const BenchInputRow({
    required this.imageId,
    required this.category,
    required this.source,
    required this.enCaption,
    required this.filCaption,
    required this.tagCaption,
  });
}

/// One execution record per (input row × caption column).
class BenchQueryRow {
  final int rowIdx;            // 1-based, monotonic across all rows written
  final String imageId;
  final String category;
  final String source;
  final String captionColumn;  // 'en' | 'fil' | 'tag'
  final String captionText;
  final int latencyMs;         // total wall-clock
  final int? embeddingTimeMs;  // from SearchResult, if exposed
  final int? searchTimeMs;     // from SearchResult, if exposed
  final int resultCount;
  final double pssBeforeMb;
  final double pssPeakMb;
  final double pssDeltaMb;
  final int trimCount;         // delta during this query
  final int trimMaxLevel;      // max level seen during this query (0 = none)
  final List<String> topFilenames;
  final List<double> topScores;
  final String? error;         // null on success

  const BenchQueryRow({
    required this.rowIdx,
    required this.imageId,
    required this.category,
    required this.source,
    required this.captionColumn,
    required this.captionText,
    required this.latencyMs,
    required this.embeddingTimeMs,
    required this.searchTimeMs,
    required this.resultCount,
    required this.pssBeforeMb,
    required this.pssPeakMb,
    required this.pssDeltaMb,
    required this.trimCount,
    required this.trimMaxLevel,
    required this.topFilenames,
    required this.topScores,
    required this.error,
  });
}

/// Aggregated stats written to the sidecar summary file.
class BenchSummary {
  final int totalQueries;
  final int succeeded;
  final int failed;
  final int totalRuntimeMs;
  final double meanLatencyMs;
  final double medianLatencyMs;
  final double p95LatencyMs;
  final double maxLatencyMs;
  final double meanPssMb;
  final double peakPssMb;
  final int totalTrimEvents;
  final int maxTrimLevelSeen;
  final DateTime startedAt;
  final DateTime endedAt;
  final bool cancelled;

  const BenchSummary({
    required this.totalQueries,
    required this.succeeded,
    required this.failed,
    required this.totalRuntimeMs,
    required this.meanLatencyMs,
    required this.medianLatencyMs,
    required this.p95LatencyMs,
    required this.maxLatencyMs,
    required this.meanPssMb,
    required this.peakPssMb,
    required this.totalTrimEvents,
    required this.maxTrimLevelSeen,
    required this.startedAt,
    required this.endedAt,
    required this.cancelled,
  });
}

/// Snapshot of the current run, surfaced to the UI.
class BenchProgress {
  final int completed;
  final int total;
  final String? currentCaption;
  final BenchQueryRow? lastRow;

  const BenchProgress({
    required this.completed,
    required this.total,
    required this.currentCaption,
    required this.lastRow,
  });

  double get fraction => total == 0 ? 0 : completed / total;
}
