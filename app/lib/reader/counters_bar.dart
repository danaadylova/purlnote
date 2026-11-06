import 'package:flutter/material.dart';

import '../library/library_models.dart';
import '../theme.dart';

/// The project's counters under the page: the row counter with − and +, and
/// any repeat counters, which follow the row counter on their own.
class CountersBar extends StatelessWidget {
  const CountersBar({
    super.key,
    required this.counters,
    required this.onRowsChanged,
    required this.onAddRepeat,
    required this.onRemove,
  });

  /// The row counter first, then repeat counters.
  final List<ProjectCounter> counters;
  final ValueChanged<int> onRowsChanged;
  final VoidCallback onAddRepeat;
  final ValueChanged<ProjectCounter> onRemove;

  @override
  Widget build(BuildContext context) {
    final rows = counters.first;
    // Only counters that repeat every few rows; a stray second row counter
    // would have nothing to repeat by.
    final repeats = counters.skip(1).where((counter) => counter.isRepeat);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RowCounter(rows: rows.value, onChanged: onRowsChanged),
        for (final repeat in repeats)
          _RepeatCounter(counter: repeat, rows: rows.value, onRemove: () => onRemove(repeat)),
        TextButton.icon(onPressed: onAddRepeat, icon: const Icon(Icons.add), label: const Text('Add repeat counter')),
      ],
    );
  }
}

/// The row counter as a small plum pill, floating over the page when the
/// phone is sideways: "ROW − 14 +".
class CompactRowCounter extends StatelessWidget {
  const CompactRowCounter({super.key, required this.rows, required this.onChanged, this.minusButton = true});

  final int rows;
  final ValueChanged<int> onChanged;

  /// Whether to show the minus button. Where space is tight, counting back
  /// is left to the full counter.
  final bool minusButton;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Row counter',
      value: '$rows',
      increasedValue: '${rows + 1}',
      decreasedValue: '${rows > 0 ? rows - 1 : 0}',
      onIncrease: () => onChanged(rows + 1),
      onDecrease: () => onChanged(rows - 1),
      child: Material(
        color: PurlnoteColors.plum,
        elevation: 4,
        shadowColor: const Color(0x803B1C34),
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'ROW',
                  style: TextStyle(color: PurlnoteColors.blush, fontSize: 11, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 6),
                if (minusButton)
                  IconButton(
                    onPressed: () => onChanged(rows - 1),
                    color: Colors.white,
                    style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.14)),
                    icon: const Icon(Icons.remove, size: 20),
                  ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '$rows',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () => onChanged(rows + 1),
                  color: PurlnoteColors.plum,
                  style: IconButton.styleFrom(backgroundColor: PurlnoteColors.marigold),
                  icon: const Icon(Icons.add, size: 22),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RowCounter extends StatelessWidget {
  const _RowCounter({required this.rows, required this.onChanged});

  final int rows;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    // VoiceOver: swipe up or down on the counter to change it.
    return Semantics(
      label: 'Row counter',
      value: '$rows',
      increasedValue: '${rows + 1}',
      decreasedValue: '${rows > 0 ? rows - 1 : 0}',
      onIncrease: () => onChanged(rows + 1),
      onDecrease: () => onChanged(rows - 1),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        decoration: BoxDecoration(color: PurlnoteColors.cream, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            const Expanded(child: Text('Rows', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
            ExcludeSemantics(
              child: Row(
                children: [
                  IconButton.outlined(onPressed: () => onChanged(rows - 1), icon: const Icon(Icons.remove)),
                  SizedBox(
                    width: 56,
                    child: Text(
                      '$rows',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton.filled(onPressed: () => onChanged(rows + 1), icon: const Icon(Icons.add)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepeatCounter extends StatelessWidget {
  const _RepeatCounter({required this.counter, required this.rows, required this.onRemove});

  final ProjectCounter counter;
  final int rows;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final done = counter.repeatsDone(rows);
    final total = counter.totalRepeats;
    final finished = total != null && done >= total;
    final progress = total == null ? '$done done' : '$done of $total done';
    final next = finished ? 'All repeats done' : 'Next in ${counter.rowsUntilNext(rows)} rows';

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
        decoration: BoxDecoration(color: PurlnoteColors.cream, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(counter.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text('$progress · $next', style: const TextStyle(fontSize: 13, color: PurlnoteColors.plumMuted)),
                ],
              ),
            ),
            IconButton(tooltip: 'Remove ${counter.label}', onPressed: onRemove, icon: const Icon(Icons.close)),
          ],
        ),
      ),
    );
  }
}

/// Asks for a repeat counter's details, such as "Decrease every 6 rows, 8 times".
Future<({String label, int every, int? times})?> askForRepeatCounter(BuildContext context) {
  final label = TextEditingController(text: 'Decrease');
  final every = TextEditingController(text: '6');
  final times = TextEditingController();

  return showDialog<({String label, int every, int? times})>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Add a repeat counter'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: label, decoration: const InputDecoration(labelText: 'What repeats')),
          TextField(
            controller: every,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Every how many rows'),
          ),
          TextField(
            controller: times,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'How many times (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final rows = int.tryParse(every.text.trim());
            if (rows == null || rows < 1) return;
            final name = label.text.trim().isEmpty ? 'Repeat' : label.text.trim();
            Navigator.pop(context, (label: '$name every $rows rows', every: rows, times: int.tryParse(times.text.trim())));
          },
          child: const Text('Add'),
        ),
      ],
    ),
  );
}
