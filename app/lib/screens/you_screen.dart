import 'package:flutter/material.dart';

import '../app_session.dart';
import '../theme.dart';

/// The knitter's account: who is signed in, the Ravelry connection, and
/// signing out.
class YouScreen extends StatelessWidget {
  const YouScreen({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final user = session.user;
        final waiting = session.pendingEdits.length;
        return Scaffold(
          appBar: AppBar(title: Semantics(header: true, child: const Text('You'))),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: PurlnoteColors.plum,
                  foregroundColor: PurlnoteColors.marigold,
                  child: Icon(Icons.person),
                ),
                title: Text(user?.displayName ?? 'Not signed in'),
                subtitle: user == null ? null : Text('Ravelry: ${user.username}'),
              ),
              const Divider(),
              _Row(
                icon: Icons.sync,
                title: 'Changes waiting to send',
                value: waiting == 0 ? 'None' : '$waiting',
              ),
              _Row(
                icon: Icons.schedule,
                title: 'Last updated from Ravelry',
                value: session.lastSyncedAt == null
                    ? 'Not yet'
                    : TimeOfDay.fromDateTime(session.lastSyncedAt!).format(context),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: () => _confirmSignOut(context),
              ),
              const SizedBox(height: 16),
              const Text(
                'Purlnote is not made by or affiliated with Ravelry. PDFs and your notes on them stay on this phone.',
                style: TextStyle(fontSize: 13, color: PurlnoteColors.plumMuted),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final waiting = session.pendingEdits.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of Ravelry?'),
        content: Text(
          'Your Ravelry projects, queue and stash are removed from this phone and come back when you sign in. '
          'PDFs, notes and counters stay on this phone.'
          '${waiting == 0 ? '' : ' $waiting changes that haven\'t reached Ravelry yet will be lost.'}',
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

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.value});

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      trailing: Text(value, style: const TextStyle(color: PurlnoteColors.plumMuted)),
    );
  }
}
