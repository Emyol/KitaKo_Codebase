import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kitako_core/kitako_core.dart';
import '../../services/face_service.dart';
import '../../services/image_search_service.dart';
import 'person_detail_screen.dart';

/// Screen showing all identified persons from face recognition.
///
/// Displays a grid of person clusters with representative thumbnails.
/// Tapping a person navigates to their detail screen.
/// Long-pressing shows options to label or merge persons.
///
/// Gracefully handles the face service being unavailable.
class PeopleScreen extends StatefulWidget {
  final ImageSearchService searchService;

  const PeopleScreen({super.key, required this.searchService});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  List<Person> _persons = [];
  bool _isLoading = true;

  FaceService? get _faceService => widget.searchService.faceService;

  @override
  void initState() {
    super.initState();
    _loadPersons();
  }

  void _loadPersons() {
    final face = _faceService;
    if (face == null || !face.isAvailable) {
      setState(() {
        _persons = [];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _persons = face.allPersons
        ..sort((a, b) => b.faceCount.compareTo(a.faceCount));
      _isLoading = false;
    });
  }

  void _openPersonDetail(Person person) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => PersonDetailScreen(
            person: person,
            searchService: widget.searchService,
          ),
        ))
        .then((_) => _loadPersons());
  }

  Future<void> _showLabelDialog(Person person) async {
    final controller = TextEditingController(text: person.label ?? '');
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
      _faceService?.labelPerson(person.personId, label);
      _loadPersons();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('People'),
        actions: [
          if (_faceService?.isAvailable == true)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _loadPersons,
            ),
        ],
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_faceService == null || !_faceService!.isAvailable) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.face_retouching_off,
                  size: 64,
                  color: isDark ? Colors.white38 : Colors.black38),
              const SizedBox(height: 16),
              Text(
                'Face Recognition Unavailable',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Face recognition models are not installed.\n'
                'The image search feature works normally without this.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black54),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_persons.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline,
                  size: 64,
                  color: isDark ? Colors.white38 : Colors.black38),
              const SizedBox(height: 16),
              Text(
                'No People Found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No faces have been detected in your gallery yet.\n'
                'Faces are automatically detected when images are indexed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black54),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              '${_persons.length} '
              '${_persons.length == 1 ? 'person' : 'people'} '
              'found in ${_faceService!.faceCount} faces',
              style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black54,
                  fontSize: 13),
            ),
          ),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.8,
              ),
              itemCount: _persons.length,
              itemBuilder: (_, i) =>
                  _buildPersonTile(_persons[i], isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonTile(Person person, bool isDark) {
    return GestureDetector(
      onTap: () => _openPersonDetail(person),
      onLongPress: () => _showLabelDialog(person),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? const Color(0xFF2A2A2A)
                    : const Color(0xFFE8E8E8),
                border: Border.all(
                  color: person.isLabeled
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: _buildPersonAvatar(person, isDark),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            person.label ?? 'Person ${person.personId}',
            style: TextStyle(
              fontSize: 12,
              fontWeight:
                  person.isLabeled ? FontWeight.w600 : FontWeight.normal,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          Text(
            '${person.faceCount} '
            '${person.faceCount == 1 ? 'photo' : 'photos'}',
            style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white38 : Colors.black45),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonAvatar(Person person, bool isDark) {
    final thumbnail = person.representativeThumbnail;
    if (thumbnail != null && thumbnail.isNotEmpty) {
      return Image.memory(
        Uint8List.fromList(thumbnail),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholderIcon(isDark),
      );
    }
    return _placeholderIcon(isDark);
  }

  Widget _placeholderIcon(bool isDark) {
    return Center(
      child: Icon(Icons.person,
          size: 40,
          color: isDark ? Colors.white24 : Colors.black26),
    );
  }
}
