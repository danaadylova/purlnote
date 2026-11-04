import 'package:flutter/material.dart';

import '../ravelry/models.dart';
import '../theme.dart';

/// Every yarn in the stash, read-only. Filters and editing come later.
class StashScreen extends StatelessWidget {
  const StashScreen({super.key, required this.stash});

  final List<StashYarn> stash;

  @override
  Widget build(BuildContext context) {
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
              itemBuilder: (context, index) => _StashRow(yarn: stash[index]),
            ),
    );
  }
}

class _StashRow extends StatelessWidget {
  const _StashRow({required this.yarn});

  final StashYarn yarn;

  @override
  Widget build(BuildContext context) {
    // "Malabrigo · Rios · Worsted": whichever of these Ravelry has.
    final details = [yarn.companyName, yarn.colorway, yarn.weightName].whereType<String>().join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      title: Text(yarn.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: details.isEmpty ? null : Text(details),
    );
  }
}
