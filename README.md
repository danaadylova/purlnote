# Purlnote

An offline-first iPhone app (Flutter, so Android can follow) that works as a phone client for a Ravelry account: projects, stash, the pattern library, and a pattern reader whose notes can go straight to a project's comments.

The design (RFC and screen mockups) is kept outside the repo.

## What's here

| Folder | What it is |
| --- | --- |
| `app/` | The Flutter app. See `app/README.md`. |
| `auth-worker/` | The sign-in function (Cloudflare Worker). Holds Ravelry's client secret so the app doesn't have to. Also serves the milestone 0 check page at `/spike`. |
| `.github/workflows/` | Checks the app and the function on every push, and deploys the function to Cloudflare from `main`. |

## Milestones

0. **Spike** (done): sign-in, refresh, profile, notes-backup size, one PDF download and one project comment, checked against the real Ravelry API. Go/no-go for the rest.
1. Sign-in and read-only notebook (in progress).
2. Editing and sync.
3. Pattern library and reader.
4. Notes to project comments, then closed beta.
5. Step-by-step instructions (after launch).

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
