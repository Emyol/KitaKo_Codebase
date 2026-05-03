import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

/// Thin wrapper over the Android MethodChannel exposed by MainActivity.
/// Falls back to ProcessInfo.currentRss + zeros on non-Android platforms so
/// the bench can still run in a smoke-test mode on desktop.
class BenchMemoryProbe {
  static const _channel = MethodChannel('kitako_app/bench');

  /// Returns process PSS in bytes. On non-Android, returns currentRss as a
  /// best-effort substitute.
  Future<int> pssBytes() async {
    if (!Platform.isAndroid) return ProcessInfo.currentRss;
    try {
      final v = await _channel.invokeMethod<int>('getPssBytes');
      return v ?? 0;
    } catch (_) {
      return ProcessInfo.currentRss;
    }
  }

  /// Returns a snapshot of cumulative trim counters: (count, maxLevel).
  /// On non-Android, returns (0, 0).
  Future<({int count, int maxLevel})> trimSnapshot() async {
    if (!Platform.isAndroid) return (count: 0, maxLevel: 0);
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('getTrimStats');
      return (
        count: (m?['count'] as num?)?.toInt() ?? 0,
        maxLevel: (m?['maxLevel'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return (count: 0, maxLevel: 0);
    }
  }
}

/// Polls PSS at a fixed interval while a search is running, tracking the
/// high-water mark. Start before the search, await it, then stop.
class PssWatermarkPoller {
  final BenchMemoryProbe probe;
  final Duration interval;
  Timer? _timer;
  int _maxBytes = 0;
  int _samples = 0;
  int _sumBytes = 0;

  PssWatermarkPoller(
    this.probe, {
    this.interval = const Duration(milliseconds: 100),
  });

  Future<void> start() async {
    _maxBytes = await probe.pssBytes();
    _samples = 1;
    _sumBytes = _maxBytes;
    _timer = Timer.periodic(interval, (_) async {
      final v = await probe.pssBytes();
      if (v > _maxBytes) _maxBytes = v;
      _samples += 1;
      _sumBytes += v;
    });
  }

  /// Stop polling. Returns peak bytes seen across all samples.
  int stop() {
    _timer?.cancel();
    _timer = null;
    return _maxBytes;
  }

  int get peakBytes => _maxBytes;
  double get meanBytes => _samples == 0 ? 0 : _sumBytes / _samples;
}
