import 'package:flutter/material.dart';

import '../app_session.dart';
import '../library/library_models.dart';
import '../library/pdf_files.dart';
import '../theme.dart';
import 'library_pattern_screen.dart';

/// How the library list is ordered.
enum LibrarySort {
  recentlyOpened('Recently opened'),
  name('Name'),
  dateAdded('Date added');

  const LibrarySort(this.label);
  final String label;
}

/// Every pattern: Ravelry purchases and imported PDFs together, with search
/// by name or designer and a choice of order.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.session});

  final AppSession session;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _search = TextEditingController();
  LibrarySort _sort = LibrarySort.recentlyOpened;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<LibraryPattern> _shown(List<LibraryPattern> all) {
    final query = _search.text.trim().toLowerCase();
    final matching = query.isEmpty
        ? [...all]
        : all
            .where((pattern) =>
                pattern.title.toLowerCase().contains(query) || (pattern.author ?? '').toLowerCase().contains(query))
            .toList();
    final never = DateTime(0);
    matching.sort(switch (_sort) {
      LibrarySort.name => (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      LibrarySort.dateAdded => (a, b) => (b.addedAt ?? never).compareTo(a.addedAt ?? never),
      LibrarySort.recentlyOpened => (a, b) {
          final byOpened = (b.lastOpenedAt ?? never).compareTo(a.lastOpenedAt ?? never);
          return byOpened != 0 ? byOpened : a.title.toLowerCase().compareTo(b.title.toLowerCase());
        },
    });
    return matching;
  }

  Future<void> _import() async {
    try {
      final pattern = await widget.session.importPdf();
      if (pattern != null && mounted) _open(pattern);
    } on ImportRefused catch (refused) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(refused.message)));
    }
  }

  void _open(LibraryPattern pattern) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LibraryPatternScreen(session: widget.session, patternKey: pattern.key),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final patterns = _shown(widget.session.patterns);
        return Scaffold(
          appBar: AppBar(
            title: Semantics(header: true, child: const Text('Library')),
            actions: [
              TextButton.icon(onPressed: _import, icon: const Icon(Icons.file_open_outlined), label: const Text('Import PDF')),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search by name or designer',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text('${patterns.length} patterns', style: const TextStyle(color: PurlnoteColors.plumMuted)),
                    const Spacer(),
                    DropdownButton<LibrarySort>(
                      value: _sort,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final sort in LibrarySort.values) DropdownMenuItem(value: sort, child: Text(sort.label)),
                      ],
                      onChanged: (sort) => setState(() => _sort = sort ?? _sort),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: patterns.isEmpty
                    ? _EmptyLibrary(searching: _search.text.isNotEmpty, onImport: _import)
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: patterns.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) =>
                            _PatternRow(pattern: patterns[index], onTap: () => _open(patterns[index])),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PatternRow extends StatelessWidget {
  const _PatternRow({required this.pattern, required this.onTap});

  final LibraryPattern pattern;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final where = pattern.source == PatternSource.imported
        ? 'Imported'
        : pattern.isOnPhone
            ? 'On this phone'
            : 'On Ravelry';
    final details = [pattern.author, where].whereType<String>().join(' · ');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      onTap: onTap,
      leading: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox.square(
            dimension: 52,
            child: pattern.coverUrl == null
                ? const ColoredBox(color: PurlnoteColors.sand, child: Icon(Icons.description_outlined))
                : Image.network(
                    pattern.coverUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) =>
                        const ColoredBox(color: PurlnoteColors.sand, child: Icon(Icons.description_outlined)),
                  ),
          ),
        ),
      ),
      title: Text(pattern.title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(details),
      trailing: const Icon(Icons.chevron_right, color: PurlnoteColors.plumMuted),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.searching, required this.onImport});

  final bool searching;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              searching
                  ? 'No patterns match that search.'
                  : 'Bring in your pattern PDFs from Files, from iCloud Drive, a download or anywhere else on this phone. '
                      'Patterns bought on Ravelry show up here too when a Ravelry account is connected.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            if (!searching) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onImport, child: const Text('Import a PDF')),
            ],
          ],
        ),
      ),
    );
  }
}
