import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

import 'image_loader_service.dart';

/// Result of a capture + save round trip.
class CameraCaptureResult {
  /// Decoded bytes of the captured image, suitable for feeding into the
  /// embedding pipeline without re-reading from disk.
  final Uint8List bytes;

  /// Original on-disk path returned by [ImagePicker] (lives in the app's
  /// temp cache — not durable; do not link to this from anywhere except for
  /// the immediate post-capture flow).
  final String tempPath;

  /// The MediaStore asset created by the save. `null` if the save failed
  /// (capture still succeeded — search can proceed off [bytes]).
  final AssetEntity? savedAsset;

  /// Human-readable reason the save failed, if any. `null` on success or
  /// when no save was attempted. Surfaced by the UI for diagnostics.
  final String? saveError;

  /// `true` when the save succeeded and the file is now visible to the
  /// system gallery / Google Photos.
  bool get savedToGallery => savedAsset != null;

  const CameraCaptureResult({
    required this.bytes,
    required this.tempPath,
    this.savedAsset,
    this.saveError,
  });
}

/// Captures a photo via the device camera and persists it to the user's
/// gallery so Kitako behaves like a real camera app — the picture survives
/// past the search session and is visible in any system gallery viewer.
///
/// Pipeline:
///   1. [ImagePicker] opens the camera and returns a temp [XFile].
///   2. The temp file is copied into the gallery via
///      [PhotoManager.editor.saveImageWithPath]. The target album follows
///      [ImageLoaderService.kCaptureRelativePath] so captures land in the
///      same folder Kitako is currently reading from — that way a freshly
///      taken photo is immediately a candidate for indexing rather than
///      orphaned in a separate directory.
///   3. The original bytes are returned to the caller for immediate use
///      (image-to-image search) without an extra disk read.
///
/// Permission model:
///   • Android 10+ (API 29+): MediaStore writes for own-app inserts need
///     NO runtime permission. `WRITE_EXTERNAL_STORAGE` is unusable on these
///     versions — declaring it returns `denied` from permission_handler
///     because the OS strips it from the merged manifest at install time.
///   • Android ≤ 28: the manifest declares `WRITE_EXTERNAL_STORAGE` with
///     `maxSdkVersion="28"` and we request it at runtime *only after* a
///     save attempt fails — that way we don't gate modern devices on a
///     legacy check that always denies.
class CameraCaptureService {
  /// Gallery sub-folder where Kitako captures land. Mirrors the album the
  /// [ImageLoaderService] is reading from so capture → index works in one
  /// shot. Test builds: `DCIM/personal_1k`. Production: `DCIM/Kitako`.
  static const String kGalleryAlbum = ImageLoaderService.kCaptureRelativePath;

  final ImagePicker _picker;

  CameraCaptureService({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  /// Open the camera, capture a photo, persist it to the gallery, and
  /// return the bytes for downstream use.
  ///
  /// Returns `null` if the user cancelled the capture.
  ///
  /// Throws only if the camera itself fails. A failure to *save* to the
  /// gallery does not throw — the returned [CameraCaptureResult.savedAsset]
  /// is `null` and [CameraCaptureResult.saveError] carries the reason so
  /// the caller can surface it.
  Future<CameraCaptureResult?> captureAndSave({
    int? maxWidth,
    int? maxHeight,
  }) async {
    final XFile? shot = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: maxWidth?.toDouble(),
      maxHeight: maxHeight?.toDouble(),
    );
    if (shot == null) return null;

    final bytes = await shot.readAsBytes();

    AssetEntity? saved;
    String? saveError;
    try {
      saved = await _saveToGallery(filePath: shot.path);
    } catch (e, st) {
      // Don't let a save failure block the search — log, capture for the
      // UI, and continue with bytes-only.
      saveError = e.toString();
      debugPrint('CameraCaptureService: save to gallery failed: $e\n$st');
    }

    return CameraCaptureResult(
      bytes: bytes,
      tempPath: shot.path,
      savedAsset: saved,
      saveError: saveError,
    );
  }

  /// Save an already-captured file to the gallery without going through
  /// the camera UI. Useful if the caller wants to capture separately and
  /// just needs the persist step.
  Future<AssetEntity?> _saveToGallery({required String filePath}) async {
    // First attempt: just call saveImageWithPath. On Android 10+ this
    // succeeds via MediaStore with no runtime permission. On pre-Q it can
    // throw a SecurityException if WRITE_EXTERNAL_STORAGE is not granted.
    try {
      return await _trySave(filePath);
    } catch (e) {
      // Only attempt a permission-then-retry on Android. The error type
      // varies (PlatformException, SecurityException via channel, etc.),
      // so we match on the message rather than the exception class.
      if (!Platform.isAndroid || !_looksLikePermissionError(e)) {
        rethrow;
      }
      debugPrint('CameraCaptureService: save failed, requesting '
          'WRITE_EXTERNAL_STORAGE and retrying once. Original: $e');
      final granted = await _requestLegacyStoragePermission();
      if (!granted) {
        throw StateError(
          'Gallery save requires storage permission on this Android version.',
        );
      }
      return await _trySave(filePath);
    }
  }

  /// One shot at the save — separated so the permission-retry path can
  /// reuse it without recursion.
  Future<AssetEntity> _trySave(String filePath) async {
    final filename =
        'kitako_${DateTime.now().millisecondsSinceEpoch}${_extOf(filePath)}';
    final asset = await PhotoManager.editor.saveImageWithPath(
      filePath,
      title: filename,
      relativePath: kGalleryAlbum,
    );
    debugPrint(
        'CameraCaptureService: saved to gallery → ${asset.id} ($filename) '
        'at relativePath=$kGalleryAlbum');
    return asset;
  }

  /// True if the exception looks like a permission denial rather than
  /// e.g. a missing file or invalid relativePath.
  bool _looksLikePermissionError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('permission') ||
        msg.contains('security') ||
        msg.contains('denied');
  }

  /// Request legacy WRITE_EXTERNAL_STORAGE (only meaningful on API ≤ 28).
  /// On API 29+ this returns `false` because the permission isn't in the
  /// merged manifest — the caller should treat that as "skip the retry"
  /// since the original error wasn't actually a permission issue.
  Future<bool> _requestLegacyStoragePermission() async {
    final status = await Permission.storage.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) return false;
    final result = await Permission.storage.request();
    return result.isGranted;
  }

  String _extOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '.jpg';
    final ext = path.substring(dot).toLowerCase();
    // Guard against weird picker outputs — fall back to jpg.
    return const {'.jpg', '.jpeg', '.png', '.heic', '.webp'}.contains(ext)
        ? ext
        : '.jpg';
  }
}
