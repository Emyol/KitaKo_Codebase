import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _NativeDummyEmbed = ffi.Void Function(
  ffi.Pointer<ffi.Float> out,
  ffi.Int32 outLen,
);
typedef _DartDummyEmbed = void Function(
  ffi.Pointer<ffi.Float> out,
  int outLen,
);

class KitakoFfi {
  late final ffi.DynamicLibrary _lib;
  late final _DartDummyEmbed _dummyEmbed;

  KitakoFfi() {
    // Try platform-specific library first, then fall back to process() where
    // appropriate. This makes desktop dev runs less brittle.
    try {
      if (Platform.isAndroid) {
        _lib = ffi.DynamicLibrary.open('libkitako_ffi.so');
      } else if (Platform.isWindows) {
        _lib = ffi.DynamicLibrary.open('kitako_ffi.dll');
      } else if (Platform.isMacOS) {
        _lib = ffi.DynamicLibrary.open('libkitako_ffi.dylib');
      } else if (Platform.isLinux) {
        _lib = ffi.DynamicLibrary.open('libkitako_ffi.so');
      } else if (Platform.isIOS) {
        _lib = ffi.DynamicLibrary.process();
      } else {
        _lib = ffi.DynamicLibrary.process();
      }
    } catch (e) {
      // Fallback: try to use the process' symbols if available.
      try {
        _lib = ffi.DynamicLibrary.process();
      } catch (_) {
        rethrow;
      }
    }

    try {
      _dummyEmbed = _lib
          .lookup<ffi.NativeFunction<_NativeDummyEmbed>>('kitako_dummy_embed')
          .asFunction();
    } catch (e) {
      throw UnsupportedError('Failed to locate native symbol "kitako_dummy_embed": $e');
    }
  }

  Float32List dummyEmbedding768() {
    final outPtr = calloc<ffi.Float>(768);
    try {
      _dummyEmbed(outPtr, 768);
      final view = outPtr.asTypedList(768);
      return Float32List.fromList(view);
    } finally {
      calloc.free(outPtr);
    }
  }
}
