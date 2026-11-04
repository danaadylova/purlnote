# Purlnote

An offline-first iPhone app (Flutter, so Android can follow) that works as a phone client for a Ravelry account: projects, stash, the pattern library, and a pattern reader whose notes can go straight to a project's comments.

The design (RFC and screen mockups) is kept outside the repo.

## What's here

| Folder | What it is |
| --- | --- |
| `app/` | The Flutter app. See `app/README.md`. |
| `auth-worker/` | The sign-in function (Cloudflare Worker). Holds Ravelry's client secret so the app doesn't have to. Also serves the milestone 0 check page at `/spike`. |
| `codemagic.yaml` | Builds the iPhone app in the cloud and sends it to TestFlight (setup steps at the top of the file). |
| `.github/workflows/` | Checks the app and the function on every push, and deploys the function to Cloudflare from `main`. |

## Milestones

All five are built and checked by the tests; they still need trying on a real iPhone through TestFlight.

0. **Spike** (done, go): sign-in, refresh, profile, notes-backup size, a PDF download and a project comment, checked against the real Ravelry API. Access tokens last one hour, not the 24 the docs say.
1. **Sign-in and Notebook**: welcome, Ravelry sign-in, first sync, projects on the needles, queue, stash.
2. **Editing and sync**: projects and stash edited offline, sent later, with field-by-field conflict choices.
3. **Library and reader**: purchases and imported PDFs, downloads, the reader with highlights, pen, notes, row ruler, counters and a screen-awake timer.
4. **Notes to project comments**: a note goes to the page, the project's comments or its notes; comments post once, even after a dropped connection. Notes backup to the knitter's Ravelry app data.
5. **Step-by-step**: the pattern one instruction at a time, made on the phone by Apple's on-device model, or by rules on other iPhones.

Still to do by hand: TestFlight testing, the closed beta, App Store submission, and the release check for step-by-step (ten real patterns, no wrong stitch count or row number after picking a size).

## Setting up milestone 0

Secrets go only into Cloudflare and GitHub's encrypted repository secrets, never into files in this repo.

1. **Cloudflare**: free account. Create an API token from the "Edit Cloudflare Workers" template and note the account ID.
2. **Ravelry**: an OAuth 2.0 app with two redirect URIs:
   - `purlnote://oauth-callback` (the phone app)
   - `https://purlnote-auth.<your-subdomain>.workers.dev/spike/callback` (the check page)
3. **GitHub** › Settings › Secrets and variables › Actions, add:
   `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `RAVELRY_CLIENT_ID`, `RAVELRY_CLIENT_SECRET`.
4. Re-run the latest **auth-worker** workflow (Actions tab). It deploys once the secrets are there.
5. Open `https://purlnote-auth.<your-subdomain>.workers.dev/spike`, choose the optional checks, and sign in. Every row should say Pass. Delete the test comment on Ravelry afterwards.
