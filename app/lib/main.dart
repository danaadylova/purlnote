import 'package:flutter/material.dart';

import 'app_session.dart';
import 'auth/auth_service.dart';
import 'auth/tokens.dart';
import 'config.dart';
import 'data/local_database.dart';
import 'data/outbox.dart';
import 'data/sync_engine.dart';
import 'library/library_store.dart';
import 'library/pdf_files.dart';
import 'notes/notes_backup.dart';
import 'notes/project_comments.dart';
import 'ravelry/ravelry_client.dart';
import 'screens/first_sync_screen.dart';
import 'screens/home_screen.dart';
import 'screens/welcome_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Wire the pieces together once, at launch.
  final config = AppConfig.fromEnvironment();
  final auth = AuthService(config: config, tokenStore: SecureTokenStore());
  final database = await LocalDatabase.open();
  final ravelry = RavelryClient(baseUrl: config.ravelryApiUrl, auth: auth);

  // Purchased PDFs use their own sign-in: Ravelry's PDF permission comes with
  // shorter-lived tokens, so they're kept apart from the main ones.
  final pdfAuth = AuthService(
    config: config,
    tokenStore: SecureTokenStore(name: 'ravelry_pdf'),
    scopes: AuthService.pdfDownloadScopes,
  );
  final pdfFiles = PdfFiles(
    library: LibraryStore(database),
    ravelry: ravelry,
    pdfRavelry: RavelryClient(baseUrl: config.ravelryApiUrl, auth: pdfAuth),
  );

  final session = AppSession(
    auth: auth,
    pdfAuth: pdfAuth,
    pdfFiles: pdfFiles,
    comments: ProjectComments(ravelry: ravelry, database: database),
    backup: NotesBackup(ravelry: ravelry, database: database),
    database: database,
    sync: SyncEngine(
      ravelry: ravelry,
      database: database,
      outbox: Outbox(ravelry: ravelry, database: database),
    ),
  );

  runApp(PurlnoteApp(session: session));
  await session.start();
}

class PurlnoteApp extends StatelessWidget {
  const PurlnoteApp({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Purlnote',
      theme: buildPurlnoteTheme(),
      debugShowCheckedModeBanner: false,
      // Rebuilds whenever the session changes, showing the screen for the
      // current stage.
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) => switch (session.stage) {
          AppStage.starting => const _Launching(),
          AppStage.signedOut => WelcomeScreen(session: session),
          AppStage.firstSync => FirstSyncScreen(session: session),
          AppStage.ready => HomeScreen(session: session),
        },
      ),
    );
  }
}

class _Launching extends StatelessWidget {
  const _Launching();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
