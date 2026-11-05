import 'package:flutter/material.dart';

/// Screen sizes where the layout changes.
abstract final class Breakpoints {
  /// From here, the app shows a side rail instead of bottom tabs, and screens
  /// use two columns.
  static const wide = 840.0;

  /// The shortest side of an iPad; every iPhone is narrower than this.
  static const tablet = 600.0;

  /// The widest a column of text or a form should get, so lines stay easy
  /// to read on a big screen.
  static const readable = 680.0;
}

/// Whether there's room for the two-column (iPad) layouts. A big iPhone
/// held sideways is wide but short, so it keeps the phone layout.
bool isWide(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width >= Breakpoints.wide && size.shortestSide >= Breakpoints.tablet;
}

/// Keeps [child] no wider than a comfortable reading width, centred. On a
/// phone it changes nothing.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.child, this.maxWidth = Breakpoints.readable});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}

/// Side margins that keep content at a comfortable reading width in the
/// middle of a wide screen. Zero on a phone.
EdgeInsets readableSides(BuildContext context, {double maxWidth = Breakpoints.readable}) {
  final spare = MediaQuery.sizeOf(context).width - maxWidth;
  return EdgeInsets.symmetric(horizontal: spare > 0 ? spare / 2 : 0);
}

/// [base] padding for a scrolling list, widened on big screens so the list's
/// content stays at a comfortable reading width while it still scrolls from
/// anywhere on the screen.
EdgeInsets readablePadding(BuildContext context, EdgeInsets base) => base + readableSides(context);
