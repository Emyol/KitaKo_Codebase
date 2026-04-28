/// KitaKo Benchmark Log Validator
///
/// Standalone checker for experiment log files produced by bench_ann.dart.
/// Can be pointed at a single JSON file or a sprint results directory to
/// validate all logs found recursively.
///
/// Checks performed:
///   1. All required fields present and non-null
///   2. Enum fields contain only accepted values
///   3. Numeric fields within sane ranges
///   4. Recall@K has entries for K ∈ {1, 5, 10, 20}
///   5. Timestamps are ISO-8601 formatted
///   6. experiment_id is unique within each file
///   7. Preset name matches ann_method (no cross-contamination)
///   8. Hyperparams keys match expected set for the ann_method
///   9. CSV row count matches JSON record count (if both exist in same dir)
///  10. CSV header matches the expected canonical header
///
/// Exit codes:
///   0 — all checks passed
///   1 — usage error / file not found
///   2 — one or more validation failures
///
/// Usage:
///   dart run tools/bench_validate.dart <path>
///   dart run tools/bench_validate.dart results/sprint8/run_xyz/experiment_log.json
///   dart run tools/bench_validate.dart results/sprint8              # scans directory
library bench_validate;

import 'dart:convert';
import 'dart:io';

// ─────────────────────────────────────────────────────────────────────────────
// Schema constants (kept in sync with bench_ann.dart)
// ─────────────────────────────────────────────────────────────────────────────

const _requiredFields = [
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

const _validAnnMethods = {'hnsw', 'ivfpq'};
const _validModels = {
  'kitako_mixed',
  'kitako_int8',
  'siglip2_baseline',
  'proxy_synthetic',
};
const _validPrecisions = {'fp32', 'int8', 'mixed', 'synthetic'};
const _validLanguages = {'en', 'tl', 'taglish', 'synthetic'};
const _recallKs = ['1', '5', '10', '20'];

/// Expected hyperparameter key sets per ANN method.
const _expectedHyperparamKeys = {
  'hnsw': {'M', 'efConstruction', 'efSearch'},
  'ivfpq': {'nlist', 'nprobe', 'm', 'nbits', 'numCentroids'},
};

/// Preset names must start with the method they belong to.
const _presetPrefixes = {
  'hnsw': 'hnsw_',
  'ivfpq': 'ivfpq_',
};

const _canonicalCsvHeader =
    'experiment_id,sprint,run_timestamp,model,model_precision,'
    'ann_method,preset_name,dataset_size,query_count,query_language_label,'
    'recall@1,recall@5,recall@10,recall@20,mean_ap,'
    'latency_median_ms,latency_p95_ms,build_time_ms,'
    'peak_ram_bytes,lmk_incident_flag,device_ram_mb,device_soc,device_os';

// ─────────────────────────────────────────────────────────────────────────────
// Issue model
// ─────────────────────────────────────────────────────────────────────────────

enum IssueSeverity { warning, error }

class Issue {
  final IssueSeverity severity;
  final String experimentId;
  final String field;
  final String message;

  const Issue({
    required this.severity,
    required this.experimentId,
    required this.field,
    required this.message,
  });

  String get tag => severity == IssueSeverity.error ? 'ERROR' : 'WARN';

  @override
  String toString() => '[$tag] exp=$experimentId  field=$field  → $message';
}

// ─────────────────────────────────────────────────────────────────────────────
// Validator
// ─────────────────────────────────────────────────────────────────────────────

class BenchValidator {
  final List<Issue> _issues = [];

  List<Issue> get issues => List.unmodifiable(_issues);
  bool get passed => _issues.every((i) => i.severity != IssueSeverity.error);

  void _err(String id, String field, String msg) =>
      _issues.add(Issue(severity: IssueSeverity.error, experimentId: id, field: field, message: msg));

  void _warn(String id, String field, String msg) =>
      _issues.add(Issue(severity: IssueSeverity.warning, experimentId: id, field: field, message: msg));

  /// Validates a list of raw JSON records decoded from experiment_log.json.
  void validateRecords(List<Map<String, dynamic>> records) {
    final seenIds = <String>{};

    for (int idx = 0; idx < records.length; idx++) {
      final r = records[idx];
      final id = r['experiment_id']?.toString() ?? '#$idx';

      // ── 1. Unique experiment_id ──────────────────────────────────────────
      if (!seenIds.add(id)) {
        _err(id, 'experiment_id', 'Duplicate ID — every record must have a unique experiment_id');
      }

      // ── 2. Required fields ───────────────────────────────────────────────
      for (final field in _requiredFields) {
        if (!r.containsKey(field) || r[field] == null) {
          _err(id, field, 'Missing or null required field');
        }
      }

      // ── 3. Enum fields ───────────────────────────────────────────────────
      _checkEnum(id, r, 'ann_method', _validAnnMethods);
      _checkEnum(id, r, 'model', _validModels);
      _checkEnum(id, r, 'model_precision', _validPrecisions);
      _checkEnum(id, r, 'query_language_label', _validLanguages);

      // ── 4. Preset name matches ann_method ────────────────────────────────
      final method = r['ann_method']?.toString();
      final preset = r['preset_name']?.toString() ?? '';
      if (method != null && _presetPrefixes.containsKey(method)) {
        final expectedPrefix = _presetPrefixes[method]!;
        if (!preset.startsWith(expectedPrefix)) {
          _err(id, 'preset_name',
              'Preset "$preset" does not match ann_method "$method" '
              '(expected prefix "$expectedPrefix")');
        }
      }

      // ── 5. Hyperparameter keys ───────────────────────────────────────────
      final hp = r['hyperparams'];
      if (hp is Map && method != null && _expectedHyperparamKeys.containsKey(method)) {
        final expected = _expectedHyperparamKeys[method]!;
        final actual = hp.keys.cast<String>().toSet();
        final missing = expected.difference(actual);
        final extra = actual.difference(expected);
        if (missing.isNotEmpty) {
          _err(id, 'hyperparams', 'Missing keys: ${missing.join(", ")}');
        }
        if (extra.isNotEmpty) {
          _warn(id, 'hyperparams', 'Unexpected extra keys: ${extra.join(", ")}');
        }
      } else if (hp != null && hp is! Map) {
        _err(id, 'hyperparams', 'Must be a JSON object');
      }

      // ── 6. recall_at_k completeness ──────────────────────────────────────
      final rak = r['recall_at_k'];
      if (rak is Map) {
        for (final k in _recallKs) {
          if (!rak.containsKey(k)) {
            _err(id, 'recall_at_k', 'Missing required key "$k"');
          } else {
            final v = rak[k];
            if (v is! num) {
              _err(id, 'recall_at_k[$k]', 'Value must be numeric, got ${v.runtimeType}');
            } else if (v < 0 || v > 1) {
              _warn(id, 'recall_at_k[$k]', 'Value $v is outside [0, 1]');
            }
          }
        }
      } else if (rak != null) {
        _err(id, 'recall_at_k', 'Must be a JSON object');
      }

      // ── 7. Positive numeric checks ───────────────────────────────────────
      _checkPositive(id, r, 'dataset_size', minExclusive: true);
      _checkPositive(id, r, 'query_count', minExclusive: true);
      _checkPositive(id, r, 'latency_median_ms', minExclusive: true);
      _checkPositive(id, r, 'build_time_ms', minExclusive: false); // 0 allowed
      _checkPositive(id, r, 'peak_ram_bytes', minExclusive: false);

      // ── 8. mAP in [0, 1] ────────────────────────────────────────────────
      final mAP = r['mean_average_precision'];
      if (mAP is num && (mAP < 0 || mAP > 1)) {
        _warn(id, 'mean_average_precision', 'Value $mAP is outside [0, 1]');
      }

      // ── 9. p95 ≥ median ──────────────────────────────────────────────────
      final median = r['latency_median_ms'];
      final p95 = r['latency_p95_ms'];
      if (median is num && p95 is num && p95 < median) {
        _warn(id, 'latency_p95_ms', 'p95 ($p95 ms) is less than median ($median ms)');
      }

      // ── 10. Timestamp format ─────────────────────────────────────────────
      final ts = r['run_timestamp']?.toString() ?? '';
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}').hasMatch(ts)) {
        _err(id, 'run_timestamp', 'Must be ISO-8601 format (YYYY-MM-DDThh:mm:ss…), got "$ts"');
      }

      // ── 11. Boolean flag ─────────────────────────────────────────────────
      final lmk = r['lmk_incident_flag'];
      if (lmk != null && lmk is! bool) {
        _warn(id, 'lmk_incident_flag', 'Expected bool, got ${lmk.runtimeType}');
      }

      // ── 12. top_k_results is a list ──────────────────────────────────────
      final tkr = r['top_k_results'];
      if (tkr != null && tkr is! List) {
        _err(id, 'top_k_results', 'Must be a JSON array');
      }
    }
  }

  /// Validates a CSV file against the canonical header and checks that
  /// the record count matches [expectedCount].
  void validateCsv(File csvFile, int expectedCount) {
    if (!csvFile.existsSync()) {
      _warn('(file)', 'experiment_log.csv', 'CSV file not found alongside JSON log');
      return;
    }

    final lines = csvFile.readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) {
      _err('(csv)', 'header', 'CSV file is empty');
      return;
    }

    // Header check
    if (lines.first.trim() != _canonicalCsvHeader) {
      _err('(csv)', 'header',
          'CSV header mismatch.\n'
          '  Expected: $_canonicalCsvHeader\n'
          '  Got     : ${lines.first}');
    }

    // Row count (header line + data lines)
    final dataRows = lines.length - 1;
    if (dataRows != expectedCount) {
      _err('(csv)', 'row_count',
          'CSV has $dataRows data rows but JSON has $expectedCount records');
    }
  }

  void _checkEnum(String id, Map<String, dynamic> r, String field, Set<String> valid) {
    final v = r[field]?.toString();
    if (v != null && !valid.contains(v)) {
      _err(id, field, 'Unknown value "$v"; expected one of: ${valid.join(", ")}');
    }
  }

  void _checkPositive(
    String id,
    Map<String, dynamic> r,
    String field, {
    required bool minExclusive,
  }) {
    final v = r[field];
    if (v is num) {
      if (minExclusive && v <= 0) {
        _err(id, field, 'Expected positive value (>0), got $v');
      } else if (!minExclusive && v < 0) {
        _err(id, field, 'Expected non-negative value, got $v');
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// File scanning
// ─────────────────────────────────────────────────────────────────────────────

List<File> _findLogs(String path) {
  final target = FileSystemEntity.typeSync(path);
  if (target == FileSystemEntityType.file) {
    return [File(path)];
  } else if (target == FileSystemEntityType.directory) {
    return Directory(path)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('experiment_log.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }
  return [];
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  print('╔══════════════════════════════════════════════════════════╗');
  print('║       KitaKo Benchmark Log Validator                     ║');
  print('╚══════════════════════════════════════════════════════════╝');
  print('');

  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    print('Usage: dart run tools/bench_validate.dart <path>');
    print('');
    print('  <path> may be a single experiment_log.json file or a');
    print('  directory that will be scanned recursively.');
    print('');
    print('Exit codes: 0=pass  1=usage/not-found  2=validation failure');
    exit(args.isEmpty ? 1 : 0);
  }

  final target = args.first;
  final logFiles = _findLogs(target);

  if (logFiles.isEmpty) {
    print('ERROR: No experiment_log.json found at: $target');
    exit(1);
  }

  print('Found ${logFiles.length} log file(s) to validate.');
  print('');

  int totalErrors = 0;
  int totalWarnings = 0;
  int totalRecords = 0;

  for (final jsonFile in logFiles) {
    print('─── ${jsonFile.path}');

    // Parse JSON
    List<Map<String, dynamic>> records;
    try {
      final raw = jsonFile.readAsStringSync();
      final List<dynamic> parsed = jsonDecode(raw);
      records = parsed.cast<Map<String, dynamic>>();
    } catch (e) {
      print('  ERROR: Failed to parse JSON: $e');
      totalErrors++;
      continue;
    }

    print('  Records : ${records.length}');
    totalRecords += records.length;

    // Run validation
    final validator = BenchValidator();
    validator.validateRecords(records);

    // Also check the sibling CSV if it exists
    final csvFile = File(jsonFile.path.replaceAll('experiment_log.json', 'experiment_log.csv'));
    validator.validateCsv(csvFile, records.length);

    // Report
    final errors = validator.issues.where((i) => i.severity == IssueSeverity.error).length;
    final warnings = validator.issues.where((i) => i.severity == IssueSeverity.warning).length;
    totalErrors += errors;
    totalWarnings += warnings;

    if (validator.issues.isEmpty) {
      print('  Result  : PASS (no issues)');
    } else {
      print('  Result  : ${validator.passed ? "WARN" : "FAIL"} '
          '($errors error(s), $warnings warning(s))');
      for (final issue in validator.issues) {
        print('    $issue');
      }
    }
    print('');
  }

  // Summary
  print('═══════════════════════════════════════════════════════════');
  print('Summary : $totalRecords records across ${logFiles.length} file(s)');
  print('          $totalErrors error(s)   $totalWarnings warning(s)');
  print('Overall : ${totalErrors == 0 ? "PASS" : "FAIL"}');
  print('');

  exit(totalErrors > 0 ? 2 : 0);
}
