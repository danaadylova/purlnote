# Purlnote app

The Flutter app: the first-launch tour, the Notebook, projects kept on the phone or synced with Ravelry, the pattern library and reader, notes posted to project comments, the notes backup, and step-by-step instructions.

## How it fits together

```
lib/
  main.dart              Wires everything up at launch and picks the screen for the current stage.
  config.dart            Addresses and the Ravelry client ID (public; passed in at build time).
  app_paths.dart         Finds saved files again after iOS moves the app's folder on an update.
  app_session.dart       App state and the actions screens can take (sign in, refresh, sign out).
  theme.dart             Colors from the mockups.
  auth/
    auth_service.dart    Ravelry sign-in through the system browser sheet, and keeping a valid token.
    tokens.dart          The tokens, and where they are kept (the Keychain).
  ravelry/
    ravelry_client.dart  Reads from Ravelry's API; refreshes the token once on 401; uses ETags.
    models.dart          The fields of projects, queue items, stash yarns and the user that screens show.
  data/
    local_database.dart  The SQLite database every screen reads from.
    sync_engine.dart     Sends waiting edits, then copies the knitter's lists from Ravelry.
    outbox.dart          Saves edits on the phone, sends them, and holds conflicts for the knitter.
    pending_edit.dart    One edit that hasn't reached Ravelry yet.
    local_projects.dart  Projects kept only on this phone (negative IDs), for use without Ravelry.
  library/
    library_models.dart  Patterns (purchases and imports), their files, and counters.
    library_store.dart   Reads and writes the library and per-pattern settings.
    pdf_files.dart       Downloads purchased PDFs and imports PDFs from Files.
  reader/
    reader_screen.dart   The reader: files, pages, tools, counters, Page | Steps.
    page_marks.dart      Highlights, pen strokes and note pins drawn on a page.
    reader_store.dart    Reading spots, annotations and counters.
    row_ruler.dart       The row ruler: kept on the page's row, moved in steps or by press and drag.
    counters_bar.dart    The row counter and repeat counters.
    awake_timer.dart     Keeps the screen on while reading.
  notes/
    note_sheet.dart      The New note sheet and the comment-permission explainer.
    project_comments.dart Posts notes as project comments, never twice.
    notes_backup.dart    Backs up notes and counters to the knitter's Ravelry app data.
  projects/
    project_notes.dart   A project's notes as a dated list.
    project_photos.dart  Adding and deleting project photos, on Ravelry or on the phone.
  steps/
    step_builder.dart    Reads a PDF's text and makes steps (on-device model or rules).
    rule_splitter.dart   The rules: rows, rounds, headings, written-out repeats.
    size_text.dart       Picks one size's numbers out of "88 (96, 104)", "88/96/104" or "31 33 35".
    step_models.dart     A step, and a project's place in the steps.
    steps_store.dart     Steps, the knitter's fixes, and each project's place.
    steps_view.dart      One instruction at a time, with Back and Next.
  screens/               Tour, Welcome, first sync, tabs, Notebook, Library, project, stash, queue, More.
  widgets/               Pieces shared by several screens, such as project covers.
assets/hello.jpg         The photo on the tour's hello page.
ios/Runner/AppDelegate.swift  The bridge to Apple's on-device model for step-by-step.
test/                    Unit and widget tests, with a fake Ravelry in test/support.
```

Rules the code follows:

- **Ravelry is optional.** Without an account everything is kept on the phone, and nothing is sent anywhere.
- **Screens never wait on the network.** They show what is in the local database; the sync engine updates it.
- **Only sign-in goes through our server.** The app sends the one-time sign-in code to the sign-in function (`auth-worker/`), which adds the client secret. Everything else goes straight from the phone to Ravelry.
- **Edits never wait on the network either.** They show at once and are sent later. Before sending, the record is read from Ravelry again; a field changed there since the knitter started editing becomes a conflict for them to settle, so nobody's change is silently overwritten.
- **Tokens live only in the Keychain**, never in the database or logs. PDF downloads use a separate sign-in, because Ravelry's PDF permission comes with shorter-lived tokens.
- **PDFs never leave the phone.** Notes and highlights belong to a file's SHA-256, so they come back if the same PDF is downloaded or imported again. Step-by-step reads the PDF on the phone, never in the cloud.
- **Comments are public and can't be edited on Ravelry**, so the app says so before posting, and checks before any retry that a comment wasn't already posted.

## Running it

```
cd app
flutter pub get
flutter test
flutter run --dart-define=RAVELRY_CLIENT_ID=<the Ravelry app's client ID>
```

The client ID is not a secret (it appears in every sign-in link). The client *secret* never goes in the app.
