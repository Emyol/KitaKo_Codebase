import 'dart:async';
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
  FaceServiceStatus _faceStatus = FaceServiceStatus.uninitialized;
  FaceIndexingState _indexingState = const FaceIndexingState();

  StreamSubscription<FaceServiceStatus>? _statusSub;
  StreamSubscription<FaceIndexingState>? _indexingSub;

  FaceService? get _faceService => widget.searchService.faceService;

  @override
  void initState() {
    super.initState();
    final face = _faceService;
    if (face != null) {
      _faceStatus = face.status;
      _statusSub = face.statusStream.listen((s) {
        if (!mounted) return;
        setState(() => _faceStatus = s);
        if (s == FaceServiceStatus.ready) _loadPersons();
      });
      _indexingSub = face.indexingStream.listen((state) {
        if (!mounted) return;
        setState(() => _indexingState = state);
      });
    }
    _loadPersons();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _indexingSub?.cancel();
    super.dispose();
  }

  void _loadPersons() {
    final face = _faceService;
    if (face == null || face.status == FaceServiceStatus.unavailable ||
        face.status == FaceServiceStatus.uninitialized) {
      setState(() {
        _persons = [];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _persons = List.of(face.allPersons)
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
          if (_faceStatus == FaceServiceStatus.ready)
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
    // Models not present at all.
    if (_faceService == null ||
        _faceStatus == FaceServiceStatus.unavailable ||
        _faceStatus == FaceServiceStatus.uninitialized) {
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

    // Models loaded, currently scanning gallery.
    if (_faceStatus == FaceServiceStatus.indexing ||
        _faceStatus == FaceServiceStatus.initializing) {
      final state = _indexingState;
      final hasProgress = state.totalImages > 0;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                _faceStatus == FaceServiceStatus.initializing
                    ? 'Loading face models…'
                    : 'Scanning for faces…',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              if (hasProgress) ...[
                const SizedBox(height: 8),
                Text(
                  '${state.processedImages} / ${state.totalImages} images'
                  '  ·  ${state.facesFound} faces found',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: state.progress),
              ],
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
              Icon(Icons.face_outlined,
                  size: 64,
                  color: isDark ? Colors.white38 : Colors.black38),
              const SizedBox(height: 16),
              Text(
                'Find People',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Scan your gallery to detect and group faces.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black54),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: null,
                icon: const Icon(Icons.search),
                label: const Text('Find Faces'),
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
                    ? const Color(0xFF1A2030)
                    : const Color(0xFFE8EEF6),
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
