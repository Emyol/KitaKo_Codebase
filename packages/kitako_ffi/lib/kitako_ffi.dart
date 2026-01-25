// Conditional export: use the real FFI implementation when `dart:ffi` is
// available; otherwise export a stub implementation (web-safe).
export 'src/kitako_ffi_stub.dart'
  if (dart.library.ffi) 'src/kitako_ffi_real.dart';
