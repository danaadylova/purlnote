import 'package:flutter/material.dart';

import '../ravelry/models.dart';
import '../theme.dart';

/// The whole queue, in queue order.
class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key, required this.queue});

  final List<QueuedProject> queue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Semantics(header: true, child: const Text('Queue'))),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: queue.length,
        itemBuilder: (context, index) {
          final item = queue[index];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: PurlnoteColors.mossLight,
              foregroundColor: PurlnoteColors.mossDark,
              child: Text('${item.position ?? index + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            title: Text(item.patternName),
          );
        },
      ),
    );
  }
}
