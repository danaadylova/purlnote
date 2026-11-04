import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Where the row ruler is: on which page, and where on it.
///
/// The ruler belongs to the page, not the screen, so it stays on the same
/// pattern row while the knitter scrolls or zooms, and comes back on that row
/// when the pattern is opened again.
class RulerPosition {
  const RulerPosition({required this.page, required this.top, required this.height, required this.visible});

  /// A new ruler a third of the way down [page].
  const RulerPosition.startOn(this.page)
      : top = 0.33,
        height = defaultHeight,
        visible = true;

  final int page;

  /// The band's top edge, as a fraction of the page's height (0 to 1).
  final double top;

  /// The band's height, as a fraction of the page's height.
  final double height;
  final bool visible;

  static const defaultHeight = 0.035;
  static const minHeight = 0.015;
  static const maxHeight = 0.15;

  /// How far one tap moves the ruler: a quarter of its height. Small steps
  /// mean the knitter never jumps past the row they're on; four taps move
  /// one full row.
  double get step => height / 4;

  RulerPosition copyWith({int? page, double? top, double? height, bool? visible}) {
    return RulerPosition(
      page: page ?? this.page,
      top: top ?? this.top,
      height: height ?? this.height,
      visible: visible ?? this.visible,
    );
  }

  /// Moved by [by] (a fraction of the page height; positive is down). Past
  /// the bottom of a page it continues at the top of the next, and past the
  /// top at the bottom of the previous, within [pageCount] pages.
  RulerPosition movedBy(double by, {required int pageCount}) {
    var newTop = top + by;
    var newPage = page;
    if (newTop > 1 - height) {
      if (page < pageCount) {
        newPage = page + 1;
        newTop = 0;
      } else {
        newTop = 1 - height;
      }
    } else if (newTop < 0) {
      if (page > 1) {
        newPage = page - 1;
        newTop = 1 - height;
      } else {
        newTop = 0;
      }
    }
    return copyWith(page: newPage, top: newTop);
  }

  /// Taller or shorter by [by], keeping the band's middle where it is.
  RulerPosition resizedBy(double by) {
    final newHeight = (height + by).clamp(minHeight, maxHeight);
    final middle = top + height / 2;
    return copyWith(height: newHeight, top: (middle - newHeight / 2).clamp(0.0, 1 - newHeight));
  }
}

/// The ruler drawn on one page: the band, and the rest of the page dimmed so
/// the current row stands out. Pages other than the ruler's are dimmed
/// whole. Button moves are animated, so the eye can follow them.
///
/// Press and hold the band to pick it up, then drag it to another row; it
/// follows the finger exactly and is put down where it's let go. Short
/// touches and swipes on the band still scroll the page as usual.
class RulerOverlay extends StatefulWidget {
  const RulerOverlay({super.key, required this.ruler, required this.page, required this.onDragged, required this.onDropped});

  final RulerPosition ruler;
  final int page;

  /// While dragging: the band's new top, as a fraction of the page height.
  final ValueChanged<double> onDragged;

  /// When let go, so the position can be saved.
  final VoidCallback onDropped;

  @override
  State<RulerOverlay> createState() => _RulerOverlayState();
}

class _RulerOverlayState extends State<RulerOverlay> {
  static const _dim = Color(0x8CFFF8EE);
  static const _duration = Duration(milliseconds: 220);

  bool _dragging = false;
  double _topWhenPickedUp = 0;

  @override
  Widget build(BuildContext context) {
    final ruler = widget.ruler;
    if (widget.page != ruler.page) {
      return const IgnorePointer(child: ColoredBox(color: _dim, child: SizedBox.expand()));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageHeight = constraints.maxHeight;
        final top = ruler.top * pageHeight;
        final band = ruler.height * pageHeight;
        // While dragging, the band follows the finger with no delay.
        final duration = _dragging ? Duration.zero : _duration;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: duration,
              curve: Curves.easeOut,
              top: 0,
              left: 0,
              right: 0,
              height: top,
              child: const IgnorePointer(child: ColoredBox(color: _dim)),
            ),
            AnimatedPositioned(
              duration: duration,
              curve: Curves.easeOut,
              top: top + band,
              left: 0,
              right: 0,
              bottom: 0,
              child: const IgnorePointer(child: ColoredBox(color: _dim)),
            ),
            AnimatedPositioned(
              duration: duration,
              curve: Curves.easeOut,
              // The touch area reaches a little past the band, so a thin
              // ruler is still easy to pick up.
              top: top - 12,
              left: 0,
              right: 0,
              height: band + 24,
              child: Semantics(
                label: 'Row ruler. Press and hold, then drag to move it.',
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onLongPressStart: (_) {
                    HapticFeedback.mediumImpact();
                    setState(() {
                      _dragging = true;
                      _topWhenPickedUp = ruler.top;
                    });
                  },
                  onLongPressMoveUpdate: (details) {
                    final moved = _topWhenPickedUp + details.offsetFromOrigin.dy / pageHeight;
                    widget.onDragged(moved.clamp(0.0, 1 - ruler.height));
                  },
                  onLongPressEnd: (_) {
                    setState(() => _dragging = false);
                    widget.onDropped();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: PurlnoteColors.marigold.withValues(alpha: _dragging ? 0.25 : 0.12),
                        border: Border.symmetric(
                          horizontal: BorderSide(color: PurlnoteColors.marigoldDark, width: _dragging ? 3 : 2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Controls for the ruler, shown while it's on: move up or down in small
/// steps (hold to keep moving), and make the band taller or shorter to fit
/// the pattern's rows.
class RulerControls extends StatelessWidget {
  const RulerControls({super.key, required this.onMove, required this.onResize});

  /// Called with -1 (up) or 1 (down), once per step.
  final ValueChanged<int> onMove;

  /// Called with -1 (shorter) or 1 (taller).
  final ValueChanged<int> onResize;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          const Text('Ruler', style: TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          _HoldButton(icon: Icons.keyboard_arrow_up, label: 'Move ruler up', onStep: () => onMove(-1)),
          const SizedBox(width: 8),
          _HoldButton(icon: Icons.keyboard_arrow_down, label: 'Move ruler down', onStep: () => onMove(1)),
          const SizedBox(width: 16),
          IconButton(
            tooltip: 'Shorter ruler',
            onPressed: () => onResize(-1),
            icon: const Icon(Icons.unfold_less),
          ),
          IconButton(
            tooltip: 'Taller ruler',
            onPressed: () => onResize(1),
            icon: const Icon(Icons.unfold_more),
          ),
        ],
      ),
    );
  }
}

/// A button that steps once on tap and keeps stepping, slowly, while held.
class _HoldButton extends StatefulWidget {
  const _HoldButton({required this.icon, required this.label, required this.onStep});

  final IconData icon;
  final String label;
  final VoidCallback onStep;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  bool _held = false;

  Future<void> _holdDown() async {
    _held = true;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    while (_held && mounted) {
      widget.onStep();
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onStep,
      child: GestureDetector(
        onTap: widget.onStep,
        onLongPressStart: (_) => _holdDown(),
        onLongPressEnd: (_) => _held = false,
        onLongPressCancel: () => _held = false,
        child: Container(
          width: 56,
          height: 44,
          decoration: BoxDecoration(
            color: PurlnoteColors.mossLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(widget.icon, color: PurlnoteColors.mossDark),
        ),
      ),
    );
  }
}
