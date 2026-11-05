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
  const OnTheNeedlesCarousel({super.key, required this.session, required this.projects, required this.onOpen});

  final AppSession session;
  final List<Project> projects;

  /// Opens a project's page.
  final ValueChanged<Project> onOpen;

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

/// What a card needs beyond the project record: the pattern PDF, if it's on
/// the phone, and the project's counters.
typedef _CardDetails = ({LibraryPattern? pattern, List<ProjectCounter> counters});

class _NeedlesCard extends StatefulWidget {
  const _NeedlesCard({required this.session, required this.project, required this.onOpen});

  final AppSession session;
  final Project project;
  final VoidCallback onOpen;

  @override
  State<_NeedlesCard> createState() => _NeedlesCardState();
}

class _NeedlesCardState extends State<_NeedlesCard> {
  late Future<_CardDetails> _details = _load();

  Future<_CardDetails> _load() async {
    final pattern = await widget.session.patternForProject(widget.project);
    final counters = await widget.session.reader.countersFor(widget.project.id);
    return (pattern: pattern != null && pattern.isOnPhone ? pattern : null, counters: counters);
  }

  @override
  void didUpdateWidget(_NeedlesCard old) {
    super.didUpdateWidget(old);
    if (old.project != widget.project) _details = _load();
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
    // Counters may have moved while reading.
    if (mounted) setState(() => _details = _load());
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
        child: FutureBuilder<_CardDetails>(
          future: _details,
          builder: (context, snapshot) {
            final details = snapshot.data;
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
                      if (details != null && details.counters.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            for (final (i, counter) in details.counters.take(3).indexed) ...[
                              if (i > 0) const SizedBox(width: 8),
                              Expanded(child: _CounterTile(counter: counter)),
                            ],
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: details == null ? null : () => _continue(details.pattern),
                        style: FilledButton.styleFrom(
                          backgroundColor: PurlnoteColors.marigold,
                          foregroundColor: PurlnoteColors.plum,
                          minimumSize: const Size.fromHeight(50),
                          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        child: Text(details?.pattern != null ? 'Open pattern' : 'Continue knitting'),
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

/// One counter's name and value, such as "ROW 31" or "REPEAT 3 / 8".
class _CounterTile extends StatelessWidget {
  const _CounterTile({required this.counter});

  final ProjectCounter counter;

  @override
  Widget build(BuildContext context) {
    final total = counter.totalRepeats;
    final value = total == null ? '${counter.value}' : '${counter.value} / $total';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            counter.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: PurlnoteColors.blush, fontSize: 11, fontWeight: FontWeight.w700),
          ),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        ],
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
