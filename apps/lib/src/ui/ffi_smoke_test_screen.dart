import 'package:flutter/material.dart';
import '../services/native/kitako_ffi_bridge.dart';

class FfiSmokeTestScreen extends StatefulWidget {
  const FfiSmokeTestScreen({super.key});

  @override
  State<FfiSmokeTestScreen> createState() => _FfiSmokeTestScreenState();
}

class _FfiSmokeTestScreenState extends State<FfiSmokeTestScreen> {
  final _bridge = KitakoFfiBridge();
  String status = "Not run";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("FFI Smoke Test")),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(status),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final emb = _bridge.getDummyEmbedding();
                setState(() {
                  if (emb == null) {
                    status = 'FFI failed: ${_bridge.lastError ?? 'unknown'}';
                  } else {
                    final a = emb.length > 0 ? emb[0] : 0;
                    final b = emb.length > 1 ? emb[1] : 0;
                    final c = emb.length > 2 ? emb[2] : 0;
                    status = "OK: len=${emb.length}, first3=[${a}, ${b}, ${c}]";
                  }
                });
              },
              child: const Text("Run FFI"),
            ),
          ],
        ),
      ),
    );
  }
}
