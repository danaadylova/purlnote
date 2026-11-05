import 'package:flutter/material.dart';

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
            Expanded(child: pages),
          ],
        ),
      );
    }

    return Scaffold(
      body: pages,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (tab) => setState(() => _tab = tab),
        destinations: [
          for (final section in _sections)
            NavigationDestination(
              icon: Icon(section.icon),
              selectedIcon: Icon(section.selectedIcon),
              label: section.label,
            ),
        ],
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
