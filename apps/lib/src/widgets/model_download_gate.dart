import 'package:flutter/material.dart';
import '../services/model_download_service.dart';

/// Extracts bundled ONNX models to the app documents directory on first
/// launch, then renders [child].
///
/// On subsequent launches the files already exist in the documents directory,
/// so extraction is skipped instantly and [child] is shown immediately.
class ModelDownloadGate extends StatefulWidget {
  final Widget child;
  final bool autoDownload;

  const ModelDownloadGate({
    super.key,
    required this.child,
    this.autoDownload = true,
  });

  @override
  State<ModelDownloadGate> createState() => _ModelDownloadGateState();
}

class _ModelDownloadGateState extends State<ModelDownloadGate> {
  bool _ready = false;
  String _statusText = 'Preparing models…';
  int _done = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _extract();
  }

  Future<void> _extract() async {
    try {
      await ModelDownloadService().extractBundledModels(
        onProgress: (filename, done, total) {
          if (mounted) {
            setState(() {
              _done = done;
              _total = total;
              _statusText = done < total
                  ? 'Extracting models ($done/$total)…'
                  : 'Models ready';
            });
          }
        },
      );
    } catch (e) {
      debugPrint('ModelDownloadGate: extraction failed: $e');
      // Non-fatal — model loading will fail later with a clear error.
    }

    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Color(0xFF4A90E2)),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _statusText,
                style: const TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              if (_total > 0) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: _done / _total,
                    backgroundColor: const Color(0xFF2A2A2A),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF4A90E2)),
                    minHeight: 3,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'This only happens once.',
                style: const TextStyle(
                  color: Color(0xFF444444),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
