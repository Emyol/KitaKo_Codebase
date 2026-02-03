import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import '../../models/search_models.dart';
import '../../services/image_search_service.dart';

/// Screen displaying full-size image with detailed metadata
///
/// Features:
/// - Full-size image view with zoom
/// - Metadata display (path, date, size, dimensions)
/// - Share and save actions
/// - Image navigation (prev/next)
class DetailsScreen extends StatefulWidget {
  /// The image to display
  final ImageItem image;

  /// Reference to the search service
  final ImageSearchService searchService;

  /// Optional list of images for navigation
  final List<ImageItem>? imageList;

  /// Current index in the image list
  final int? currentIndex;

  const DetailsScreen({
    super.key,
    required this.image,
    required this.searchService,
    this.imageList,
    this.currentIndex,
  });

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  late ImageItem _currentImage;
  late int _currentIndex;
  bool _showMetadata = true;
  final TransformationController _transformationController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    _currentImage = widget.image;
    _currentIndex = widget.currentIndex ?? 0;
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _currentImage.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Toggle metadata
          IconButton(
            icon: Icon(
              _showMetadata ? Icons.info : Icons.info_outline,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _showMetadata = !_showMetadata;
              });
            },
          ),
          // Share button
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: _shareImage,
          ),
          // More options
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'copy_path',
                child: Row(
                  children: [
                    Icon(Icons.content_copy, size: 20),
                    SizedBox(width: 12),
                    Text('Copy Path'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'open_folder',
                child: Row(
                  children: [
                    Icon(Icons.folder_open, size: 20),
                    SizedBox(width: 12),
                    Text('Open Folder'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 20, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Delete', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Image viewer with zoom
          GestureDetector(
            onDoubleTap: _handleDoubleTap,
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: _buildFullImage(),
              ),
            ),
          ),

          // Metadata panel (slide up from bottom)
          if (_showMetadata)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildMetadataPanel(isDark, textColor),
            ),

          // Navigation arrows (if part of a list)
          if (widget.imageList != null && widget.imageList!.length > 1) ...[
            // Previous button
            if (_currentIndex > 0)
              Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _buildNavigationButton(
                    icon: Icons.chevron_left,
                    onPressed: _goToPrevious,
                  ),
                ),
              ),
            // Next button
            if (_currentIndex < widget.imageList!.length - 1)
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _buildNavigationButton(
                    icon: Icons.chevron_right,
                    onPressed: _goToNext,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Build the full-size image widget
  Widget _buildFullImage() {
    // Try to load thumbnail if available
    if (_currentImage.thumbnail != null) {
      return Image.memory(
        _currentImage.thumbnail!,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }

    // Try to load from file path
    final file = File(_currentImage.path);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }

    // Fallback to placeholder
    return _buildPlaceholder();
  }

  /// Build placeholder for images that can't be loaded
  Widget _buildPlaceholder() {
    return Container(
      width: 300,
      height: 300,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: 80,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _currentImage.name,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Image not available',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// Build the metadata panel
  Widget _buildMetadataPanel(bool isDark, Color textColor) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.7),
            Colors.black.withOpacity(0.9),
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // File name
              _buildMetadataRow(
                Icons.insert_drive_file_outlined,
                'Name',
                _currentImage.name,
              ),
              const SizedBox(height: 12),

              // File path
              _buildMetadataRow(
                Icons.folder_outlined,
                'Path',
                _currentImage.path,
                isPath: true,
              ),
              const SizedBox(height: 12),

              // Row with size and dimensions
              Row(
                children: [
                  Expanded(
                    child: _buildMetadataRow(
                      Icons.storage_outlined,
                      'Size',
                      _formatFileSize(_currentImage.sizeBytes),
                    ),
                  ),
                  if (_currentImage.width != null && _currentImage.height != null)
                    Expanded(
                      child: _buildMetadataRow(
                        Icons.aspect_ratio,
                        'Dimensions',
                        '${_currentImage.width} × ${_currentImage.height}',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Dates
              Row(
                children: [
                  if (_currentImage.createdAt != null)
                    Expanded(
                      child: _buildMetadataRow(
                        Icons.calendar_today_outlined,
                        'Created',
                        _formatDate(_currentImage.createdAt!),
                      ),
                    ),
                  if (_currentImage.modifiedAt != null)
                    Expanded(
                      child: _buildMetadataRow(
                        Icons.edit_calendar_outlined,
                        'Modified',
                        _formatDate(_currentImage.modifiedAt!),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build a single metadata row
  Widget _buildMetadataRow(
    IconData icon,
    String label,
    String value, {
    bool isPath = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: Colors.white.withOpacity(0.6),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                ),
                maxLines: isPath ? 2 : 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build navigation button
  Widget _buildNavigationButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 32),
        onPressed: onPressed,
      ),
    );
  }

  /// Handle double tap to reset zoom
  void _handleDoubleTap() {
    if (_transformationController.value != Matrix4.identity()) {
      _transformationController.value = Matrix4.identity();
    } else {
      // Zoom in 2x at center
      _transformationController.value = Matrix4.identity()..scale(2.0);
    }
  }

  /// Navigate to previous image
  void _goToPrevious() {
    if (widget.imageList == null || _currentIndex <= 0) return;
    setState(() {
      _currentIndex--;
      _currentImage = widget.imageList![_currentIndex];
      _transformationController.value = Matrix4.identity();
    });
  }

  /// Navigate to next image
  void _goToNext() {
    if (widget.imageList == null ||
        _currentIndex >= widget.imageList!.length - 1) {
      return;
    }
    setState(() {
      _currentIndex++;
      _currentImage = widget.imageList![_currentIndex];
      _transformationController.value = Matrix4.identity();
    });
  }

  /// Share the current image
  Future<void> _shareImage() async {
    final file = File(_currentImage.path);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Image file not found'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    try {
      await Share.shareXFiles(
        [XFile(_currentImage.path)],
        text: 'Shared from KitaKo',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share: $e'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  /// Handle menu actions
  void _handleMenuAction(String action) {
    switch (action) {
      case 'copy_path':
        Clipboard.setData(ClipboardData(text: _currentImage.path));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Path copied to clipboard'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        break;
      case 'open_folder':
        // TODO: Implement folder opening
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Opening folder...'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        break;
      case 'delete':
        _showDeleteConfirmation();
        break;
    }
  }

  /// Show delete confirmation dialog
  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Image'),
        content: Text('Are you sure you want to delete "${_currentImage.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Implement actual deletion
              Navigator.of(this.context).pop();
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(
                  content: Text('Deleted: ${_currentImage.name}'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Format file size in human-readable format
  String _formatFileSize(int? bytes) {
    if (bytes == null) return 'Unknown';

    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Format date in readable format
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
