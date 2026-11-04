import 'package:flutter/material.dart';

import '../app_session.dart';
import '../data/local_database.dart';
import '../data/pending_edit.dart';
import '../ravelry/models.dart';
import '../theme.dart';
import '../widgets/project_widgets.dart';
import 'edit_conflict_screen.dart';
import 'project_screen.dart';
import 'queue_screen.dart';
import 'stash_screen.dart';

/// Home: projects on the needles, a shortcut to the stash, the queue, and
/// every other project. Read-only in milestone 1.
class NotebookScreen extends StatelessWidget {
  const NotebookScreen({super.key, required this.session});

  final AppSession session;

  /// How many queued patterns to show before "See all".
  static const queuePreviewLength = 5;

  @override
  Widget build(BuildContext context) {
    final onTheNeedles = session.onTheNeedles;
    final others = session.otherProjects;
    final queue = session.queue;

    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: const Text('Notebook')),
        actions: [_AccountMenu(session: session)],
      ),
      body: RefreshIndicator(
        onRefresh: session.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (session.syncProblem != null) _Banner(message: session.syncProblem!),
            for (final edit in session.conflicts)
              _ConflictBanner(
                recordName: _recordName(edit),
                onTap: () => _push(context, EditConflictScreen(session: session, edit: edit)),
              ),
            _SectionTitle('On the needles', count: onTheNeedles.length),
            if (onTheNeedles.isEmpty)
              const _Empty('Nothing on the needles. Projects marked "In progress" on Ravelry show up here.')
            else
              for (final project in onTheNeedles)
                ProjectCard(project: project, onTap: () => _openProject(context, project)),
            const SizedBox(height: 8),
            _StashShortcut(
              yarnCount: session.stash.length,
              onTap: () => _push(context, StashScreen(session: session)),
            ),
            _SectionTitle('Queue', count: queue.length),
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
            if (others.isNotEmpty) ...[
              _SectionTitle('Other projects', count: others.length),
              for (final project in others)
                _OtherProjectRow(project: project, onTap: () => _openProject(context, project)),
            ],
            const SizedBox(height: 16),
            _LastUpdated(session: session),
          ],
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
    } ?? 'An item';
  }

  void _openProject(BuildContext context, Project project) {
    _push(context, ProjectScreen(session: session, projectId: project.id));
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Semantics(
        header: true,
        child: Text('$title · $count', style: Theme.of(context).textTheme.titleMedium),
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
    if (session.isSyncing) {
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

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (choice) {
        if (choice == 'sign_out') _confirmSignOut(context);
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text('Signed in as ${session.user?.username ?? ''}'),
        ),
        const PopupMenuItem<String>(value: 'sign_out', child: Text('Sign out')),
      ],
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of Ravelry?'),
        content: const Text(
          'Your projects, queue and stash are removed from this phone. '
          'They come back when you sign in again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed == true) await session.signOut();
  }
}
