import 'package:flutter/material.dart';

import '../app_session.dart';
import '../library/library_models.dart';
import '../ravelry/models.dart';
import '../reader/reader_screen.dart';
import '../theme.dart';
import '../widgets/project_cover.dart';

/// The projects on the needles as big cards, swiped sideways one at a time,
/// with dots showing which one is in view.
class OnTheNeedlesCarousel extends StatefulWidget {
  const OnTheNeedlesCarousel({
    super.key,
    required this.session,
    required this.projects,
    required this.onOpen,
    required this.onArrange,
  });

  final AppSession session;
  final List<Project> projects;

  /// Opens a project's page.
  final ValueChanged<Project> onOpen;

  /// Press and hold a card: rearrange the cards, starting with that one.
  final ValueChanged<Project> onArrange;

  /// Tall enough for the cover, the numbers and the button.
  static const height = 410.0;

  /// A card's width when several sit side by side.
  static const cardWidth = 340.0;

  /// From this width the cards sit in a row instead of being swiped.
  static const rowLayoutWidth = 700.0;

  @override
  State<OnTheNeedlesCarousel> createState() => _OnTheNeedlesCarouselState();
}

class _OnTheNeedlesCarouselState extends State<OnTheNeedlesCarousel> {
  // Less than full width, so the next card peeks in and invites a swipe.
  final _pages = PageController(viewportFraction: 0.88);
  int _current = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projects = widget.projects;
    return LayoutBuilder(
      builder: (context, constraints) {
        // With room for more than one card (iPad), lay them out in a row
        // that scrolls sideways instead of one at a time.
        if (constraints.maxWidth >= OnTheNeedlesCarousel.rowLayoutWidth) {
          return SizedBox(
            height: OnTheNeedlesCarousel.height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: projects.length,
              separatorBuilder: (context, index) => const SizedBox(width: 18),
              itemBuilder: (context, index) => SizedBox(
                width: OnTheNeedlesCarousel.cardWidth,
                child: _NeedlesCard(
                  session: widget.session,
                  project: projects[index],
                  onOpen: () => widget.onOpen(projects[index]),
                onArrange: () => widget.onArrange(projects[index]),
                ),
              ),
            ),
          );
        }
        return _swiped(projects);
      },
    );
  }

  /// One card at a time, swiped sideways, with dots.
  Widget _swiped(List<Project> projects) {
    return Column(
      children: [
        SizedBox(
          height: OnTheNeedlesCarousel.height,
          child: PageView.builder(
            controller: _pages,
            padEnds: false,
            itemCount: projects.length,
            onPageChanged: (page) => setState(() => _current = page),
            itemBuilder: (context, index) => Padding(
              padding: EdgeInsets.only(left: index == 0 ? 20 : 6, right: 6),
              child: _NeedlesCard(
                session: widget.session,
                project: projects[index],
                onOpen: () => widget.onOpen(projects[index]),
                onArrange: () => widget.onArrange(projects[index]),
              ),
            ),
          ),
        ),
        if (projects.length > 1) ...[
          const SizedBox(height: 12),
          Semantics(
            label: 'Project ${_current + 1} of ${projects.length}. Swipe for more.',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < projects.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _current ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _current ? PurlnoteColors.plum : PurlnoteColors.line,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _NeedlesCard extends StatefulWidget {
  const _NeedlesCard({required this.session, required this.project, required this.onOpen, required this.onArrange});

  final AppSession session;
  final Project project;
  final VoidCallback onOpen;
  final VoidCallback onArrange;

  @override
  State<_NeedlesCard> createState() => _NeedlesCardState();
}

class _NeedlesCardState extends State<_NeedlesCard> {
  /// The project's pattern, if its PDF is on this device. Loaded once the
  /// card shows, so the button can say "Open pattern" or "Continue knitting".
  late Future<LibraryPattern?> _pattern = _load();

  Future<LibraryPattern?> _load() async {
    final pattern = await widget.session.patternForProject(widget.project);
    return pattern != null && pattern.isOnPhone ? pattern : null;
  }

  @override
  void didUpdateWidget(_NeedlesCard old) {
    super.didUpdateWidget(old);
    if (old.project != widget.project) _pattern = _load();
  }

  /// With the pattern's PDF on the phone, opens it where the knitter left
  /// off; without one, opens the project page (notes, photos, counters).
  Future<void> _continue(LibraryPattern? pattern) async {
    if (pattern == null) {
      widget.onOpen();
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ReaderScreen(session: widget.session, pattern: pattern, projectId: widget.project.id),
    ));
    // The PDF may have been added or removed meanwhile.
    if (mounted) setState(() => _pattern = _load());
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final subtitle = [project.patternName, if (project.size != null) 'Size ${project.size}'].nonNulls.join(' · ');
    return Material(
      color: PurlnoteColors.plum,
      borderRadius: BorderRadius.circular(26),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpen,
        onLongPress: widget.onArrange,
        child: FutureBuilder<LibraryPattern?>(
          future: _pattern,
          builder: (context, snapshot) {
            final loaded = snapshot.connectionState == ConnectionState.done;
            final pattern = snapshot.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The cover takes whatever height the text leaves, so larger
                // text sizes shrink the photo rather than overflow the card.
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ProjectCover(project: project),
                      const Positioned(left: 14, top: 14, child: _Tag('ON THE NEEDLES')),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  project.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: PurlnoteColors.cream,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (subtitle.isNotEmpty)
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: PurlnoteColors.blush, fontSize: 14),
                                  ),
                              ],
                            ),
                          ),
                          if (project.progressPercent != null) _ProgressRing(percent: project.progressPercent!),
                        ],
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: loaded ? () => _continue(pattern) : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: PurlnoteColors.marigold,
                          foregroundColor: PurlnoteColors.plum,
                          minimumSize: const Size.fromHeight(50),
                          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        child: Text(pattern != null ? 'Open pattern' : 'Continue knitting'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: PurlnoteColors.plum.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(color: PurlnoteColors.blush, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// How far along the project is, from the percentage set on it.
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$percent percent done',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: 56,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: percent / 100,
              strokeWidth: 6,
              strokeCap: StrokeCap.round,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              color: PurlnoteColors.marigold,
            ),
            Center(
              child: Text(
                '$percent%',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Finished projects as small cards in a row, most recent first.
class FinishedRow extends StatelessWidget {
  const FinishedRow({super.key, required this.projects, required this.onOpen});

  final List<Project> projects;
  final ValueChanged<Project> onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: projects.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final project = projects[index];
          final finished = project.completed;
          return SizedBox(
            width: 130,
            child: InkWell(
              onTap: () => onOpen(project),
              borderRadius: BorderRadius.circular(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 100,
                    child: ProjectCover(project: project, borderRadius: BorderRadius.circular(18)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  if (finished != null)
                    Text(
                      'Finished ${_shortDate(finished)}',
                      style: const TextStyle(color: PurlnoteColors.plumMuted, fontSize: 13),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "28 Oct", or "28 Oct 2024" for another year.
String _shortDate(DateTime date) {
  final dayMonth = '${date.day} ${_months[date.month - 1]}';
  return date.year == DateTime.now().year ? dayMonth : '$dayMonth ${date.year}';
}

/// Rearranges the projects on the needles: drag a project by its handle (or
/// press and hold it) to move it. [picked] is the project whose card was
/// pressed, shown highlighted. Each move is saved straight away.
Future<void> showArrangeNeedles(BuildContext context, AppSession session, {Project? picked}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: PurlnoteColors.cream,
    builder: (context) => _ArrangeNeedles(session: session, picked: picked),
  );
}

class _ArrangeNeedles extends StatefulWidget {
  const _ArrangeNeedles({required this.session, this.picked});

  final AppSession session;
  final Project? picked;

  @override
  State<_ArrangeNeedles> createState() => _ArrangeNeedlesState();
}

class _ArrangeNeedlesState extends State<_ArrangeNeedles> {
  late final List<Project> _order = widget.session.onTheNeedles;

  void _move(int from, int to) {
    setState(() => _order.insert(to, _order.removeAt(from)));
    widget.session.arrangeOnTheNeedles([for (final project in _order) project.id]);
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Semantics(
                header: true,
                child: Text('Arrange your projects', style: Theme.of(context).textTheme.titleLarge),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Drag a project up or down. The first one is the card you see first.',
                style: TextStyle(color: PurlnoteColors.plumMuted),
              ),
            ),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: _order.length,
                onReorderItem: _move,
                itemBuilder: (context, index) {
                  final project = _order[index];
                  final picked = project.id == widget.picked?.id;
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(project.id),
                    index: index,
                    child: Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: picked ? PurlnoteColors.mossLight : Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: picked ? PurlnoteColors.moss : PurlnoteColors.line),
                      ),
                      child: ListTile(
                        leading: SizedBox.square(
                          dimension: 44,
                          child: ProjectCover(project: project, borderRadius: BorderRadius.circular(10)),
                        ),
                        title: Text(project.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: index == 0 ? const Text('Shown first') : null,
                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: Semantics(
                            label: 'Move ${project.name}',
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.drag_handle, color: PurlnoteColors.plumMuted),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
