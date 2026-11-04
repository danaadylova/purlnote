import 'package:flutter/material.dart';

import '../app_session.dart';
import '../data/sync_engine.dart';
import '../theme.dart';

/// Shown right after sign-in while the knitter's records are copied to the
/// phone. They can start as soon as their projects are in.
class FirstSyncScreen extends StatelessWidget {
  const FirstSyncScreen({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final failed = !session.isSyncing && session.syncProblem != null;
    final name = session.user?.displayName;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  name == null ? 'Getting your notebook ready' : 'Welcome, $name',
                  style: text.headlineMedium,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Copying your Ravelry records to this phone so they work offline.',
                style: text.bodyLarge?.copyWith(color: PurlnoteColors.plumMuted),
              ),
              const SizedBox(height: 32),
              for (final step in SyncStep.values)
                _StepRow(
                  label: step.label,
                  count: session.firstSyncProgress[step],
                  running: session.isSyncing && _isNext(step),
                ),
              const Spacer(),
              if (failed) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(session.syncProblem!, style: const TextStyle(fontSize: 15)),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: session.retryFirstSync, child: const Text('Try again')),
              ] else
                FilledButton(
                  onPressed: session.canLeaveFirstSync ? session.finishFirstSync : null,
                  child: Text(session.isSyncing && session.canLeaveFirstSync
                      ? 'Start now (the rest keeps loading)'
                      : 'Open my notebook'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Steps run in order, so the first unfinished one is running now.
  bool _isNext(SyncStep step) {
    final unfinished = SyncStep.values.where((candidate) => !session.firstSyncProgress.containsKey(candidate));
    return unfinished.isNotEmpty && unfinished.first == step;
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.count, required this.running});

  final String label;

  /// Records stored, or null if the step hasn't finished.
  final int? count;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final done = count != null;
    final status = done ? '$count' : (running ? 'Loading' : 'Waiting');

    return Semantics(
      label: '$label: ${done ? 'done, $count' : status}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 24,
              child: done
                  ? const Icon(Icons.check_circle, color: PurlnoteColors.moss)
                  : running
                      ? const CircularProgressIndicator(strokeWidth: 2.5)
                      : const Icon(Icons.radio_button_unchecked, color: PurlnoteColors.inputBorder),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 17))),
            Text(status, style: const TextStyle(fontSize: 15, color: PurlnoteColors.plumMuted)),
          ],
        ),
      ),
    );
  }
}
