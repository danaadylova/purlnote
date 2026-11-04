import 'package:flutter/material.dart';

import '../theme.dart';

/// A short tour of what Purlnote does, shown on the first launch and from
/// You → How Purlnote works. Four pages; Skip leaves at any point.
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key, required this.onDone, this.doneLabel = 'Get started'});

  /// Called when the knitter finishes or skips the tour.
  final VoidCallback onDone;

  /// The last page's button.
  final String doneLabel;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _pages = PageController();
  int _current = 0;

  static const _content = [
    _Page(
      title: 'Your patterns, always with you',
      body:
          'Bring in pattern PDFs from Files, or from your Ravelry library. '
          'They open offline, right where you left off.',
      picture: _PatternsPicture(),
    ),
    _Page(
      title: 'Mark it up',
      body: 'Highlight the size you\'re making, write with the pen, and pin notes to any spot on the page.',
      picture: _MarkUpPicture(),
    ),
    _Page(
      title: 'Never lose your row',
      body:
          'The row ruler sits on the line you\'re knitting. Press and hold it to move it, '
          'and count rows and repeats with the counters.',
      picture: _RulerPicture(),
    ),
    _Page(
      title: 'One step at a time',
      body:
          'Steps turns a pattern into one instruction at a time, with just your size\'s numbers. '
          'Pick where to start, then tap Next.',
      picture: _StepsPicture(),
    ),
  ];

  bool get _onLastPage => _current == _content.length - 1;

  void _next() {
    if (_onLastPage) {
      widget.onDone();
    } else {
      _pages.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 8, 0),
                // Kept on the last page too, so it's always in the same place.
                child: TextButton(onPressed: widget.onDone, child: const Text('Skip')),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (page) => setState(() => _current = page),
                children: _content,
              ),
            ),
            _Dots(count: _content.length, current: _current),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: FilledButton(
                onPressed: _next,
                child: Text(_onLastPage ? widget.doneLabel : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.body, required this.picture});

  final String title;
  final String body;
  final Widget picture;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        const SizedBox(height: 8),
        ExcludeSemantics(child: AspectRatio(aspectRatio: 1.1, child: picture)),
        const SizedBox(height: 28),
        Semantics(header: true, child: Text(title, style: text.headlineMedium)),
        const SizedBox(height: 12),
        Text(body, style: text.bodyLarge?.copyWith(color: PurlnoteColors.plumMuted, height: 1.45)),
      ],
    );
  }
}

/// Which page the tour is on.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Page ${current + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == current ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == current ? PurlnoteColors.plum : PurlnoteColors.line,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}

// The pictures are drawn with plain widgets, so they need no image files and
// stay sharp at any size.

/// A rounded panel the pictures sit on.
class _Panel extends StatelessWidget {
  const _Panel({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(28)),
      padding: const EdgeInsets.all(28),
      child: child,
    );
  }
}

/// A pattern page: a white sheet with grey lines for text.
class _Sheet extends StatelessWidget {
  const _Sheet({this.lines = 9, this.children = const []});

  final int lines;

  /// Drawn on top of the lines, such as a highlight or a ruler.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Color(0x1A3B1C34), blurRadius: 18, offset: Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < lines; i++)
                  FractionallySizedBox(
                    widthFactor: i.isEven ? 0.92 : 0.7,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(color: PurlnoteColors.line, borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _PatternsPicture extends StatelessWidget {
  const _PatternsPicture();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      color: PurlnoteColors.mossLight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: -0.12,
            child: const FractionallySizedBox(widthFactor: 0.55, heightFactor: 0.8, child: _Sheet()),
          ),
          Transform.rotate(
            angle: 0.08,
            child: const FractionallySizedBox(widthFactor: 0.55, heightFactor: 0.8, child: _Sheet()),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: PurlnoteColors.moss, borderRadius: BorderRadius.circular(22)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Import from Files', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkUpPicture extends StatelessWidget {
  const _MarkUpPicture();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      color: PurlnoteColors.blush,
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.7,
          child: _Sheet(
            children: [
              // A highlighted row.
              Positioned(
                left: 12,
                right: 40,
                top: 70,
                height: 16,
                child: Container(color: PurlnoteColors.marigold.withValues(alpha: 0.45)),
              ),
              // A pinned note.
              Positioned(
                right: 14,
                top: 30,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(color: PurlnoteColors.plum, shape: BoxShape.circle),
                  child: const Icon(Icons.sticky_note_2_outlined, color: PurlnoteColors.marigold, size: 18),
                ),
              ),
              // A pen mark.
              const Positioned(
                left: 24,
                bottom: 28,
                child: Icon(Icons.gesture, color: PurlnoteColors.marigoldDark, size: 44),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RulerPicture extends StatelessWidget {
  const _RulerPicture();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      color: PurlnoteColors.sand,
      child: Stack(
        children: [
          Center(
            child: FractionallySizedBox(
              widthFactor: 0.75,
              child: _Sheet(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final bandTop = constraints.maxHeight * 0.45;
                      return Stack(
                        children: [
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: bandTop,
                            child: Container(color: const Color(0x8CFFF8EE)),
                          ),
                          Positioned(
                            top: bandTop,
                            left: 0,
                            right: 0,
                            height: 22,
                            child: Container(
                              decoration: BoxDecoration(
                                color: PurlnoteColors.marigold.withValues(alpha: 0.15),
                                border: const Border.symmetric(
                                  horizontal: BorderSide(color: PurlnoteColors.marigoldDark, width: 2),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: bandTop + 22,
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(color: const Color(0x8CFFF8EE)),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: PurlnoteColors.plum, borderRadius: BorderRadius.circular(16)),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('ROW', style: TextStyle(color: PurlnoteColors.blush, fontSize: 11, fontWeight: FontWeight.w700)),
                  Text(
                    '31',
                    style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, height: 1.1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepsPicture extends StatelessWidget {
  const _StepsPicture();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      color: PurlnoteColors.plum,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: PurlnoteColors.cream, borderRadius: BorderRadius.circular(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'STEP 12 OF 48 · SIZE M',
                style: TextStyle(color: PurlnoteColors.plumMuted, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              const Text(
                'Cast on 33 sts. Join to work in the round.',
                style: TextStyle(color: PurlnoteColors.plum, fontSize: 20, fontWeight: FontWeight.w700, height: 1.25),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: const LinearProgressIndicator(
                        value: 12 / 48,
                        minHeight: 6,
                        backgroundColor: PurlnoteColors.line,
                        color: PurlnoteColors.marigold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: PurlnoteColors.moss, borderRadius: BorderRadius.circular(14)),
                    child: const Text('Next', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
