import 'package:flutter/material.dart';

import '../app_session.dart';
import '../data/local_database.dart';
import '../ravelry/models.dart';
import '../theme.dart';
import 'stash_yarn_screen.dart';

/// Every yarn in the stash. Tap one to see and edit it.
class StashScreen extends StatelessWidget {
  const StashScreen({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final stash = session.stash;
        return Scaffold(
          appBar: AppBar(title: Semantics(header: true, child: const Text('Stash'))),
          body: stash.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No yarn in your stash yet.', style: TextStyle(color: PurlnoteColors.plumMuted)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: stash.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) => _StashRow(
                    yarn: stash[index],
                    waitingToSend: session.pendingEditFor(RecordType.stash, stash[index].id) != null,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => StashYarnScreen(session: session, yarnId: stash[index].id),
                    )),
                  ),
                ),
        );
      },
    );
  }
}

class _StashRow extends StatelessWidget {
  const _StashRow({required this.yarn, required this.waitingToSend, required this.onTap});

  final StashYarn yarn;
  final bool waitingToSend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // "Malabrigo · Rios · Worsted": whichever of these Ravelry has.
    final details = [yarn.companyName, yarn.colorway, yarn.weightName].whereType<String>().join(' · ');
    final status = yarn.status == StashStatus.inStash ? null : yarn.status.label;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      onTap: onTap,
      title: Text(yarn.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [details, if (status != null) status, if (waitingToSend) 'Waiting to send']
            .where((part) => part.isNotEmpty)
            .join('\n'),
      ),
      trailing: const Icon(Icons.chevron_right, color: PurlnoteColors.plumMuted),
    );
  }
}
