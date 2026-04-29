import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Append-only crash log on disk. Survives restarts, rotates at ~1 MB.
///
/// Writes are serialized through an internal Future chain so concurrent
/// `log()` calls don't interleave or race the rotation step. The class
/// is a singleton — call [CrashLogger.instance.init] once from `main()`.
class CrashLogger {
  CrashLogger._();
  static final CrashLogger instance = CrashLogger._();

  static const _maxBytes = 1024 * 1024; // 1 MB before rotation

  File? _current; // <docs>/crash_log.txt
  File? _rotated; // <docs>/crash_log.1.txt
  Future<void> _writeChain = Future.value();
  bool _initialized = false;

  /// Resolves the log files. Safe to call multiple times — only the first
  /// invocation does work.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _current = File('${dir.path}/crash_log.txt');
      _rotated = File('${dir.path}/crash_log.1.txt');
      _initialized = true;
    } catch (e) {
      // Don't throw from init — a crash logger that crashes is worse than
      // no crash logger. Logging will silently no-op until init succeeds.
      debugPrint('CrashLogger: init failed: $e');
    }
  }

  /// Append a single entry to the log. `channel` is a short tag like
  /// "flutter", "platform", "zone", "ort", "ffi". `message` is optional
  /// extra context (e.g. the operation name that crashed).
  void log(
    String channel,
    Object error,
    StackTrace? stack, {
    String? message,
  }) {
    // Always echo to debug console — useful in dev, free in release.
    debugPrint('CrashLogger[$channel]: ${message ?? ""} $error');
    if (stack != null) debugPrint(stack.toString());

    if (!_initialized || _current == null) return;

    // Serialize disk writes through the chain so concurrent crashes
    // don't interleave half-written entries or trigger duplicate rotates.
    _writeChain = _writeChain.then((_) => _appendEntry(
          channel: channel,
          error: error,
          stack: stack,
          message: message,
        ));
  }

  Future<void> _appendEntry({
    required String channel,
    required Object error,
    required StackTrace? stack,
    required String? message,
  }) async {
    final file = _current;
    if (file == null) return;
    try {
      final ts = DateTime.now().toIso8601String();
      final buf = StringBuffer()
        ..writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
        ..writeln('[$ts] [$channel]${message != null ? " $message" : ""}')
        ..writeln(error.toString());
      if (stack != null) {
        buf.writeln(stack.toString());
      }
      await file.writeAsString(buf.toString(), mode: FileMode.append, flush: true);

      // Rotate after writing if we crossed the cap.
      final stat = await file.stat();
      if (stat.size > _maxBytes) {
        await _rotate();
      }
    } catch (e) {
      // Swallow disk-write failures. We're already in an error path.
      debugPrint('CrashLogger: write failed: $e');
    }
  }

  Future<void> _rotate() async {
    final cur = _current;
    final old = _rotated;
    if (cur == null || old == null) return;
    try {
      if (await old.exists()) {
        await old.delete();
      }
      await cur.rename(old.path);
    } catch (e) {
      debugPrint('CrashLogger: rotate failed: $e');
    }
  }

  /// Read the most recent ~N lines across both log files. Returns the
  /// concatenated tail (oldest first) suitable for sharing or display.
  Future<String> readRecent({int maxBytes = 64 * 1024}) async {
    if (!_initialized) return '';
    final cur = _current;
    final old = _rotated;
    final parts = <String>[];
    try {
      if (old != null && await old.exists()) {
        parts.add(await old.readAsString());
      }
      if (cur != null && await cur.exists()) {
        parts.add(await cur.readAsString());
      }
    } catch (e) {
      return 'CrashLogger: read failed: $e';
    }
    final all = parts.join();
    if (all.length <= maxBytes) return all;
    return '…(truncated)…\n${all.substring(all.length - maxBytes)}';
  }

  /// Wipe both log files. No-op if init failed.
  Future<void> clear() async {
    if (!_initialized) return;
    try {
      if (_current != null && await _current!.exists()) {
        await _current!.delete();
      }
      if (_rotated != null && await _rotated!.exists()) {
        await _rotated!.delete();
      }
    } catch (e) {
      debugPrint('CrashLogger: clear failed: $e');
    }
  }
}
