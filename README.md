<img src="design/app_icon_1024.png" alt="Purlnote app icon: a marigold p on plum" width="96">

# Purlnote

A knitting and crochet notebook for iPhone. Read your pattern PDFs with notes, highlights and a row ruler that stay where you left them, follow a pattern one step at a time, and keep track of your projects. It works fully on its own, and can connect to a Ravelry account if you have one.

Purlnote is in beta on TestFlight, with the App Store release coming next.

## What it does

**Patterns**
- Import pattern PDFs from Files, or download the ones you bought on Ravelry.
- Highlight the size you're making, write with a pen, and pin notes anywhere on a page.
- A row ruler sits on the line you're knitting. Move it in small steps, or press and hold to drag it. It comes back on the same row next time.
- Row counters and repeat counters for each project, and a timer that keeps the screen awake while you knit.

**Step by step**
- Turns a pattern into one instruction at a time, with Back and Next.
- Pick your size once, and each step shows only your number: "Cast on 96 sts" instead of "Cast on 88 (96, 104) sts".
- Choose where to start, so you can skip the pattern's introduction.
- Made on the phone: by Apple's on-device model where it's available, and by built-in rules everywhere else. Patterns are never uploaded.

**Projects**
- The Notebook shows the projects on your needles as big cards you swipe through, with finished projects underneath.
- Notes, photos and counters for each project.
- With Ravelry connected: your Ravelry projects, stash, queue and purchased patterns, edited offline and sent when you're back online. A note can also be posted as a comment on the project.

**Getting started**
- A short tour on first launch, with a Skip button.
- Use it straight away on your phone, or sign in with Ravelry. You can connect Ravelry later, or never.

## Privacy

- Your PDFs, notes, highlights and counters stay on your phone.
- There are no ads, no analytics and no Purlnote account.
- With Ravelry connected, the app talks directly to Ravelry. The only exception is sign-in itself, which goes through a small sign-in function that keeps Ravelry's client secret out of the app. That function stores and logs nothing.
- Ravelry sign-in happens in Apple's secure sign-in sheet, so Purlnote never sees your password. Sign-in tokens are kept in the iPhone Keychain.

## Feedback

Ideas, bugs, or just hello: **unraveled.makes@gmail.com**, or **More → Send feedback** in the app.

## For developers

| Folder | What it is |
| --- | --- |
| `app/` | The Flutter app. [`app/README.md`](app/README.md) explains how the code fits together and how to run it. |
| `auth-worker/` | The sign-in function (a Cloudflare Worker). Ravelry only accepts its client secret from a server, so this holds it and swaps sign-in codes for tokens. |
| `design/` | The app icon and the script that draws it. |
| `codemagic.yaml` | Builds the iPhone app in the cloud and uploads it to TestFlight. Setup steps are at the top of the file. |
| `.github/workflows/` | On every push: format, analyze and test the app; test the sign-in function and deploy it to Cloudflare from `main`. |

### Secrets

No secret lives in this repository. The Ravelry client secret, the Cloudflare API token and the App Store Connect key are stored only as GitHub repository secrets or Codemagic encrypted variables. The Ravelry client ID is public by design; it appears in every sign-in link.

### Setting up your own copy

1. **Ravelry:** create an OAuth 2.0 app with the redirect URI `purlnote://oauth-callback`.
2. **Cloudflare:** a free account, with an API token made from the "Edit Cloudflare Workers" template.
3. **GitHub** › Settings › Secrets and variables › Actions: add `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `RAVELRY_CLIENT_ID` and `RAVELRY_CLIENT_SECRET`. The **auth-worker** workflow deploys the sign-in function once they're there.
4. **Codemagic:** follow the steps at the top of `codemagic.yaml` to sign and upload iPhone builds.

Purlnote is not made by or affiliated with Ravelry.
