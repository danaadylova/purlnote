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

/// The ruler drawn on one page: a marigold band across the row, with the
/// pattern left fully readable around it. Button moves are animated, so the
/// eye can follow them.
///
/// Press and hold the band to pick it up, then drag it to another row, on
/// this page or the next. The reader follows the finger from there (see
/// [onPickedUp]), since the drag can leave this page. Short touches and
/// swipes on the band still scroll the page as usual.
class RulerOverlay extends StatelessWidget {
  const RulerOverlay({
    super.key,
    required this.ruler,
    required this.page,
    required this.dragging,
    required this.onPickedUp,
  });

  final RulerPosition ruler;
  final int page;

  /// Whether the ruler is being dragged: drawn bolder, and moved without
  /// animation so it stays under the finger.
  final bool dragging;

  /// Called when the band is picked up, with how far below the band's top
  /// edge the finger is, in pixels.
  final ValueChanged<double> onPickedUp;

  static const _duration = Duration(milliseconds: 220);

  /// How far the touch area reaches past the band, so a thin ruler is still
  /// easy to pick up.
  static const _grabMargin = 12.0;

  @override
  Widget build(BuildContext context) {
    if (page != ruler.page) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageHeight = constraints.maxHeight;
        final top = ruler.top * pageHeight;
        final band = ruler.height * pageHeight;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: dragging ? Duration.zero : _duration,
              curve: Curves.easeOut,
              top: top - _grabMargin,
              left: 0,
              right: 0,
              height: band + _grabMargin * 2,
              child: Semantics(
                label: 'Row ruler. Press and hold, then drag to move it.',
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onLongPressStart: (details) {
                    HapticFeedback.mediumImpact();
                    onPickedUp(details.localPosition.dy - _grabMargin);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: _grabMargin),
                    child: Container(
                      decoration: BoxDecoration(
                        color: PurlnoteColors.marigold.withValues(alpha: dragging ? 0.22 : 0.1),
                        border: Border.symmetric(
                          horizontal: BorderSide(color: PurlnoteColors.marigoldDark, width: dragging ? 3 : 2),
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
  const RulerControls({super.key, required this.onMove, required this.onResize, this.compact = false});

  /// Just the buttons, without the white bar and its label, for the floating
  /// controls when the phone is sideways.
  final bool compact;

  /// Called with -1 (up) or 1 (down), once per step.
  final ValueChanged<int> onMove;

  /// Called with -1 (shorter) or 1 (taller).
  final ValueChanged<int> onResize;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HoldButton(icon: Icons.keyboard_arrow_up, label: 'Move ruler up', onStep: () => onMove(-1)),
          const SizedBox(width: 6),
          _HoldButton(icon: Icons.keyboard_arrow_down, label: 'Move ruler down', onStep: () => onMove(1)),
          IconButton(tooltip: 'Shorter ruler', onPressed: () => onResize(-1), icon: const Icon(Icons.unfold_less)),
          IconButton(tooltip: 'Taller ruler', onPressed: () => onResize(1), icon: const Icon(Icons.unfold_more)),
        ],
      );
    }
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
