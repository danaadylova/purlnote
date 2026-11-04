import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../app_session.dart';
import '../theme.dart';
import 'size_text.dart';
import 'step_models.dart';
import 'steps_store.dart';

/// The Steps view: the pattern one instruction at a time, with Back and
/// Next. Each step shows the page it came from, so the knitter can check it
/// against the original.
class StepsView extends StatefulWidget {
  const StepsView({
    super.key,
    required this.session,
    required this.fileSha256,
    required this.pdfPath,
    required this.projectId,
    required this.onShowPage,
    this.rows,
    this.onRowsChanged,
  });

  final AppSession session;
  final String fileSha256;
  final String pdfPath;

  /// The project's ID, or 0 when reading outside a project.
  final int projectId;

  /// Opens the PDF at a page, to see a step in the original.
  final ValueChanged<int> onShowPage;

  /// The project's row counter, if it has one. Next moves it on row steps.
  final int? rows;
  final ValueChanged<int>? onRowsChanged;

  @override
  State<StepsView> createState() => _StepsViewState();
}

class _StepsViewState extends State<StepsView> {
  StepsStore get _store => widget.session.steps;

  List<PatternStep> _all = const [];
  StepProgress _progress = const StepProgress(currentStep: 0, sizeIndex: null, nextMovesCounter: true);
  List<String> _sizeNames = const [];
  bool _showAllSizes = false;

  /// While building: "Reading page 3 of 9".
  String? _building;
  List<int> _pagesWithoutText = const [];

  /// The step the instructions start at, chosen by the knitter. Steps before
  /// it (materials, gauge, notes) are skipped.
  int? _startId;

  /// The steps to follow: from the chosen start on, without hidden ones.
  List<PatternStep> get _visible {
    final shown = _all.where((step) => !step.hidden).toList();
    final start = shown.indexWhere((step) => step.id == _startId);
    return start <= 0 ? shown : shown.sublist(start);
  }

  /// Steps before the chosen start, for "Pattern info" at the top.
  List<PatternStep> get _skipped {
    final shown = _all.where((step) => !step.hidden).toList();
    final start = shown.indexWhere((step) => step.id == _startId);
    return start <= 0 ? const [] : shown.sublist(0, start);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool rebuild = false}) async {
    var steps = await _store.stepsFor(widget.fileSha256);
    if (steps.isEmpty || rebuild) {
      setState(() => _building = 'Reading the pattern…');
      final result = await widget.session.stepBuilder.build(
        fileSha256: widget.fileSha256,
        pdfPath: widget.pdfPath,
        onPage: (page, count) {
          if (mounted) setState(() => _building = 'Reading page $page of $count');
        },
      );
      _pagesWithoutText = result.pagesWithoutText;
      steps = await _store.stepsFor(widget.fileSha256);
    }
    final progress = await _store.progress(widget.projectId, widget.fileSha256);
    final sizes = await widget.session.stepBuilder.sizeNames(fileSha256: widget.fileSha256, pdfPath: widget.pdfPath);
    final startId = await _store.startStepId(widget.fileSha256);
    if (!mounted) return;
    setState(() {
      _all = steps;
      _progress = progress;
      _sizeNames = sizes;
      _startId = startId;
      _building = null;
    });
    // First time with this pattern: ask the size, then where to start.
    if (progress.sizeIndex == null && _sizeNames.isNotEmpty) await _pickSize();
    if (startId == null && mounted && _all.length > 3) await _chooseStart(firstTime: true);
  }

  /// Lets the knitter pick where the instructions begin. The steps before it
  /// stay readable under "Pattern info" but Back and Next skip them.
  ///
  /// The first time, closing the list without choosing starts at the very
  /// first step, so the question isn't asked on every open; the menu's
  /// "Choose where the pattern starts" changes it any time.
  Future<void> _chooseStart({bool firstTime = false}) async {
    final shown = _all.where((step) => !step.hidden).toList();
    final chosen = await showModalBottomSheet<PatternStep>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _StepPicker(
        title: 'Where do you start?',
        explanation: 'Patterns usually begin with materials, gauge and notes. Tap the first instruction you\'ll work, '
            'such as the cast on. Everything before it stays under Pattern info.',
        steps: shown,
        highlighted: shown.where((step) => step.id == _startId).firstOrNull ?? suggestedStart(shown),
        highlightLabel: _startId == null ? 'Suggested' : 'Current start',
      ),
    );
    final start = chosen ?? (firstTime && shown.isNotEmpty ? shown.first : null);
    if (start?.id == null) return;
    await _store.saveStartStepId(widget.fileSha256, start!.id!);
    setState(() => _startId = start.id);
    await _save(StepProgress(currentStep: 0, sizeIndex: _progress.sizeIndex, nextMovesCounter: _progress.nextMovesCounter));
  }

  /// Jumps to any step, listed by section.
  Future<void> _jumpTo() async {
    final visible = _visible;
    final index = _progress.currentStep.clamp(0, visible.length - 1);
    final chosen = await showModalBottomSheet<PatternStep>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _StepPicker(
        title: 'Go to a step',
        steps: visible,
        highlighted: visible[index],
        highlightLabel: 'You are here',
      ),
    );
    if (chosen == null) return;
    await _save(StepProgress(
      currentStep: visible.indexOf(chosen),
      sizeIndex: _progress.sizeIndex,
      nextMovesCounter: _progress.nextMovesCounter,
    ));
  }

  void _showPatternInfo() {
    final skipped = _skipped;
    final sizeIndex = _progress.sizeIndex;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          children: [
            Semantics(header: true, child: Text('Pattern info', style: Theme.of(context).textTheme.titleLarge)),
            const SizedBox(height: 8),
            for (final step in skipped)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(sizeIndex == null ? step.text : textForSize(step.text, sizeIndex)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(StepProgress progress) async {
    setState(() => _progress = progress);
    await _store.saveProgress(widget.projectId, widget.fileSha256, progress);
  }

  Future<void> _move(int by) async {
    final visible = _visible;
    final from = _progress.currentStep.clamp(0, visible.length - 1);
    final to = (from + by).clamp(0, visible.length - 1);
    if (to == from) return;
    // Next on a row finishes that row, so the counter goes up; Back undoes it.
    final rowStep = by > 0 ? visible[from] : visible[to];
    final rows = widget.rows;
    if (_progress.nextMovesCounter && rowStep.isRow && rows != null) {
      widget.onRowsChanged?.call(rows + (by > 0 ? 1 : -1));
    }
    await _save(StepProgress(
      currentStep: to,
      sizeIndex: _progress.sizeIndex,
      nextMovesCounter: _progress.nextMovesCounter,
    ));
  }

  Future<void> _pickSize() async {
    final chosen = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SizePicker(names: _sizeNames, current: _progress.sizeIndex),
    );
    if (chosen == null) return;
    await _save(StepProgress(
      currentStep: _progress.currentStep,
      sizeIndex: chosen < 0 ? null : chosen,
      nextMovesCounter: _progress.nextMovesCounter,
    ));
  }

  Future<void> _fix(PatternStep step, PatternStep? next) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Fix this step', style: TextStyle(fontWeight: FontWeight.w700))),
            ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit text'), onTap: () => Navigator.pop(context, 'edit')),
            if (next != null)
              ListTile(
                leading: const Icon(Icons.merge_type),
                title: const Text('Join with next step'),
                onTap: () => Navigator.pop(context, 'join'),
              ),
            ListTile(leading: const Icon(Icons.call_split), title: const Text('Split into two steps'), onTap: () => Navigator.pop(context, 'split')),
            ListTile(leading: const Icon(Icons.visibility_off_outlined), title: const Text('Hide this step'), onTap: () => Navigator.pop(context, 'hide')),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text('See it on page ${step.sourcePage}'),
              onTap: () => Navigator.pop(context, 'page'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'edit':
        final text = await _askForText(title: 'Edit step', initial: step.text);
        if (text != null && text.trim().isNotEmpty) await _store.editText(step, text.trim());
      case 'join':
        await _store.join(step, next!);
      case 'split':
        final text = await _askForText(
          title: 'Split step',
          initial: step.text,
          help: 'Put a line break where the second step should start.',
        );
        final at = text?.indexOf('\n') ?? -1;
        if (text != null && at > 0) {
          await _store.editText(step, text.replaceFirst('\n', ' '));
          await _store.split(widget.fileSha256, step.copyWith(text: text.replaceFirst('\n', ' ')), at);
        }
      case 'hide':
        await _store.hide(step);
      case 'page':
        widget.onShowPage(step.sourcePage);
        return;
    }
    final steps = await _store.stepsFor(widget.fileSha256);
    if (mounted) setState(() => _all = steps);
  }

  Future<String?> _askForText({required String title, required String initial, String? help}) {
    final text = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: text,
          autofocus: true,
          minLines: 3,
          maxLines: 10,
          decoration: InputDecoration(helperText: help, helperMaxLines: 3),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, text.text), child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _confirmRebuild() async {
    final rebuild = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rebuild steps?'),
        content: const Text('Your fixes to these steps are replaced by fresh steps from the PDF.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Rebuild')),
        ],
      ),
    );
    if (rebuild == true) {
      await _save(StepProgress(currentStep: 0, sizeIndex: _progress.sizeIndex, nextMovesCounter: _progress.nextMovesCounter));
      await _load(rebuild: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final building = _building;
    final visible = _visible;
    if (building != null && visible.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Semantics(liveRegion: true, child: Text(building)),
          ],
        ),
      );
    }
    if (visible.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'This PDF has no text to read, so steps can\'t be made from it. Scanned patterns and image-only charts '
            'can only be read on the page.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final index = _progress.currentStep.clamp(0, visible.length - 1);
    final step = visible[index];
    final previous = index > 0 ? visible[index - 1] : null;
    final next = index + 1 < visible.length ? visible[index + 1] : null;
    final basic = _all.isNotEmpty && _all.every((s) => s.madeBy != StepMaker.model);
    final sizeIndex = _progress.sizeIndex;

    String shown(PatternStep s) => sizeIndex == null || _showAllSizes ? s.text : textForSize(s.text, sizeIndex);

    return Column(
      children: [
        _StepsHeader(
          section: step.section,
          position: 'Step ${index + 1} of ${visible.length}',
          sizeName: sizeIndex == null || sizeIndex >= _sizeNames.length ? null : _sizeNames[sizeIndex],
          hasSizes: _sizeNames.isNotEmpty,
          nextMovesCounter: _progress.nextMovesCounter,
          onPickSize: _pickSize,
          onToggleCounter: () => _save(StepProgress(
            currentStep: _progress.currentStep,
            sizeIndex: _progress.sizeIndex,
            nextMovesCounter: !_progress.nextMovesCounter,
          )),
          onRebuild: _confirmRebuild,
          onJump: _jumpTo,
          onChooseStart: () => _chooseStart(),
        ),
        if (basic) const _Notice(text: 'Basic steps on this iPhone. Some may be split oddly; press and hold a step to fix it.'),
        if (_pagesWithoutText.isNotEmpty)
          _Notice(text: 'No text to read on page ${_pagesWithoutText.join(', ')}. Check those pages in the PDF.'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              if (index == 0 && _skipped.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _showPatternInfo,
                    icon: const Icon(Icons.info_outline),
                    label: Text('Pattern info (${_skipped.length} parts before the start)'),
                  ),
                ),
              if (previous != null)
                _SideStep(heading: previous.heading, text: shown(previous), dashed: false),
              const SizedBox(height: 10),
              GestureDetector(
                onLongPress: () => _fix(step, next),
                child: _CurrentStep(
                  step: step,
                  text: shown(step),
                  showingAllSizes: _showAllSizes || sizeIndex == null,
                  canToggleSizes: sizeIndex != null && sizeCountIn(step.text) > 1,
                  onToggleSizes: () => setState(() => _showAllSizes = !_showAllSizes),
                  onShowPage: () => widget.onShowPage(step.sourcePage),
                  onFix: () => _fix(step, next),
                ),
              ),
              const SizedBox(height: 10),
              if (next != null) _SideStep(heading: 'Next · ${next.heading}', text: shown(next), dashed: true),
            ],
          ),
        ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: index == 0 ? null : () => _move(-1),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Back', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: next == null ? null : () => _move(1),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  icon: const Icon(Icons.chevron_right),
                  label: Text(next == null ? 'Last step' : 'Next'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepsHeader extends StatelessWidget {
  const _StepsHeader({
    required this.section,
    required this.position,
    required this.sizeName,
    required this.hasSizes,
    required this.nextMovesCounter,
    required this.onPickSize,
    required this.onToggleCounter,
    required this.onRebuild,
    required this.onJump,
    required this.onChooseStart,
  });

  final String? section;
  final String position;
  final String? sizeName;
  final bool hasSizes;
  final bool nextMovesCounter;
  final VoidCallback onPickSize;
  final VoidCallback onToggleCounter;
  final VoidCallback onRebuild;
  final VoidCallback onJump;
  final VoidCallback onChooseStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onJump,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(section ?? 'Pattern', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(
                      '$position · Go to…',
                      style: const TextStyle(fontSize: 13, color: PurlnoteColors.plumMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (hasSizes)
            ActionChip(
              avatar: const Icon(Icons.straighten, size: 16),
              label: Text(sizeName == null ? 'All sizes' : 'Size $sizeName'),
              tooltip: 'Change size',
              onPressed: onPickSize,
              backgroundColor: PurlnoteColors.mossLight,
              side: BorderSide.none,
            ),
          PopupMenuButton<String>(
            tooltip: 'Steps menu',
            onSelected: (choice) {
              if (choice == 'counter') onToggleCounter();
              if (choice == 'rebuild') onRebuild();
              if (choice == 'jump') onJump();
              if (choice == 'start') onChooseStart();
              if (choice == 'size') onPickSize();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'jump', child: Text('Go to a step')),
              const PopupMenuItem(value: 'start', child: Text('Choose where the pattern starts')),
              if (hasSizes) const PopupMenuItem(value: 'size', child: Text('Change size')),
              CheckedPopupMenuItem(value: 'counter', checked: nextMovesCounter, child: const Text('Next moves the row counter')),
              const PopupMenuItem(value: 'rebuild', child: Text('Rebuild steps')),
            ],
          ),
        ],
      ),
    );
  }
}

class _CurrentStep extends StatelessWidget {
  const _CurrentStep({
    required this.step,
    required this.text,
    required this.showingAllSizes,
    required this.canToggleSizes,
    required this.onToggleSizes,
    required this.onShowPage,
    required this.onFix,
  });

  final PatternStep step;
  final String text;
  final bool showingAllSizes;
  final bool canToggleSizes;
  final VoidCallback onToggleSizes;
  final VoidCallback onShowPage;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final repeat = step.repeatIndex == null ? null : 'Repeat ${step.repeatIndex} of ${step.repeatTotal}';
    return Semantics(
      label: 'Current step',
      customSemanticsActions: {const CustomSemanticsAction(label: 'Fix this step'): onFix},
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: PurlnoteColors.moss, width: 2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    step.heading,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: PurlnoteColors.mossDark),
                  ),
                ),
                if (repeat != null) _Tag(text: repeat, color: PurlnoteColors.blush),
                const SizedBox(width: 6),
                _Tag(text: step.madeBy == StepMaker.edited ? 'Fixed by you' : 'Made by Purlnote', color: PurlnoteColors.sand),
              ],
            ),
            const SizedBox(height: 10),
            Text(text, style: const TextStyle(fontSize: 22, height: 1.35, fontWeight: FontWeight.w600)),
            if (canToggleSizes)
              TextButton(
                onPressed: onToggleSizes,
                child: Text(showingAllSizes ? 'Show only my size' : 'Show every size'),
              ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: onShowPage,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text('From page ${step.sourcePage} · see the original'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideStep extends StatelessWidget {
  const _SideStep({required this.heading, required this.text, required this.dashed});

  final String heading;
  final String text;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dashed ? Colors.transparent : PurlnoteColors.sand,
        border: dashed ? Border.all(color: PurlnoteColors.inputBorder) : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '$heading · ', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: text),
        ]),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, color: PurlnoteColors.plumMuted),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: PurlnoteColors.plum)),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: PurlnoteColors.blush, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: const TextStyle(fontSize: 13)),
    );
  }
}

/// Asks which size is being made. Returns its index, -1 for "all sizes", or
/// null if dismissed.
class _SizePicker extends StatelessWidget {
  const _SizePicker({required this.names, required this.current});

  final List<String> names;
  final int? current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text('Which size are you making?', style: Theme.of(context).textTheme.titleLarge)),
            const SizedBox(height: 8),
            const Text(
              'Steps show only your numbers, so "cast on 88 (96, 104)" reads "cast on 96". '
              'Purlnote makes these steps from the PDF on this phone and can misread a pattern, '
              'so check a step against the page when something looks off.',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < names.length; i++)
                  ChoiceChip(
                    label: Text(names[i]),
                    selected: current == i,
                    onSelected: (_) => Navigator.pop(context, i),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: () => Navigator.pop(context, -1), child: const Text('Show all sizes in steps')),
          ],
        ),
      ),
    );
  }
}

/// The first step that looks like real instructions: a row or round, or a
/// cast on. Used to suggest where the pattern starts.
PatternStep? suggestedStart(List<PatternStep> steps) {
  final castOn = RegExp(r'\b(cast on|co\b|ch(ain)? \d+|make a slip knot|set-?up)', caseSensitive: false);
  for (final step in steps) {
    if (step.isRow || castOn.hasMatch(step.text)) return step;
  }
  return steps.isEmpty ? null : steps.first;
}

/// A list of steps grouped by section, for choosing the start or jumping to
/// a step. Returns the step tapped.
class _StepPicker extends StatelessWidget {
  const _StepPicker({
    required this.title,
    required this.steps,
    this.explanation,
    this.highlighted,
    this.highlightLabel,
  });

  final String title;
  final String? explanation;
  final List<PatternStep> steps;
  final PatternStep? highlighted;
  final String? highlightLabel;

  @override
  Widget build(BuildContext context) {
    final highlightIndex = highlighted == null ? 0 : steps.indexOf(highlighted!);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (context, scroll) {
        final rows = <Widget>[];
        String? section;
        for (var i = 0; i < steps.length; i++) {
          final step = steps[i];
          if (step.section != section) {
            section = step.section;
            if (section != null) {
              rows.add(Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Semantics(
                  header: true,
                  child: Text(section, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ));
            }
          }
          final isHighlighted = i == highlightIndex;
          rows.add(ListTile(
            selected: isHighlighted,
            selectedTileColor: PurlnoteColors.mossLight,
            selectedColor: PurlnoteColors.plum,
            title: Text(step.heading, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(step.text, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: isHighlighted && highlightLabel != null
                ? Text(highlightLabel!, style: const TextStyle(fontWeight: FontWeight.w700, color: PurlnoteColors.mossDark))
                : Text('p.${step.sourcePage}', style: const TextStyle(color: PurlnoteColors.plumMuted)),
            onTap: () => Navigator.pop(context, step),
          ));
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
                  if (explanation != null) ...[
                    const SizedBox(height: 6),
                    Text(explanation!, style: const TextStyle(height: 1.4)),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                children: rows,
              ),
            ),
          ],
        );
      },
    );
  }
}
