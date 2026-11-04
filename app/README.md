# Purlnote app

The Flutter app. Milestone 1 covers sign-in with Ravelry, the first sync, and a read-only Notebook (projects on the needles, the queue, the stash and every other project).

## How it fits together

```
lib/
  main.dart              Wires everything up at launch and picks the screen for the current stage.
  config.dart            Addresses and the Ravelry client ID (public; passed in at build time).
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
    sync_engine.dart     Copies the knitter's lists from Ravelry into the database.
  screens/               Welcome, first sync, Notebook, project, stash and queue.
  widgets/               Pieces shared by several screens.
test/                    Unit and widget tests, with a fake Ravelry in test/support.
```

Rules the code follows:

- **Screens never wait on the network.** They show what is in the local database; the sync engine updates it.
- **Only sign-in goes through our server.** The app sends the one-time sign-in code to the sign-in function (`auth-worker/`), which adds the client secret. Everything else goes straight from the phone to Ravelry.
- **Tokens live only in the Keychain**, never in the database or logs.

## Running it

```
cd app
flutter pub get
flutter test
flutter run --dart-define=RAVELRY_CLIENT_ID=<the Ravelry app's client ID>
```

The client ID is not a secret (it appears in every sign-in link). The client *secret* never goes in the app.
