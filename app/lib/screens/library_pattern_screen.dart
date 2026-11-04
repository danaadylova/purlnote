import 'package:flutter/material.dart';

import '../app_session.dart';
import '../library/library_models.dart';
import '../library/pdf_files.dart';
import '../reader/reader_screen.dart';
import '../theme.dart';

/// One pattern's files: download them, open them, add or rename files, and
/// see which projects use the pattern.
class LibraryPatternScreen extends StatefulWidget {
  const LibraryPatternScreen({super.key, required this.session, required this.patternKey});

  final AppSession session;
  final String patternKey;

  @override
  State<LibraryPatternScreen> createState() => _LibraryPatternScreenState();
}

class _LibraryPatternScreenState extends State<LibraryPatternScreen> {
  /// The file being downloaded right now, if any.
  int? _downloading;
  bool _canDownload = false;

  @override
  void initState() {
    super.initState();
    final pattern = widget.session.patternByKey(widget.patternKey);
    if (pattern != null && pattern.source == PatternSource.ravelry) {
      widget.session.loadPurchaseFiles(pattern);
      widget.session.canDownloadPdfs().then((allowed) {
        if (mounted) setState(() => _canDownload = allowed);
      });
    }
  }

  void _say(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _allowDownloads() async {
    final problem = await widget.session.allowPdfDownloads();
    if (!mounted) return;
    if (problem != null) {
      _say(problem);
    } else {
      setState(() => _canDownload = true);
    }
  }

  Future<void> _download(PatternFile file) async {
    setState(() => _downloading = file.id);
    final problem = await widget.session.downloadFile(file);
    if (!mounted) return;
    setState(() => _downloading = null);
    if (problem != null) _say(problem);
  }

  Future<void> _addAnotherPdf() async {
    try {
      await widget.session.importPdf(addToPattern: widget.patternKey);
    } on ImportRefused catch (refused) {
      _say(refused.message);
    }
  }

  Future<void> _rename({required String title, required String current, required Future<void> Function(String) save}) async {
    final text = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: text, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, text.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await save(name);
  }

  void _read(LibraryPattern pattern, {PatternFile? file, int? projectId}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ReaderScreen(session: widget.session, pattern: pattern, startFileId: file?.id, projectId: projectId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final pattern = widget.session.patternByKey(widget.patternKey);
        if (pattern == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Pattern not found.')));
        return _buildPattern(context, pattern);
      },
    );
  }

  Widget _buildPattern(BuildContext context, LibraryPattern pattern) {
    final isImport = pattern.source == PatternSource.imported;
    final projects = widget.session.projects
        .where((project) => pattern.ravelryPatternId != null && project.patternId == pattern.ravelryPatternId)
        .toList();
    final needsPermission = !isImport && !_canDownload && pattern.files.any((file) => !file.isDownloaded);

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (isImport)
            IconButton(
              tooltip: 'Rename pattern',
              icon: const Icon(Icons.drive_file_rename_outline),
              onPressed: () => _rename(
                title: 'Pattern name',
                current: pattern.title,
                save: (name) => widget.session.renameImportedPattern(pattern.key, name),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Semantics(header: true, child: Text(pattern.title, style: Theme.of(context).textTheme.headlineMedium)),
          if (pattern.author != null) Text(pattern.author!, style: const TextStyle(color: PurlnoteColors.plumMuted)),
          const SizedBox(height: 20),
          if (pattern.isOnPhone)
            FilledButton.icon(
              onPressed: () => _read(pattern),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Read'),
            ),
          if (needsPermission) ...[
            const SizedBox(height: 12),
            _PermissionCard(onAllow: _allowDownloads),
          ],
          const SizedBox(height: 20),
          Semantics(header: true, child: Text('Files', style: Theme.of(context).textTheme.titleMedium)),
          if (pattern.files.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Getting the list of files from Ravelry…', style: TextStyle(color: PurlnoteColors.plumMuted)),
            ),
          for (final file in pattern.files)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(file.isDownloaded ? Icons.picture_as_pdf : Icons.cloud_outlined, color: PurlnoteColors.moss),
              title: Text(file.label),
              subtitle: Text(file.isDownloaded ? _size(file.bytes) : 'On Ravelry'),
              onTap: file.isDownloaded ? () => _read(pattern, file: file) : null,
              onLongPress: () => _rename(
                title: 'File name',
                current: file.label,
                save: (label) => widget.session.renameFile(file.id, label),
              ),
              trailing: file.isDownloaded
                  ? const Icon(Icons.chevron_right)
                  : _downloading == file.id
                      ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : TextButton(onPressed: _canDownload ? () => _download(file) : null, child: const Text('Download')),
            ),
          if (isImport)
            TextButton.icon(onPressed: _addAnotherPdf, icon: const Icon(Icons.add), label: const Text('Add another PDF')),
          if (pattern.files.isNotEmpty)
            const Text('Press and hold a file to rename it.', style: TextStyle(fontSize: 13, color: PurlnoteColors.plumMuted)),
          if (projects.isNotEmpty) ...[
            const SizedBox(height: 24),
            Semantics(header: true, child: Text('Your projects', style: Theme.of(context).textTheme.titleMedium)),
            for (final project in projects)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(project.name),
                subtitle: project.statusName == null ? null : Text(project.statusName!),
                trailing: pattern.isOnPhone ? const Text('Read') : null,
                onTap: pattern.isOnPhone ? () => _read(pattern, projectId: project.id) : null,
              ),
          ],
        ],
      ),
    );
  }

  String _size(int? bytes) {
    if (bytes == null) return 'On this phone';
    final mb = bytes / (1024 * 1024);
    return mb >= 1 ? '${mb.toStringAsFixed(1)} MB · on this phone' : '${(bytes / 1024).round()} KB · on this phone';
  }
}

/// Explains the one-time permission for downloading purchased PDFs.
class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.onAllow});

  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: PurlnoteColors.mossLight, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'To download your purchased PDFs, allow Purlnote to fetch them from Ravelry. '
            'Ravelry asks once. Each PDF is downloaded once and kept on this phone.',
            style: TextStyle(fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 10),
          FilledButton(onPressed: onAllow, child: const Text('Allow PDF downloads')),
        ],
      ),
    );
  }
}
