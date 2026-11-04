import 'package:flutter/material.dart';

import '../app_session.dart';
import 'library_screen.dart';
import 'notebook_screen.dart';
import 'you_screen.dart';

/// The tabs: Notebook, Library and You. Each tab keeps its place when the
/// knitter switches away and back.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});

  final AppSession session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          NotebookScreen(session: widget.session),
          LibraryScreen(session: widget.session),
          YouScreen(session: widget.session),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (tab) => setState(() => _tab = tab),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Notebook'),
          NavigationDestination(icon: Icon(Icons.local_library_outlined), selectedIcon: Icon(Icons.local_library), label: 'Library'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'You'),
        ],
      ),
    );
  }
}
