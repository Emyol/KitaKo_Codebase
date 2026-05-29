import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kitako_core/kitako_core.dart';
import '../../services/face_service.dart';
import '../../services/image_search_service.dart';
import '../../models/search_models.dart';

import '../theme/palette.dart';
/// Detail screen for a single identified person.
///
/// Shows the person's representative thumbnail, label/name, face count,
/// and a grid of all images containing that person.
/// Users can label/rename the person from this screen.
class PersonDetailScreen extends StatefulWidget {
  final Person person;
  final ImageSearchService searchService;

  const PersonDetailScreen({
    super.key,
    required this.person,
    required this.searchService,
  });

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  late Person _person;
  List<ImageItem> _images = [];
  bool _isLoading = true;

  FaceService? get _faceService => widget.searchService.faceService;

  @override
  void initState() {
    super.initState();
    _person = widget.person;
    _loadPersonImages();
  }

  Future<void> _loadPersonImages() async {
    final face = _faceService;
    if (face == null || !face.isAvailable) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final imageIds = face.getImageIdsForPerson(_person.personId);

      final images = <ImageItem>[];
      for (final id in imageIds) {
        try {
          final img =
              await widget.searchService.imageLoader.getImageWithThumbnail(id);
          images.add(img);
        } catch (_) {
          // Skip images that can't be loaded
        }
      }

      if (mounted) {
        setState(() {
          _images = images;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('PersonDetailScreen: Failed to load images: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showLabelDialog() async {
    final controller = TextEditingController(text: _person.label ?? '');
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name this person'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter name...',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (label != null && label.isNotEmpty) {
      _faceService?.labelPerson(_person.personId, label);

      final updatedPerson = _faceService?.getPerson(_person.personId);
      if (updatedPerson != null && mounted) {
        setState(() => _person = updatedPerson);
      }
    }
  }

  Future<void> _searchByPerson() async {
    if (_person.label == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Label this person first to search by name'),
        ),
      );
      return;
    }

    await widget.searchService.searchByPerson(_person.label!);
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayName = _person.label ?? 'Person ${_person.personId}';

    return Scaffold(
      appBar: AppBar(
        title: Text(displayName),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit name',
            onPressed: _showLabelDialog,
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search photos of this person',
            onPressed: _searchByPerson,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(isDark)),
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: _images.isEmpty
                      ? SliverToBoxAdapter(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                'No photos found for this person',
                                style: TextStyle(
                                  color: P.textMore(isDark),
                                ),
                              ),
                            ),
                          ),
                        )
                      : SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 1,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => _buildImageTile(_images[i], isDark),
                            childCount: _images.length,
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark
                  ? const Color(0xFF1A2030)
                  : const Color(0xFFE8EEF6),
              border: Border.all(
                color: _person.isLabeled
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 3,
              ),
            ),
            child: ClipOval(
              child: _person.representativeThumbnail != null
                  ? Image.memory(
                      Uint8List.fromList(_person.representativeThumbnail!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.person,
                        size: 48,
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                    )
                  : Icon(
                      Icons.person,
                      size: 48,
                      color: isDark ? Colors.white24 : Colors.black26,
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _person.label ?? 'Unknown Person',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: P.text(isDark),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_person.faceCount} '
            '${_person.faceCount == 1 ? 'appearance' : 'appearances'} '
            'in ${_images.length} '
            '${_images.length == 1 ? 'photo' : 'photos'}',
            style: TextStyle(
                color: P.textMore(isDark)),
          ),
          const SizedBox(height: 12),
          if (!_person.isLabeled)
            OutlinedButton.icon(
              onPressed: _showLabelDialog,
              icon: const Icon(Icons.label_outline, size: 18),
              label: const Text('Add Name'),
            ),
        ],
      ),
    );
  }

  Widget _buildImageTile(ImageItem image, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: P.surfaceAlt(isDark),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(image.path),
          fit: BoxFit.cover,
          cacheWidth: 256,
          errorBuilder: (_, _, _) => _buildImagePlaceholder(image, isDark),
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder(ImageItem image, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_outlined,
            color: isDark
                ? Colors.white.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.3),
            size: 32,
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              image.name,
              style: TextStyle(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.5)
                    : Colors.black.withValues(alpha: 0.5),
                fontSize: 9,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
