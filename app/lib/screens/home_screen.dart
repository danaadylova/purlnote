import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_session.dart';
import '../layout.dart';
import '../theme.dart';
import 'library_screen.dart';
import 'more_screen.dart';
import 'notebook_screen.dart';

/// The three sections: Notebook, Library and More. On a phone they're tabs
/// along the bottom; on an iPad, a plum rail down the side. Each keeps its
/// place when the knitter switches away and back.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});

  final AppSession session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  static const _sections = [
    (label: 'Notebook', icon: Icons.menu_book_outlined, selectedIcon: Icons.menu_book),
    (label: 'Library', icon: Icons.local_library_outlined, selectedIcon: Icons.local_library),
    (label: 'More', icon: Icons.more_horiz, selectedIcon: Icons.more_horiz),
  ];

  @override
  Widget build(BuildContext context) {
    // Light status bar icons over the Notebook's plum band, dark elsewhere.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _tab == 0 ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: _layout(context),
    );
  }

  Widget _layout(BuildContext context) {
    final pages = IndexedStack(
      index: _tab,
      children: [
        NotebookScreen(session: widget.session),
        LibraryScreen(session: widget.session),
        MoreScreen(session: widget.session),
      ],
    );

    if (isWide(context)) {
      return Scaffold(
        body: Row(
          children: [
            _SideRail(
              selected: _tab,
              onSelected: (tab) => setState(() => _tab = tab),
            ),
            Expanded(
              child: DecoratedBox(decoration: const BoxDecoration(gradient: plumFade), child: pages),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      // The screens run on under the floating tab bar, so the page shows
      // around its rounded ends. Lists leave room at their end for it.
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: DecoratedBox(decoration: const BoxDecoration(gradient: plumFade), child: pages),
      bottomNavigationBar: _FloatingTabBar(selected: _tab, onSelected: (tab) => setState(() => _tab = tab)),
    );
  }
}

/// The phone's section switcher: a plum bar with rounded ends floating above
/// the bottom edge. The chosen section sits in a marigold pill with its name;
/// the others show their icon.
class _FloatingTabBar extends StatelessWidget {
  const _FloatingTabBar({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
        child: Material(
          elevation: 8,
          shadowColor: const Color(0x803B1C34),
          borderRadius: BorderRadius.circular(30),
          clipBehavior: Clip.antiAlias,
          child: DecoratedBox(
            decoration: const BoxDecoration(gradient: plumGlowBand),
            child: SizedBox(
              height: 60,
              child: Row(
                children: [
                  for (final (index, section) in _HomeScreenState._sections.indexed)
                    Expanded(
                      flex: index == selected ? 3 : 2,
                      child: _TabButton(
                        label: section.label,
                        icon: index == selected ? section.selectedIcon : section.icon,
                        selected: index == selected,
                        onTap: () => onSelected(index),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(horizontal: selected ? 16 : 10, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? PurlnoteColors.marigold : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: selected ? PurlnoteColors.plum : PurlnoteColors.blush),
                if (selected) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: const TextStyle(color: PurlnoteColors.plum, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The iPad's section switcher: the app mark on top, then the sections, on
/// plum.
class _SideRail extends StatelessWidget {
  const _SideRail({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: selected,
      onDestinationSelected: onSelected,
      backgroundColor: PurlnoteColors.plum,
      indicatorColor: PurlnoteColors.marigold,
      labelType: NavigationRailLabelType.all,
      minWidth: 96,
      groupAlignment: -0.85,
      selectedIconTheme: const IconThemeData(color: PurlnoteColors.plum),
      unselectedIconTheme: const IconThemeData(color: PurlnoteColors.blush),
      selectedLabelTextStyle: const TextStyle(color: PurlnoteColors.cream, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: const TextStyle(color: PurlnoteColors.blush),
      leading: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 20),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: PurlnoteColors.marigold, borderRadius: BorderRadius.circular(13)),
          child: const ExcludeSemantics(
            child: Text(
              'p',
              style: TextStyle(color: PurlnoteColors.plum, fontSize: 30, fontWeight: FontWeight.w800, height: 1),
            ),
          ),
        ),
      ),
      destinations: [
        for (final section in _HomeScreenState._sections)
          NavigationRailDestination(
            icon: Icon(section.icon),
            selectedIcon: Icon(section.selectedIcon),
            label: Text(section.label),
          ),
      ],
    );
  }
}
