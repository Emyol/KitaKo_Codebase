/// KitaKo ANN Benchmark Script — Sprint 8
///
/// Runs benchmark experiments across preset-locked ANN configurations,
/// logs to a standard schema (JSON + CSV), validates log integrity,
/// and writes results tables to results/sprint8/{run_id}/.
///
/// Proxy dataset: generates N random 768-D unit vectors with brute-force
/// ground-truth nearest neighbours so the script runs offline and produces
/// repeatable numbers across model variants.
///
/// Usage:
///   dart run tools/bench_ann.dart [options]
///   dart run tools/bench_ann.dart --n 5000 --queries 50 --k 10
///   dart run tools/bench_ann.dart --algo ivfpq --preset high
///   dart run tools/bench_ann.dart --help
library bench_ann;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:kitako_ann/kitako_ann.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 1. LOCKED PRESET DEFINITIONS
//    DO NOT CHANGE THESE BETWEEN EXPERIMENTS — changes invalidate cross-run
//    comparisons.  To test new values add a new named preset instead.
// ═══════════════════════════════════════════════════════════════════════════

enum PresetTier { low, balanced, high }

/// Immutable HNSW hyperparameter preset.
class HnswPreset {
  final String name;
  final PresetTier tier;
  final int m;
  final int efConstruction;
  final int efSearch;

  const HnswPreset({
    required this.name,
    required this.tier,
    required this.m,
    required this.efConstruction,
    required this.efSearch,
  });

  Map<String, dynamic> toMap() => {
        'M': m,
        'efConstruction': efConstruction,
        'efSearch': efSearch,
      };
}

/// Immutable IVF-PQ hyperparameter preset.
class IvfPqPreset {
  final String name;
  final PresetTier tier;

  /// Number of Voronoi cells (nlist / numClusters)
  final int nlist;

  /// Cells probed at query time (nprobe / numProbes)
  final int nprobe;

  /// Number of subquantizers — must divide 768 evenly
  final int m;

  /// Bits per code → centroids per subquantizer = 2^nbits
  final int nbits;

  const IvfPqPreset({
    required this.name,
    required this.tier,
    required this.nlist,
    required this.nprobe,
    required this.m,
    required this.nbits,
  });

  int get numCentroids => 1 << nbits; // 2^nbits

  Map<String, dynamic> toMap() => {
        'nlist': nlist,
        'nprobe': nprobe,
        'm': m,
        'nbits': nbits,
        'numCentroids': numCentroids,
      };
}

/// All locked presets.  Indexed as BenchPresets.hnsw[tier] etc.
abstract class BenchPresets {
  // -------------------------------------------------------------------
  // HNSW — tuned for 768-D SigLIP embeddings (mobile-target footprint)
  // -------------------------------------------------------------------
  static const Map<PresetTier, HnswPreset> hnsw = {
    PresetTier.low: HnswPreset(
      name: 'hnsw_low',
      tier: PresetTier.low,
      m: 8,
      efConstruction: 100,
      efSearch: 32,
    ),
    PresetTier.balanced: HnswPreset(
      name: 'hnsw_balanced',
      tier: PresetTier.balanced,
      m: 16,
      efConstruction: 200,
      efSearch: 64,
    ),
    PresetTier.high: HnswPreset(
      name: 'hnsw_high',
      tier: PresetTier.high,
      m: 32,
      efConstruction: 400,
      efSearch: 128,
    ),
  };

  // -------------------------------------------------------------------
  // IVF-PQ — dimensioned for ~5 000 proxy vectors; scale nlist/nprobe
  // proportionally when testing on larger production datasets.
  // dim=768 divisors used: m ∈ {8, 48, 96}  (768÷m ∈ {96,16,8} dims/SQ)
  // -------------------------------------------------------------------
  static const Map<PresetTier, IvfPqPreset> ivfpq = {
    PresetTier.low: IvfPqPreset(
      name: 'ivfpq_low',
      tier: PresetTier.low,
      nlist: 32,
      nprobe: 4,
      m: 8, // 96 dims/subspace — coarser, smaller codes
      nbits: 8,
    ),
    PresetTier.balanced: IvfPqPreset(
      name: 'ivfpq_balanced',
      tier: PresetTier.balanced,
      nlist: 64,
      nprobe: 8,
      m: 48, // 16 dims/subspace
      nbits: 8,
    ),
    PresetTier.high: IvfPqPreset(
      name: 'ivfpq_high',
      tier: PresetTier.high,
      nlist: 128,
      nprobe: 32,
      m: 96, // 8 dims/subspace — finest quantization
      nbits: 8,
    ),
  };

  // Human-readable tier label
  static String tierLabel(PresetTier t) => t.name; // 'low' | 'balanced' | 'high'
}

// ═══════════════════════════════════════════════════════════════════════════
// 2. STANDARD LOG SCHEMA
// ═══════════════════════════════════════════════════════════════════════════

/// A single experiment record. All fields are required; missing any field
/// causes LogValidator to reject the record.
class ExperimentRecord {
  // --- Identity ---
  final String experimentId;
  final String sprint;
  final String runTimestamp; // ISO-8601
  final int runTimestampMs; // epoch ms

  // --- Model ---
  final String model; // e.g. 'kitako_mixed', 'proxy_synthetic'
  final String modelPrecision; // 'fp32' | 'int8' | 'mixed' | 'synthetic'

  // --- ANN ---
  final String annMethod; // 'hnsw' | 'ivfpq'
  final String presetName; // e.g. 'hnsw_balanced'
  final Map<String, dynamic> hyperparams;

  // --- Dataset ---
  final int datasetSize;
  final int queryCount;
  final String queryLanguageLabel; // 'en' | 'tl' | 'taglish' | 'synthetic'

  // --- Per-query result snapshot (last query logged as example) ---
  final List<Map<String, dynamic>> topKResults; // [{rank, id, distance}, ...]

  // --- Aggregate metrics ---
  final Map<String, double> recallAtK; // {'1': 0.9, '5': 0.95, ...}
  final double meanAveragePrecision;
  final double latencyMedianMs;
  final double latencyP95Ms;
  final int buildTimeMs;

  // --- System ---
  final int peakRamBytes;
  final bool lmkIncidentFlag; // Low Memory Killer hit (Android only)

  // --- Device ---
  final int deviceRamMb;
  final String deviceSoC; // e.g. 'Snapdragon 8 Gen 3' | 'N/A (desktop)'
  final String deviceOs; // e.g. 'Android 14' | 'Windows 11'

  const ExperimentRecord({
    required this.experimentId,
    required this.sprint,
    required this.runTimestamp,
    required this.runTimestampMs,
    required this.model,
    required this.modelPrecision,
    required this.annMethod,
    required this.presetName,
    required this.hyperparams,
    required this.datasetSize,
    required this.queryCount,
    required this.queryLanguageLabel,
    required this.topKResults,
    required this.recallAtK,
    required this.meanAveragePrecision,
    required this.latencyMedianMs,
    required this.latencyP95Ms,
    required this.buildTimeMs,
    required this.peakRamBytes,
    required this.lmkIncidentFlag,
    required this.deviceRamMb,
    required this.deviceSoC,
    required this.deviceOs,
  });

  Map<String, dynamic> toJson() => {
        'experiment_id': experimentId,
        'sprint': sprint,
        'run_timestamp': runTimestamp,
        'run_timestamp_ms': runTimestampMs,
        'model': model,
        'model_precision': modelPrecision,
        'ann_method': annMethod,
        'preset_name': presetName,
        'hyperparams': hyperparams,
        'dataset_size': datasetSize,
        'query_count': queryCount,
        'query_language_label': queryLanguageLabel,
        'top_k_results': topKResults,
        'recall_at_k': recallAtK,
        'mean_average_precision': meanAveragePrecision,
        'latency_median_ms': latencyMedianMs,
        'latency_p95_ms': latencyP95Ms,
        'build_time_ms': buildTimeMs,
        'peak_ram_bytes': peakRamBytes,
        'lmk_incident_flag': lmkIncidentFlag,
        'device_ram_mb': deviceRamMb,
        'device_soc': deviceSoC,
        'device_os': deviceOs,
      };

  /// Ordered CSV header matching toCsvRow()
  static String csvHeader() =>
      'experiment_id,sprint,run_timestamp,model,model_precision,'
      'ann_method,preset_name,dataset_size,query_count,query_language_label,'
      'recall@1,recall@5,recall@10,recall@20,mean_ap,'
      'latency_median_ms,latency_p95_ms,build_time_ms,'
      'peak_ram_bytes,lmk_incident_flag,device_ram_mb,device_soc,device_os';

  String toCsvRow() {
    String r(int k) =>
        (recallAtK[k.toString()] ?? double.nan).toStringAsFixed(4);
    return [
      experimentId,
      sprint,
      runTimestamp,
      model,
      modelPrecision,
      annMethod,
      presetName,
      datasetSize,
      queryCount,
      queryLanguageLabel,
      r(1),
      r(5),
      r(10),
      r(20),
      meanAveragePrecision.toStringAsFixed(4),
      latencyMedianMs.toStringAsFixed(2),
      latencyP95Ms.toStringAsFixed(2),
      buildTimeMs,
      peakRamBytes,
      lmkIncidentFlag ? '1' : '0',
      deviceRamMb,
      '"$deviceSoC"',
      '"$deviceOs"',
    ].join(',');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 3. LOG VALIDATOR
// ═══════════════════════════════════════════════════════════════════════════

class ValidationIssue {
  final String experimentId;
  final String field;
  final String message;
  const ValidationIssue(this.experimentId, this.field, this.message);

  @override
  String toString() => '[$experimentId] $field: $message';
}

class LogValidator {
  static const _requiredTopLevelFields = [
    'experiment_id',
    'sprint',
    'run_timestamp',
    'run_timestamp_ms',
    'model',
    'model_precision',
    'ann_method',
    'preset_name',
    'hyperparams',
    'dataset_size',
    'query_count',
    'query_language_label',
    'top_k_results',
    'recall_at_k',
    'mean_average_precision',
    'latency_median_ms',
    'latency_p95_ms',
    'build_time_ms',
    'peak_ram_bytes',
    'lmk_incident_flag',
    'device_ram_mb',
    'device_soc',
    'device_os',
  ];

  static const _validAnnMethods = {'hnsw', 'ivfpq'};
  static const _validModels = {
    'kitako_mixed',
    'kitako_int8',
    'siglip2_baseline',
    'proxy_synthetic',
  };
  static const _validLanguages = {'en', 'tl', 'taglish', 'synthetic'};
  static const _validPrecisions = {'fp32', 'int8', 'mixed', 'synthetic'};
  static const _recallKs = ['1', '5', '10', '20'];

  /// Validates a list of raw JSON records.
  /// Returns the list of issues found (empty = valid).
  List<ValidationIssue> validate(List<Map<String, dynamic>> records) {
    final issues = <ValidationIssue>[];
    final seenIds = <String>{};

    for (final record in records) {
      final id = record['experiment_id']?.toString() ?? '<missing>';

      // Duplicate ID check
      if (!seenIds.add(id)) {
        issues.add(ValidationIssue(id, 'experiment_id', 'Duplicate ID — experiment IDs must be unique per run'));
      }

      // Missing required fields
      for (final field in _requiredTopLevelFields) {
        if (!record.containsKey(field) || record[field] == null) {
          issues.add(ValidationIssue(id, field, 'Missing or null required field'));
        }
      }

      // Enum validation
      _checkEnum(issues, id, record, 'ann_method', _validAnnMethods);
      _checkEnum(issues, id, record, 'model', _validModels);
      _checkEnum(issues, id, record, 'query_language_label', _validLanguages);
      _checkEnum(issues, id, record, 'model_precision', _validPrecisions);

      // recall_at_k completeness
      final rak = record['recall_at_k'];
      if (rak is Map) {
        for (final k in _recallKs) {
          if (!rak.containsKey(k)) {
            issues.add(ValidationIssue(id, 'recall_at_k', 'Missing key "$k"'));
          }
        }
      } else if (rak != null) {
        issues.add(ValidationIssue(id, 'recall_at_k', 'Must be a JSON object'));
      }

      // Positive numeric sanity checks
      _checkPositive(issues, id, record, 'dataset_size');
      _checkPositive(issues, id, record, 'query_count');
      _checkPositive(issues, id, record, 'latency_median_ms');
      _checkPositive(issues, id, record, 'build_time_ms');

      // Timestamp format
      final ts = record['run_timestamp']?.toString() ?? '';
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}').hasMatch(ts)) {
        issues.add(ValidationIssue(id, 'run_timestamp', 'Expected ISO-8601 format'));
      }
    }

    return issues;
  }

  void _checkEnum(
    List<ValidationIssue> issues,
    String id,
    Map<String, dynamic> r,
    String field,
    Set<String> valid,
  ) {
    final v = r[field]?.toString();
    if (v != null && !valid.contains(v)) {
      issues.add(ValidationIssue(
        id,
        field,
        'Unknown value "$v"; expected one of: ${valid.join(", ")}',
      ));
    }
  }

  void _checkPositive(
    List<ValidationIssue> issues,
    String id,
    Map<String, dynamic> r,
    String field,
  ) {
    final v = r[field];
    if (v != null && (v is num) && v <= 0) {
      issues.add(ValidationIssue(id, field, 'Expected positive number, got $v'));
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 4. PROXY DATASET
// ═══════════════════════════════════════════════════════════════════════════

class ProxyDataset {
  final List<Float32List> indexVectors;
  final List<Float32List> queryVectors;

  /// groundTruth[q] = ordered list of (id, dot-product) pairs, exact top-K
  final List<List<({int id, double score})>> groundTruth;

  ProxyDataset({
    required this.indexVectors,
    required this.queryVectors,
    required this.groundTruth,
  });

  int get indexSize => indexVectors.length;
  int get queryCount => queryVectors.length;

  /// Generates a proxy dataset of [n] index vectors and [q] query vectors,
  /// each of dimension [dim], normalized to the unit sphere.
  /// [maxK] controls how many ground-truth neighbours are precomputed.
  static ProxyDataset generate({
    required int n,
    required int q,
    required int dim,
    int maxK = 20,
    int seed = 42,
  }) {
    final rng = Random(seed);
    stdout.write('  Generating $n index vectors (dim=$dim) ...');
    final index = List.generate(n, (_) => _randomUnitVector(rng, dim));
    stdout.writeln(' done');

    stdout.write('  Generating $q query vectors ...');
    final queries = List.generate(q, (_) => _randomUnitVector(rng, dim));
    stdout.writeln(' done');

    stdout.write('  Computing brute-force ground truth (top-$maxK per query) ...');
    final gt = _bruteForceGroundTruth(index, queries, maxK);
    stdout.writeln(' done');

    return ProxyDataset(
      indexVectors: index,
      queryVectors: queries,
      groundTruth: gt,
    );
  }

  static Float32List _randomUnitVector(Random rng, int dim) {
    final v = Float32List(dim);
    double norm = 0;
    for (int i = 0; i < dim; i++) {
      // Box–Muller gives normally distributed values
      final u1 = rng.nextDouble() + 1e-10;
      final u2 = rng.nextDouble();
      v[i] = sqrt(-2.0 * log(u1)) * cos(2 * pi * u2);
      norm += v[i] * v[i];
    }
    norm = sqrt(norm);
    for (int i = 0; i < dim; i++) {
      v[i] /= norm;
    }
    return v;
  }

  /// Returns, for each query, the top-[k] index-vector IDs sorted by
  /// descending dot product (inner product = cosine for unit vectors).
  static List<List<({int id, double score})>> _bruteForceGroundTruth(
    List<Float32List> index,
    List<Float32List> queries,
    int k,
  ) {
    final result = <List<({int id, double score})>>[];
    for (int qi = 0; qi < queries.length; qi++) {
      final q = queries[qi];
      final dim = q.length;

      // Compute dot products with all index vectors
      final scores = List.generate(index.length, (i) {
        double dot = 0;
        final v = index[i];
        for (int d = 0; d < dim; d++) {
          dot += q[d] * v[d];
        }
        return (id: i, score: dot);
      });

      scores.sort((a, b) => b.score.compareTo(a.score));
      result.add(scores.take(k).toList());

      if ((qi + 1) % (queries.length ~/ 5).clamp(1, 9999) == 0) {
        stdout.write('.');
      }
    }
    return result;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 5. METRICS COMPUTER
// ═══════════════════════════════════════════════════════════════════════════

class QueryMetrics {
  final Map<int, double> recallAtK; // k → recall value
  final double averagePrecision;
  final double latencyMs;

  const QueryMetrics({
    required this.recallAtK,
    required this.averagePrecision,
    required this.latencyMs,
  });
}

class AggregateMetrics {
  final Map<String, double> recallAtK; // '1','5','10','20' → mean recall
  final double meanAveragePrecision;
  final double latencyMedianMs;
  final double latencyP95Ms;

  const AggregateMetrics({
    required this.recallAtK,
    required this.meanAveragePrecision,
    required this.latencyMedianMs,
    required this.latencyP95Ms,
  });
}

class MetricsComputer {
  static const _ks = [1, 5, 10, 20];

  /// Computes per-query metrics given ANN results and ground truth.
  static QueryMetrics computeQuery({
    required List<AnnSearchResult> annResults,
    required List<({int id, double score})> groundTruth,
    required double latencyMs,
  }) {
    final gtIds = groundTruth.map((e) => e.id).toSet();
    final annIds = annResults.map((r) => r.id).toList();

    final recallAtK = <int, double>{};
    for (final k in _ks) {
      if (k > annIds.length || k > groundTruth.length) {
        recallAtK[k] = double.nan;
        continue;
      }
      final retrieved = annIds.take(k).toSet();
      final relevant = gtIds.take(k).toSet();
      recallAtK[k] = retrieved.intersection(relevant).length / k;
    }

    // AP: iterate over returned results, count relevant hits
    double ap = 0;
    int hits = 0;
    final relLimit = groundTruth.length;
    for (int i = 0; i < annIds.length; i++) {
      if (i >= relLimit) break;
      if (gtIds.contains(annIds[i])) {
        hits++;
        ap += hits / (i + 1);
      }
    }
    ap = relLimit > 0 ? ap / relLimit : 0;

    return QueryMetrics(
      recallAtK: recallAtK,
      averagePrecision: ap,
      latencyMs: latencyMs,
    );
  }

  /// Aggregates per-query metrics into run-level statistics.
  static AggregateMetrics aggregate(List<QueryMetrics> queryMetrics) {
    final recallSums = <int, double>{for (final k in _ks) k: 0};
    double apSum = 0;
    final latencies = <double>[];

    for (final qm in queryMetrics) {
      for (final k in _ks) {
        final v = qm.recallAtK[k];
        if (v != null && !v.isNaN) recallSums[k] = recallSums[k]! + v;
      }
      apSum += qm.averagePrecision;
      latencies.add(qm.latencyMs);
    }

    final n = queryMetrics.length.toDouble();
    latencies.sort();

    double percentile(List<double> sorted, double p) {
      if (sorted.isEmpty) return 0;
      final idx = ((sorted.length - 1) * p).round();
      return sorted[idx];
    }

    return AggregateMetrics(
      recallAtK: {
        for (final k in _ks) k.toString(): recallSums[k]! / n,
      },
      meanAveragePrecision: apSum / n,
      latencyMedianMs: percentile(latencies, 0.50),
      latencyP95Ms: percentile(latencies, 0.95),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 6. EXPERIMENT RUNNER
// ═══════════════════════════════════════════════════════════════════════════

/// Generates a short unique run ID: timestamp + random suffix.
String _generateRunId() {
  final now = DateTime.now();
  final ts = '${now.year}${_pad(now.month)}${_pad(now.day)}'
      '_${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
  final suffix = Random().nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
  return 'run_${ts}_$suffix';
}

String _generateExperimentId(String runId, String presetName) {
  final suffix = Random().nextInt(0xFFFFF).toRadixString(16).padLeft(5, '0');
  return '${runId}__${presetName}__$suffix';
}

String _pad(int n) => n.toString().padLeft(2, '0');

/// Collects host device info for desktop runs (Android fields are N/A).
Map<String, dynamic> _hostDeviceInfo() {
  final os = Platform.operatingSystem;
  final osVer = Platform.operatingSystemVersion;
  // Total physical RAM is not available from pure Dart without FFI;
  // use maxRss as a proxy for the session working set.
  final approxRamMb = ProcessInfo.maxRss ~/ (1024 * 1024);
  return {
    'deviceRamMb': approxRamMb,
    'deviceSoC': 'N/A (desktop)',
    'deviceOs': '$os $osVer',
  };
}

/// Runs a single HNSW preset experiment.  Returns null if the native library
/// is not available on this platform.
Future<ExperimentRecord?> _runHnsw({
  required String runId,
  required HnswPreset preset,
  required ProxyDataset dataset,
  required Map<String, dynamic> deviceInfo,
  required int topK,
}) async {
  final label = 'HNSW/${preset.name}';
  print('  [$label] building index (n=${dataset.indexSize}) ...');

  final config = HnswConfig(
    dimension: 768,
    metric: DistanceMetric.innerProduct,
    m: preset.m,
    efConstruction: preset.efConstruction,
    efSearch: preset.efSearch,
    maxElements: dataset.indexSize + 64,
  );

  final index = HnswAnnIndex(config: config);

  // --- Build ---
  final buildStart = DateTime.now();
  int peakRam = ProcessInfo.currentRss;
  try {
    await index.initialize();
    await index.addVectors(dataset.indexVectors, List.generate(dataset.indexSize, (i) => i));
  } on AnnIndexException catch (e) {
    print('  [$label] SKIP — HNSW native library not available: $e');
    index.dispose();
    return null;
  }
  final buildMs = DateTime.now().difference(buildStart).inMilliseconds;
  peakRam = max(peakRam, ProcessInfo.currentRss);

  print('  [$label] index built in ${buildMs}ms — running ${dataset.queryCount} queries ...');

  // --- Search ---
  final queryMetrics = <QueryMetrics>[];
  List<AnnSearchResult>? lastResults;
  for (int qi = 0; qi < dataset.queryCount; qi++) {
    final qStart = DateTime.now();
    final results = await index.search(dataset.queryVectors[qi], topK);
    final qMs = DateTime.now().difference(qStart).inMicroseconds / 1000.0;

    final qm = MetricsComputer.computeQuery(
      annResults: results,
      groundTruth: dataset.groundTruth[qi].take(topK).toList(),
      latencyMs: qMs,
    );
    queryMetrics.add(qm);
    lastResults = results;
    peakRam = max(peakRam, ProcessInfo.currentRss);
  }

  index.dispose();
  final agg = MetricsComputer.aggregate(queryMetrics);
  final now = DateTime.now();
  final experimentId = _generateExperimentId(runId, preset.name);

  print('  [$label] Recall@10=${agg.recallAtK["10"]?.toStringAsFixed(3)} '
      'mAP=${agg.meanAveragePrecision.toStringAsFixed(3)} '
      'lat_med=${agg.latencyMedianMs.toStringAsFixed(1)}ms');

  return ExperimentRecord(
    experimentId: experimentId,
    sprint: 'sprint8',
    runTimestamp: now.toIso8601String(),
    runTimestampMs: now.millisecondsSinceEpoch,
    model: 'proxy_synthetic',
    modelPrecision: 'synthetic',
    annMethod: 'hnsw',
    presetName: preset.name,
    hyperparams: preset.toMap(),
    datasetSize: dataset.indexSize,
    queryCount: dataset.queryCount,
    queryLanguageLabel: 'synthetic',
    topKResults: (lastResults ?? [])
        .asMap()
        .entries
        .map((e) => {'rank': e.key + 1, 'id': e.value.id, 'distance': e.value.distance})
        .toList(),
    recallAtK: agg.recallAtK,
    meanAveragePrecision: agg.meanAveragePrecision,
    latencyMedianMs: agg.latencyMedianMs,
    latencyP95Ms: agg.latencyP95Ms,
    buildTimeMs: buildMs,
    peakRamBytes: peakRam,
    lmkIncidentFlag: false,
    deviceRamMb: deviceInfo['deviceRamMb'] as int,
    deviceSoC: deviceInfo['deviceSoC'] as String,
    deviceOs: deviceInfo['deviceOs'] as String,
  );
}

/// Runs a single IVF-PQ preset experiment.
Future<ExperimentRecord> _runIvfPq({
  required String runId,
  required IvfPqPreset preset,
  required ProxyDataset dataset,
  required Map<String, dynamic> deviceInfo,
  required int topK,
}) async {
  final label = 'IVF-PQ/${preset.name}';
  print('  [$label] training + building index (n=${dataset.indexSize}) ...');

  final config = IvfPqConfig(
    dimension: 768,
    metric: DistanceMetric.innerProduct,
    numClusters: preset.nlist,
    numSubquantizers: preset.m,
    numCentroidsPerSubquantizer: preset.numCentroids,
    numProbes: preset.nprobe,
    trainingIterations: 20,
  );

  final index = IvfPqAnnIndex(config: config);

  // --- Train + Build ---
  final buildStart = DateTime.now();
  int peakRam = ProcessInfo.currentRss;

  await index.train(dataset.indexVectors, seed: 42);
  await index.addVectors(dataset.indexVectors, List.generate(dataset.indexSize, (i) => i));

  final buildMs = DateTime.now().difference(buildStart).inMilliseconds;
  peakRam = max(peakRam, ProcessInfo.currentRss);

  print('  [$label] index ready in ${buildMs}ms — running ${dataset.queryCount} queries ...');

  // --- Search ---
  final queryMetrics = <QueryMetrics>[];
  List<AnnSearchResult>? lastResults;
  for (int qi = 0; qi < dataset.queryCount; qi++) {
    final qStart = DateTime.now();
    final results = await index.search(dataset.queryVectors[qi], topK);
    final qMs = DateTime.now().difference(qStart).inMicroseconds / 1000.0;

    final qm = MetricsComputer.computeQuery(
      annResults: results,
      groundTruth: dataset.groundTruth[qi].take(topK).toList(),
      latencyMs: qMs,
    );
    queryMetrics.add(qm);
    lastResults = results;
    peakRam = max(peakRam, ProcessInfo.currentRss);
  }

  index.dispose();
  final agg = MetricsComputer.aggregate(queryMetrics);
  final now = DateTime.now();
  final experimentId = _generateExperimentId(runId, preset.name);

  print('  [$label] Recall@10=${agg.recallAtK["10"]?.toStringAsFixed(3)} '
      'mAP=${agg.meanAveragePrecision.toStringAsFixed(3)} '
      'lat_med=${agg.latencyMedianMs.toStringAsFixed(1)}ms');

  return ExperimentRecord(
    experimentId: experimentId,
    sprint: 'sprint8',
    runTimestamp: now.toIso8601String(),
    runTimestampMs: now.millisecondsSinceEpoch,
    model: 'proxy_synthetic',
    modelPrecision: 'synthetic',
    annMethod: 'ivfpq',
    presetName: preset.name,
    hyperparams: preset.toMap(),
    datasetSize: dataset.indexSize,
    queryCount: dataset.queryCount,
    queryLanguageLabel: 'synthetic',
    topKResults: (lastResults ?? [])
        .asMap()
        .entries
        .map((e) => {'rank': e.key + 1, 'id': e.value.id, 'distance': e.value.distance})
        .toList(),
    recallAtK: agg.recallAtK,
    meanAveragePrecision: agg.meanAveragePrecision,
    latencyMedianMs: agg.latencyMedianMs,
    latencyP95Ms: agg.latencyP95Ms,
    buildTimeMs: buildMs,
    peakRamBytes: peakRam,
    lmkIncidentFlag: false,
    deviceRamMb: deviceInfo['deviceRamMb'] as int,
    deviceSoC: deviceInfo['deviceSoC'] as String,
    deviceOs: deviceInfo['deviceOs'] as String,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// 7. RESULTS WRITER
// ═══════════════════════════════════════════════════════════════════════════

class ResultsWriter {
  final String outDir; // e.g. results/sprint8/run_20250308_123456_abcd

  ResultsWriter(this.outDir);

  void ensureDir() => Directory(outDir).createSync(recursive: true);

  void writeJson(List<ExperimentRecord> records) {
    final path = '$outDir/experiment_log.json';
    final json = jsonEncode(records.map((r) => r.toJson()).toList());
    File(path).writeAsStringSync(json);
    print('  Wrote JSON log  → $path');
  }

  void writeCsv(List<ExperimentRecord> records) {
    final path = '$outDir/experiment_log.csv';
    final buf = StringBuffer();
    buf.writeln(ExperimentRecord.csvHeader());
    for (final r in records) {
      buf.writeln(r.toCsvRow());
    }
    File(path).writeAsStringSync(buf.toString());
    print('  Wrote CSV log   → $path');
  }

  void writeValidationReport(List<ValidationIssue> issues) {
    final path = '$outDir/validation_report.txt';
    final buf = StringBuffer();
    buf.writeln('Log Validation Report — ${DateTime.now().toIso8601String()}');
    buf.writeln('=' * 60);
    if (issues.isEmpty) {
      buf.writeln('PASS: All records are valid (0 issues found).');
    } else {
      buf.writeln('FAIL: ${issues.length} issue(s) found:\n');
      for (final issue in issues) {
        buf.writeln('  $issue');
      }
    }
    File(path).writeAsStringSync(buf.toString());
    print('  Wrote validation → $path  [${issues.isEmpty ? "PASS" : "FAIL: ${issues.length} issues"}]');
  }

  void writeRecallTable(List<ExperimentRecord> records) {
    final path = '$outDir/recall_table.csv';
    final buf = StringBuffer();
    buf.writeln('preset,ann_method,Recall@1,Recall@5,Recall@10,Recall@20,mAP');
    for (final r in records) {
      final rak = r.recallAtK;
      buf.writeln([
        r.presetName,
        r.annMethod,
        rak['1']?.toStringAsFixed(4) ?? 'NaN',
        rak['5']?.toStringAsFixed(4) ?? 'NaN',
        rak['10']?.toStringAsFixed(4) ?? 'NaN',
        rak['20']?.toStringAsFixed(4) ?? 'NaN',
        r.meanAveragePrecision.toStringAsFixed(4),
      ].join(','));
    }
    File(path).writeAsStringSync(buf.toString());
    print('  Wrote recall    → $path');
  }

  void writeLatencyTable(List<ExperimentRecord> records) {
    final path = '$outDir/latency_table.csv';
    final buf = StringBuffer();
    buf.writeln('preset,ann_method,latency_median_ms,latency_p95_ms,build_time_ms,peak_ram_mb,lmk_rate');
    for (final r in records) {
      buf.writeln([
        r.presetName,
        r.annMethod,
        r.latencyMedianMs.toStringAsFixed(2),
        r.latencyP95Ms.toStringAsFixed(2),
        r.buildTimeMs,
        (r.peakRamBytes / (1024 * 1024)).toStringAsFixed(1),
        r.lmkIncidentFlag ? '1.0' : '0.0',
      ].join(','));
    }
    File(path).writeAsStringSync(buf.toString());
    print('  Wrote latency   → $path');
  }

  void writeSummaryMarkdown(List<ExperimentRecord> records, String runId) {
    final path = '$outDir/summary.md';
    final buf = StringBuffer();
    buf.writeln('# ANN Benchmark Summary — Sprint 8');
    buf.writeln();
    buf.writeln('**Run ID:** `$runId`  ');
    buf.writeln('**Generated:** ${DateTime.now().toIso8601String()}  ');
    if (records.isNotEmpty) {
      final d = records.first;
      buf.writeln('**Device:** ${d.deviceOs} / ${d.deviceSoC}  ');
      buf.writeln('**Dataset:** ${d.datasetSize} vectors × ${d.queryCount} queries (proxy_synthetic)  ');
    }
    buf.writeln();
    buf.writeln('## Recall @ K');
    buf.writeln();
    buf.writeln('| Preset | Method | R@1 | R@5 | R@10 | R@20 | mAP |');
    buf.writeln('|--------|--------|-----|-----|------|------|-----|');
    for (final r in records) {
      final rak = r.recallAtK;
      buf.writeln('| ${r.presetName} | ${r.annMethod.toUpperCase()} '
          '| ${_fmt(rak["1"])} | ${_fmt(rak["5"])} '
          '| ${_fmt(rak["10"])} | ${_fmt(rak["20"])} '
          '| ${_fmt(r.meanAveragePrecision)} |');
    }
    buf.writeln();
    buf.writeln('## Latency & Memory');
    buf.writeln();
    buf.writeln('| Preset | Method | Lat. Median (ms) | Lat. P95 (ms) | Build (ms) | Peak RAM (MB) | LMK Rate |');
    buf.writeln('|--------|--------|-----------------|---------------|------------|---------------|----------|');
    for (final r in records) {
      buf.writeln('| ${r.presetName} | ${r.annMethod.toUpperCase()} '
          '| ${r.latencyMedianMs.toStringAsFixed(2)} '
          '| ${r.latencyP95Ms.toStringAsFixed(2)} '
          '| ${r.buildTimeMs} '
          '| ${(r.peakRamBytes / (1024 * 1024)).toStringAsFixed(1)} '
          '| ${r.lmkIncidentFlag ? "YES" : "—"} |');
    }
    buf.writeln();
    buf.writeln('## Hyperparameters Used (locked presets)');
    buf.writeln();
    buf.writeln('| Preset | Params |');
    buf.writeln('|--------|--------|');
    for (final r in records) {
      final hp = r.hyperparams.entries.map((e) => '${e.key}=${e.value}').join(', ');
      buf.writeln('| ${r.presetName} | `$hp` |');
    }
    buf.writeln();
    buf.writeln('---');
    buf.writeln('*Generated by `tools/bench_ann.dart`*');
    File(path).writeAsStringSync(buf.toString());
    print('  Wrote summary   → $path');
  }

  String _fmt(double? v) =>
      v == null || v.isNaN ? 'N/A' : v.toStringAsFixed(3);
}

// ═══════════════════════════════════════════════════════════════════════════
// 8. CLI ARGUMENT PARSING
// ═══════════════════════════════════════════════════════════════════════════

class BenchConfig {
  final int n; // index vector count
  final int q; // query count
  final int topK; // search top-K
  final Set<String> algos; // 'hnsw', 'ivfpq', or both
  final Set<PresetTier> tiers; // which preset tiers to run
  final String outBase; // root output directory
  final bool validateOnly;
  final String? validatePath;

  const BenchConfig({
    required this.n,
    required this.q,
    required this.topK,
    required this.algos,
    required this.tiers,
    required this.outBase,
    required this.validateOnly,
    required this.validatePath,
  });
}

BenchConfig? _parseArgs(List<String> args) {
  int n = 5000;
  int q = 50;
  int topK = 20;
  final algos = <String>{'hnsw', 'ivfpq'};
  final tiers = <PresetTier>{...PresetTier.values};
  String outBase = 'results/sprint8';
  bool validateOnly = false;
  String? validatePath;

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--n':
        if (i + 1 < args.length) n = int.parse(args[++i]);
        break;
      case '--queries':
      case '--q':
        if (i + 1 < args.length) q = int.parse(args[++i]);
        break;
      case '--k':
        if (i + 1 < args.length) topK = int.parse(args[++i]);
        break;
      case '--algo':
        if (i + 1 < args.length) {
          algos.clear();
          algos.addAll(args[++i].split(',').map((s) => s.trim()));
        }
        break;
      case '--preset':
        if (i + 1 < args.length) {
          tiers.clear();
          for (final name in args[++i].split(',').map((s) => s.trim())) {
            final t = PresetTier.values.where((t) => t.name == name).firstOrNull;
            if (t != null) tiers.add(t);
          }
        }
        break;
      case '--out':
        if (i + 1 < args.length) outBase = args[++i];
        break;
      case '--validate':
        validateOnly = true;
        if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
          validatePath = args[++i];
        }
        break;
      case '--help':
      case '-h':
        _printUsage();
        return null;
    }
  }

  return BenchConfig(
    n: n,
    q: q,
    topK: topK,
    algos: algos,
    tiers: tiers,
    outBase: outBase,
    validateOnly: validateOnly,
    validatePath: validatePath,
  );
}

void _printUsage() {
  print('''
Usage: dart run tools/bench_ann.dart [options]

Options:
  --n <int>              Number of proxy index vectors (default: 5000)
  --q <int>              Number of query vectors      (default: 50)
  --k <int>              Top-K for search             (default: 20)
  --algo <csv>           Algorithms to run: hnsw,ivfpq (default: both)
  --preset <csv>         Preset tiers: low,balanced,high (default: all)
  --out <dir>            Base output dir (default: results/sprint8)
  --validate [path]      Validate an existing experiment_log.json
  --help, -h             Show this help

Examples:
  dart run tools/bench_ann.dart
  dart run tools/bench_ann.dart --n 2000 --q 30 --algo ivfpq --preset balanced,high
  dart run tools/bench_ann.dart --validate results/sprint8/run_xyz/experiment_log.json
''');
}

// ═══════════════════════════════════════════════════════════════════════════
// 9. VALIDATE-ONLY MODE
// ═══════════════════════════════════════════════════════════════════════════

Future<void> _runValidateOnly(String? path) async {
  final filePath = path ?? _findLatestLog('results/sprint8');
  if (filePath == null) {
    print('ERROR: No experiment_log.json found. '
        'Run a benchmark first or pass --validate <path>.');
    exit(1);
  }

  print('Validating: $filePath');
  final raw = File(filePath).readAsStringSync();
  final List<dynamic> parsed = jsonDecode(raw);
  final records = parsed.cast<Map<String, dynamic>>();

  final issues = LogValidator().validate(records);
  print('  Records  : ${records.length}');
  print('  Issues   : ${issues.length}');
  if (issues.isEmpty) {
    print('  Result   : PASS');
  } else {
    print('  Result   : FAIL');
    for (final issue in issues) {
      print('    $issue');
    }
    exit(2);
  }
}

String? _findLatestLog(String base) {
  final dir = Directory(base);
  if (!dir.existsSync()) return null;
  final logs = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('experiment_log.json'))
      .toList();
  if (logs.isEmpty) return null;
  logs.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  return logs.first.path;
}

// ═══════════════════════════════════════════════════════════════════════════
// 10. MAIN
// ═══════════════════════════════════════════════════════════════════════════

Future<void> main(List<String> args) async {
  print('╔══════════════════════════════════════════════════════════╗');
  print('║         KitaKo ANN Benchmark — Sprint 8                  ║');
  print('╚══════════════════════════════════════════════════════════╝');
  print('');

  final config = _parseArgs(args);
  if (config == null) exit(0);

  // --- Validate-only shortcut ---
  if (config.validateOnly) {
    await _runValidateOnly(config.validatePath);
    return;
  }

  // --- Device info ---
  final deviceInfo = _hostDeviceInfo();
  print('Device : ${deviceInfo["deviceOs"]}');
  print('Max RSS: ${(ProcessInfo.maxRss / (1024 * 1024)).toStringAsFixed(0)} MB (session so far)');
  print('');

  // --- Proxy dataset ---
  print('Generating proxy dataset (n=${config.n}, q=${config.q}, dim=768) ...');
  final dataset = ProxyDataset.generate(
    n: config.n,
    q: config.q,
    dim: 768,
    maxK: config.topK,
  );
  print('');

  // --- Run experiments ---
  final runId = _generateRunId();
  print('Run ID : $runId');
  print('');

  final records = <ExperimentRecord>[];

  // HNSW
  if (config.algos.contains('hnsw')) {
    print('─── HNSW experiments ───────────────────────────────────────');
    for (final tier in PresetTier.values) {
      if (!config.tiers.contains(tier)) continue;
      final preset = BenchPresets.hnsw[tier]!;
      final record = await _runHnsw(
        runId: runId,
        preset: preset,
        dataset: dataset,
        deviceInfo: deviceInfo,
        topK: config.topK,
      );
      if (record != null) records.add(record);
    }
    print('');
  }

  // IVF-PQ
  if (config.algos.contains('ivfpq')) {
    print('─── IVF-PQ experiments ─────────────────────────────────────');
    for (final tier in PresetTier.values) {
      if (!config.tiers.contains(tier)) continue;
      final preset = BenchPresets.ivfpq[tier]!;
      try {
        final record = await _runIvfPq(
          runId: runId,
          preset: preset,
          dataset: dataset,
          deviceInfo: deviceInfo,
          topK: config.topK,
        );
        records.add(record);
      } catch (e) {
        print('  [IVF-PQ/${preset.name}] FAILED: $e');
      }
    }
    print('');
  }

  if (records.isEmpty) {
    print('WARNING: No experiments completed — nothing to write.');
    exit(1);
  }

  // --- Validate ---
  print('─── Validating logs ────────────────────────────────────────');
  final jsonRecords = records.map((r) => r.toJson()).toList();
  final issues = LogValidator().validate(jsonRecords);
  print('  ${records.length} records — ${issues.isEmpty ? "PASS (0 issues)" : "FAIL (${issues.length} issues)"}');
  print('');

  // --- Write results ---
  final outDir = '${config.outBase}/$runId';
  print('─── Writing results → $outDir ');
  final writer = ResultsWriter(outDir);
  writer.ensureDir();
  writer.writeJson(records);
  writer.writeCsv(records);
  writer.writeValidationReport(issues);
  writer.writeRecallTable(records);
  writer.writeLatencyTable(records);
  writer.writeSummaryMarkdown(records, runId);

  print('');
  print('╔══════════════════════════════════════════════════════════╗');
  print('║                  BENCHMARK COMPLETE                      ║');
  print('╚══════════════════════════════════════════════════════════╝');
  print('');
  print('Results: $outDir/');
  print('');

  if (issues.isNotEmpty) {
    print('WARNING: ${issues.length} validation issue(s) found — see validation_report.txt');
    exit(2);
  }
}
