import 'package:flutter/material.dart';
import 'dart:typed_data';

import 'package:kitako_ffi/kitako_ffi.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _status = 'Initializing...';
  List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _testFfi();
  }

  void _log(String msg) {
    setState(() {
      _logs.add(msg);
    });
  }

  Future<void> _testFfi() async {
    try {
      _log('Creating KitakoFfi...');
      final ffi = KitakoFfi();
      _log('✓ KitakoFfi created successfully!');
      
      _log('ANN available: ${ffi.isAnnAvailable}');
      
      _log('Testing dummy embedding...');
      final embedding = ffi.dummyEmbedding768();
      if (embedding != null) {
        _log('✓ Got embedding: ${embedding.length} dimensions');
        _log('  First 5 values: ${embedding.sublist(0, 5).map((v) => v.toStringAsFixed(2)).join(", ")}');
      } else {
        _log('✗ Embedding is null');
      }
      
      if (ffi.isAnnAvailable) {
        _log('');
        _log('=== Testing ANN Functions ===');
        
        _log('Creating ANN index (768 dim, Inner Product)...');
        final handle = ffi.annCreate(768, AnnSpaceType.innerProduct);
        _log('✓ ANN index handle created');
        
        _log('Initializing index for 10 items...');
        ffi.annInitIndex(handle, maxElements: 10, M: 16, efConstruction: 100);
        _log('✓ Index initialized');
        
        // Add some test vectors
        for (int i = 0; i < 5; i++) {
          final vec = Float32List(768);
          for (int j = 0; j < 768; j++) {
            vec[j] = (i * 100 + j) / 1000.0;
          }
          ffi.annAddItem(handle, vec, i);
          _log('  Added item $i');
        }
        
        _log('Index count: ${ffi.annGetCount(handle)}');
        
        // Search
        _log('Searching for nearest neighbors...');
        final query = Float32List(768);
        for (int j = 0; j < 768; j++) {
          query[j] = j / 1000.0; // Similar to item 0
        }
        
        final results = ffi.annSearch(handle, query, 3);
        _log('✓ Search returned ${results.length} results:');
        for (final r in results) {
          _log('  ID: ${r.id}, Distance: ${r.distance.toStringAsFixed(4)}');
        }
        
        ffi.annFree(handle);
        _log('✓ ANN index freed');
      }
      
      setState(() => _status = 'All tests passed!');
    } catch (e, st) {
      _log('Error: $e');
      _log('Stack: $st');
      setState(() => _status = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('KitaKo FFI Test')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status: $_status', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (ctx, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(_logs[i], style: const TextStyle(fontFamily: 'monospace')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
