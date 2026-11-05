import 'package:flutter/material.dart';

import '../app_session.dart';
import '../data/local_database.dart';
import '../data/pending_edit.dart';
import '../library/library_models.dart';
import '../ravelry/models.dart';
import '../layout.dart';
import '../theme.dart';
import '../widgets/project_widgets.dart';
import 'notebook_cards.dart';
import 'edit_conflict_screen.dart';
import 'project_screen.dart';
import 'queue_screen.dart';
import 'stash_screen.dart';

/// Home: the projects on the needles as big cards to swipe through, finished
/// projects below them, then the stash, the queue and every other project.
class NotebookScreen extends StatelessWidget {
  const NotebookScreen({super.key, required this.session});

  final AppSession session;

  /// How many queued patterns to show before "See all".
  static const queuePreviewLength = 5;

  @override
  Widget build(BuildContext context) {
    final onTheNeedles = session.onTheNeedles;
    final finished = session.finishedProjects;
    final others = session.otherProjects;
    final queue = session.queue;
    final text = Theme.of(context).textTheme;

    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'On the needles · ${onTheNeedles.length}',
                  style: const TextStyle(color: PurlnoteColors.plumMuted, fontWeight: FontWeight.w600),
                ),
                Semantics(
                  header: true,
                  child: Text(
                    'Your notebook',
                    style: text.headlineLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          _NewProjectButton(onPressed: () => _newProject(context)),
        ],
      ),
    );

    final projectSections = <Widget>[
      header,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            if (session.syncProblem != null) _Banner(message: session.syncProblem!),
            for (final edit in session.conflicts)
              _ConflictBanner(
                recordName: _recordName(edit),
                onTap: () => _push(context, EditConflictScreen(session: session, edit: edit)),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (onTheNeedles.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: _Empty('Nothing on the needles yet. Start one with the + button.'),
        )
      else
        OnTheNeedlesCarousel(
          session: session,
          projects: onTheNeedles,
          onOpen: (project) => _openProject(context, project),
        ),
      if (finished.isNotEmpty) ...[
        const _SectionTitle('Finished'),
        FinishedRow(projects: finished, onOpen: (project) => _openProject(context, project)),
      ],
    ];

    // Stash and queue live on Ravelry, so they appear once an account is
    // connected.
    final otherSections = <Widget>[
      if (session.connected) ...[
        _StashShortcut(
          yarnCount: session.stash.length,
          onTap: () => _push(context, StashScreen(session: session)),
        ),
        _SectionTitle('Queue', count: queue.length, padded: false),
        if (queue.isEmpty)
          const _Empty('Your queue is empty.')
        else ...[
          for (final item in queue.take(queuePreviewLength)) _QueueRow(item: item),
          if (queue.length > queuePreviewLength)
            TextButton(
              onPressed: () => _push(context, QueueScreen(queue: queue)),
              child: Text('See all ${queue.length}'),
            ),
        ],
      ],
      if (others.isNotEmpty) ...[
        _SectionTitle('Other projects', count: others.length, padded: false),
        for (final project in others)
          _OtherProjectRow(project: project, onTap: () => _openProject(context, project)),
      ],
      const SizedBox(height: 16),
      _LastUpdated(session: session),
    ];

    if (isWide(context)) {
      // iPad: projects on the left, stash, queue and the rest in a column
      // on the right.
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: session.refresh,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(top: 24, bottom: 32),
                    children: projectSections,
                  ),
                ),
                Container(
                  width: 320,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(left: BorderSide(color: PurlnoteColors.line)),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
                    children: otherSections,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: session.refresh,
          child: ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 32),
            children: [
              ...projectSections,
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: otherSections),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The project or yarn a pending edit belongs to, by name.
  String _recordName(PendingEdit edit) {
    return switch (edit.recordType) {
          RecordType.project => session.projectById(edit.ravelryId)?.name,
          RecordType.stash => session.stashById(edit.ravelryId)?.name,
          _ => null,
        } ??
        'An item';
  }

  /// Starts a project on this phone, optionally with a pattern from the
  /// library.
  Future<void> _newProject(BuildContext context) async {
    final created = await showDialog<({String name, String? patternKey})>(
      context: context,
      builder: (context) => _NewProjectDialog(patterns: session.patterns.where((p) => p.isOnPhone).toList()),
    );
    if (created == null) return;
    final id = await session.createProject(name: created.name, patternKey: created.patternKey);
    if (context.mounted) _push(context, ProjectScreen(session: session, projectId: id));
  }

  void _openProject(BuildContext context, Project project) {
    _push(context, ProjectScreen(session: session, projectId: project.id));
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.count, this.padded = true});

  final String title;

  /// Shown after the title, as in "Queue · 3".
  final int? count;

  /// Whether to add the screen's side margins (for titles outside a padded
  /// column).
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padded ? 20 : 0, 24, padded ? 20 : 0, 10),
      child: Semantics(
        header: true,
        child: Text(count == null ? title : '$title · $count', style: Theme.of(context).textTheme.titleLarge),
      ),
    );
  }
}

/// The square plum "+" that starts a new project.
class _NewProjectButton extends StatelessWidget {
  const _NewProjectButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'New project',
      child: Material(
        color: PurlnoteColors.plum,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: const SizedBox.square(
            dimension: 48,
            child: Icon(Icons.add, color: PurlnoteColors.marigold, size: 28, semanticLabel: 'New project'),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(message, style: const TextStyle(color: PurlnoteColors.plumMuted, fontSize: 15)),
    );
  }
}

/// Stash isn't a tab; it opens from here, next to projects and the queue.
class _StashShortcut extends StatelessWidget {
  const _StashShortcut({required this.yarnCount, required this.onTap});

  final int yarnCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PurlnoteColors.sand,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.inventory_2_outlined, color: PurlnoteColors.moss),
              const SizedBox(width: 12),
              const Expanded(child: Text('Stash', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
              Text('$yarnCount ${yarnCount == 1 ? 'yarn' : 'yarns'}',
                  style: const TextStyle(color: PurlnoteColors.plumMuted)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: PurlnoteColors.plumMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.item});

  final QueuedProject item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: PurlnoteColors.mossLight,
        foregroundColor: PurlnoteColors.mossDark,
        child: Text('${item.position ?? '·'}', style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      title: Text(item.patternName),
    );
  }
}

class _OtherProjectRow extends StatelessWidget {
  const _OtherProjectRow({required this.project, required this.onTap});

  final Project project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = project.statusName;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: ProjectPhoto(url: project.photoUrl, size: 48),
      title: Text(project.name),
      subtitle: project.patternName == null ? null : Text(project.patternName!),
      trailing: status == null ? null : StatusChip(status: status),
    );
  }
}

/// Shown for each edit that was also changed on Ravelry.
class _ConflictBanner extends StatelessWidget {
  const _ConflictBanner({required this.recordName, required this.onTap});

  final String recordName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: PurlnoteColors.blush,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.call_split, size: 20, color: PurlnoteColors.plum),
                const SizedBox(width: 10),
                Expanded(child: Text('$recordName was also changed on Ravelry. Choose which version to keep.')),
                const Icon(Icons.chevron_right, color: PurlnoteColors.plum),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when the last sync failed; the Notebook keeps showing stored data.
class _Banner extends StatelessWidget {
  const _Banner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: PurlnoteColors.blush, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined, size: 20, color: PurlnoteColors.plum),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _LastUpdated extends StatelessWidget {
  const _LastUpdated({required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    final String message;
    if (!session.connected) {
      message = 'Everything here is kept on this phone.';
    } else if (session.isSyncing) {
      message = 'Updating from Ravelry…';
    } else if (session.lastSyncedAt == null) {
      message = 'Not updated yet. Pull down to update.';
    } else {
      final time = TimeOfDay.fromDateTime(session.lastSyncedAt!).format(context);
      message = 'Updated from Ravelry at $time. Pull down to update.';
    }
    return Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall);
  }
}

/// Asks for a new project's name and, optionally, its pattern.
class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog({required this.patterns});

  /// Patterns with a PDF on this phone.
  final List<LibraryPattern> patterns;

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final _name = TextEditingController();
  String? _patternKey;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New project'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'Harbour Raglan for Sam'),
          ),
          const SizedBox(height: 12),
          if (widget.patterns.isEmpty)
            const Text(
              'To read a pattern with this project, import its PDF in Library, then open the project.',
              style: TextStyle(fontSize: 13, color: PurlnoteColors.plumMuted),
            )
          else
            DropdownButtonFormField<String?>(
              initialValue: _patternKey,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Pattern (optional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('None yet')),
                for (final pattern in widget.patterns)
                  DropdownMenuItem(value: pattern.key, child: Text(pattern.title, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (key) => setState(() => _patternKey = key),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, (name: name, patternKey: _patternKey));
          },
          child: const Text('Start'),
        ),
      ],
    );
  }
}
