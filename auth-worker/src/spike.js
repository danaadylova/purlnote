// Milestone 0 check ("spike"): one page that signs in with Ravelry and tests,
// server-side, what Purlnote depends on. Tokens never reach the browser.
//
//   GET /spike            form: pick optional checks, then "Sign in with Ravelry"
//   POST /spike/start     sets a state cookie and redirects to Ravelry
//   GET /spike/callback   exchanges the code and runs the checks
//
// Turned on only when SPIKE_ENABLED is "true"; turn it off after milestone 0.

import { ravelryToken, noStore } from "./ravelry.js";

export const AUTH_URL = "https://www.ravelry.com/oauth2/auth";
export const API = "https://api.ravelry.com";
const COOKIE = "purlnote_spike";
export const PROBE_KEY = "purlnote_spike_probe";
export const PROBE_SIZES = [1, 8, 32, 64, 128, 256, 512]; // KB
const COMMENT_BODY = "Purlnote test comment (milestone 0 check). Safe to delete.";

export async function handleSpike(request, env, url) {
  if (!env.RAVELRY_CLIENT_ID || !env.RAVELRY_CLIENT_SECRET) {
    return page("Not set up", "<p>The Ravelry client ID and secret are not set on this function yet.</p>", 500);
  }
  if (url.pathname === "/spike" && request.method === "GET") return startPage(url);
  if (url.pathname === "/spike/start" && request.method === "POST") return start(request, env, url);
  if (url.pathname === "/spike/callback" && request.method === "GET") return callback(request, env, url);
  return page("Not found", "<p>Nothing here.</p>", 404);
}

function callbackUrl(url) {
  return `${url.origin}/spike/callback`;
}

function startPage(url) {
  const body = `
<p>This signs in with your Ravelry account and checks, on the server, what Purlnote needs:
sign-in, refresh, your profile, and how much the notes backup can store. No token is shown.</p>
<p>Redirect URI to register on the Ravelry app: <code>${esc(callbackUrl(url))}</code></p>
<form method="post" action="/spike/start">
  <fieldset>
    <legend>Optional checks</legend>
    <label><input type="checkbox" name="pdf" value="1"> Download one purchased PDF (uses 1 of your 100 daily downloads; the file is thrown away)</label>
    <label><input type="checkbox" name="comment" value="1"> Post a public test comment on one of my projects</label>
    <label>Project name contains <input type="text" name="project" maxlength="80" autocomplete="off"></label>
  </fieldset>
  <button type="submit">Sign in with Ravelry</button>
</form>`;
  return page("Purlnote milestone 0 check", body);
}

async function start(request, env, url) {
  const form = await request.formData();
  const options = {
    pdf: form.get("pdf") === "1",
    comment: form.get("comment") === "1",
    project: String(form.get("project") || "").slice(0, 80),
  };
  const scopes = ["offline"];
  if (options.comment) scopes.push("message-write");
  if (options.pdf) scopes.push("library-pdf");

  const state = randomHex(16);
  const auth = new URL(AUTH_URL);
  auth.searchParams.set("response_type", "code");
  auth.searchParams.set("client_id", env.RAVELRY_CLIENT_ID);
  auth.searchParams.set("redirect_uri", callbackUrl(url));
  auth.searchParams.set("scope", scopes.join(" "));
  auth.searchParams.set("state", state);

  const cookieValue = `${state}.${b64url(JSON.stringify(options))}`;
  return new Response(null, {
    status: 303,
    headers: {
      ...noStore(),
      Location: auth.toString(),
      "Set-Cookie": `${COOKIE}=${cookieValue}; Path=/spike; HttpOnly; Secure; SameSite=Lax; Max-Age=600`,
    },
  });
}

async function callback(request, env, url) {
  const cookie = readCookie(request, COOKIE);
  const clear = `${COOKIE}=; Path=/spike; HttpOnly; Secure; SameSite=Lax; Max-Age=0`;

  if (url.searchParams.get("error")) {
    return page("Sign-in not finished", `<p>Ravelry said: ${esc(url.searchParams.get("error"))}</p><p><a href="/spike">Start again</a></p>`, 400, clear);
  }
  const [state, packed] = (cookie || "").split(".");
  if (!state || state !== url.searchParams.get("state")) {
    return page("Sign-in expired", `<p>This sign-in didn't start here or took over 10 minutes.</p><p><a href="/spike">Start again</a></p>`, 400, clear);
  }
  let options = { pdf: false, comment: false, project: "" };
  try {
    options = { ...options, ...JSON.parse(unb64url(packed)) };
  } catch {
    // keep defaults
  }
  const code = url.searchParams.get("code");
  if (!code) return page("No code", `<p>Ravelry didn't send a sign-in code.</p>`, 400, clear);

  const results = await runChecks(env, code, callbackUrl(url), options);
  return page("Milestone 0 results", renderResults(results), 200, clear);
}

// Runs every check in order. Each result: { name, ok, detail }. "ok: null"
// means skipped. Token values are scrubbed from every detail string.
export async function runChecks(env, code, redirectUri, options) {
  const results = [];
  const secrets = [];
  const add = (name, ok, detail) => results.push({ name, ok, detail: scrub(String(detail), secrets) });

  // 1. Code exchange
  const exchanged = await ravelryToken(env, { grant_type: "authorization_code", code, redirect_uri: redirectUri });
  if (exchanged.status !== 200) {
    add("Sign-in (code exchange)", false, `HTTP ${exchanged.status}: ${exchanged.body.error || ""} ${exchanged.body.error_description || ""}`);
    return results;
  }
  let token = exchanged.body;
  secrets.push(token.access_token, token.refresh_token);
  add("Sign-in (code exchange)", true, `Scopes granted: ${token.scope || "(not listed)"}; expires in ${token.expires_in ?? "?"} s; refresh token: ${token.refresh_token ? "yes" : "no"}`);

  // 2. Refresh
  if (token.refresh_token) {
    const refreshed = await ravelryToken(env, { grant_type: "refresh_token", refresh_token: token.refresh_token });
    if (refreshed.status === 200) {
      secrets.push(refreshed.body.access_token, refreshed.body.refresh_token);
      add("Refresh token", true, `New access token issued; new refresh token: ${refreshed.body.refresh_token ? "yes" : "no"}`);
      token = { ...token, ...refreshed.body };
    } else {
      add("Refresh token", false, `HTTP ${refreshed.status}: ${refreshed.body.error || ""} ${refreshed.body.error_description || ""}`);
    }
  } else {
    add("Refresh token", false, "No refresh token was issued (is the offline scope allowed for this app?)");
  }

  const api = (path, init = {}) => ravelryApi(token.access_token, path, init);

  // 3. Current user
  let username = null;
  const me = await api("/current_user.json");
  if (me.ok && me.data?.user?.username) {
    username = me.data.user.username;
    add("Current user", true, `Signed in as ${username}`);
  } else {
    add("Current user", false, me.problem);
    return results;
  }

  // 4. Notes backup size (app data store)
  add("Notes backup storage", ...(await probeAppData(api)));

  // 5. Optional PDF download
  if (options.pdf) add("Purchased PDF download", ...(await probePdf(api, username)));
  else add("Purchased PDF download", null, "Skipped");

  // 6. Optional project comment
  if (options.comment) add("Project comment", ...(await probeComment(api, username, options.project)));
  else add("Project comment", null, "Skipped");

  return results;
}

export async function ravelryApi(accessToken, path, init = {}) {
  let response;
  try {
    response = await fetch(API + path, {
      ...init,
      headers: { Authorization: `Bearer ${accessToken}`, Accept: "application/json", ...(init.headers || {}) },
    });
  } catch {
    return { ok: false, status: 0, problem: `Could not reach ${path}` };
  }
  let data = null;
  let text = "";
  try {
    text = await response.text();
    data = JSON.parse(text);
  } catch {
    // not JSON
  }
  if (!response.ok) {
    return { ok: false, status: response.status, data, problem: `HTTP ${response.status} from ${path}: ${text.slice(0, 200)}` };
  }
  return { ok: true, status: response.status, data };
}

function form(values) {
  return {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(values).toString(),
  };
}

// Writes values of growing size to one key, reads each back, then deletes it.
export async function probeAppData(api) {
  let largest = 0;
  let failure = "";
  for (const kb of PROBE_SIZES) {
    const value = probeValue(kb * 1024);
    const set = await api("/app/data/set.json", form({ [PROBE_KEY]: value }));
    if (!set.ok) {
      failure = `${kb} KB write failed: ${set.problem}`;
      break;
    }
    const got = await api(`/app/data/get.json?keys=${PROBE_KEY}`);
    const stored = got.ok ? got.data?.data?.[PROBE_KEY] : undefined;
    if (stored !== value) {
      failure = got.ok
        ? `${kb} KB read back ${typeof stored === "string" ? stored.length + " characters" : "nothing"}`
        : `${kb} KB read failed: ${got.problem}`;
      break;
    }
    largest = kb;
  }
  const removed = await api(`/app/data/delete.json?keys=${PROBE_KEY}`, { method: "POST" });
  const cleanup = removed.ok ? "test key removed" : `test key NOT removed (${removed.problem})`;

  if (largest === 0) return [false, `${failure}; ${cleanup}`];
  const top = PROBE_SIZES[PROBE_SIZES.length - 1];
  const summary = largest === top ? `At least ${top} KB per value works` : `Largest value that worked: ${largest} KB (${failure})`;
  return [true, `${summary}; ${cleanup}`];
}

function probeValue(length) {
  const alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  let out = "";
  let seed = length;
  while (out.length < length) {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    out += alphabet[seed % alphabet.length];
  }
  return out;
}

// Finds the first library volume with a PDF, gets a download link, downloads
// it and discards it. Uses one of the user's 100 daily download links.
export async function probePdf(api, username) {
  const library = await api(`/people/${encodeURIComponent(username)}/library/search.json?page_size=50`);
  if (!library.ok) return [false, `Library search: ${library.problem}`];
  const volumes = library.data?.volumes || [];
  if (volumes.length === 0) return [false, "The library is empty, so there was nothing to download"];

  for (const summary of volumes.slice(0, 15)) {
    const volume = await api(`/volumes/${summary.id}.json`);
    const attachment = volume.ok ? (volume.data?.volume?.volume_attachments || []).find((a) => a.product_attachment_id) : null;
    if (!attachment) continue;

    const link = await api(`/product_attachments/${attachment.product_attachment_id}/generate_download_link.json`, { method: "POST" });
    if (!link.ok) {
      return [false, link.status === 429 ? "Daily download limit reached (HTTP 429)" : `Download link: ${link.problem}`];
    }
    const downloadUrl = link.data?.download_link?.url;
    if (!downloadUrl) return [false, "Download link response had no URL"];
    let file;
    try {
      file = await fetch(downloadUrl);
    } catch {
      return [false, "The download link could not be fetched"];
    }
    if (!file.ok) return [false, `Download returned HTTP ${file.status}`];
    const bytes = new Uint8Array(await file.arrayBuffer());
    const isPdf = bytes.length > 4 && String.fromCharCode(...bytes.slice(0, 4)) === "%PDF";
    const title = summary.title || volume.data?.volume?.title || `volume ${summary.id}`;
    const expires = link.data.download_link.expires_at ? `; link expires ${link.data.download_link.expires_at}` : "";
    return [isPdf, `"${title}": ${Math.round(bytes.length / 1024)} KB, ${isPdf ? "a real PDF" : "NOT a PDF"} (discarded)${expires}`];
  }
  return [false, "None of the first 15 library items had a downloadable PDF"];
}

// Posts one public test comment on the first project whose name contains the
// given text. Delete it on Ravelry afterwards.
export async function probeComment(api, username, nameContains) {
  const wanted = (nameContains || "").trim().toLowerCase();
  if (!wanted) return [false, "No project name was given, so no comment was posted"];
  const list = await api(`/projects/${encodeURIComponent(username)}/list.json`);
  if (!list.ok) return [false, `Project list: ${list.problem}`];
  const projects = list.data?.projects || [];
  const project = projects.find((p) => String(p.name || "").toLowerCase().includes(wanted));
  if (!project) {
    if (projects.length === 0) return [false, `Ravelry listed no projects for ${username}, so no comment was posted`];
    const names = projects.slice(0, 10).map((p) => p.name).join(", ");
    return [false, `No project name contains "${nameContains}". ${projects.length} projects; first: ${names}`];
  }
  const posted = await api("/comments/create.json", form({ type: "project", commented_id: String(project.id), body: COMMENT_BODY }));
  if (!posted.ok) return [false, `Comment on "${project.name}": ${posted.problem}`];
  const where = project.permalink ? ` https://www.ravelry.com/projects/${username}/${project.permalink}` : "";
  return [true, `Posted comment ${posted.data?.comment?.id ?? "(no id returned)"} on "${project.name}". Please delete it on Ravelry:${where}`];
}

function renderResults(results) {
  const rows = results
    .map((r) => {
      const mark = r.ok === null ? "Skipped" : r.ok ? "Pass" : "Fail";
      return `<tr><th scope="row">${esc(r.name)}</th><td class="${mark.toLowerCase()}">${mark}</td><td>${esc(r.detail)}</td></tr>`;
    })
    .join("");
  return `<table><thead><tr><th scope="col">Check</th><th scope="col">Result</th><th scope="col">Detail</th></tr></thead><tbody>${rows}</tbody></table>
<p>Nothing in this table is a secret, so it is safe to share.</p><p><a href="/spike">Run again</a></p>`;
}

export function scrub(text, secrets) {
  let out = text;
  for (const secret of secrets) {
    if (secret && secret.length >= 8) out = out.split(secret).join("[token]");
  }
  return out;
}

function page(title, body, status = 200, setCookie) {
  const headers = {
    ...noStore(),
    "Content-Type": "text/html; charset=utf-8",
    "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; form-action 'self' https://www.ravelry.com",
    "X-Frame-Options": "DENY",
  };
  if (setCookie) headers["Set-Cookie"] = setCookie;
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title><style>
body{font:16px/1.5 system-ui,sans-serif;max-width:720px;margin:24px auto;padding:0 16px;color:#3B1C34;background:#FFF8EE}
h1{font-size:24px} fieldset{border:1px solid #9A8576;border-radius:8px;margin:16px 0} label{display:block;padding:8px 0}
button{background:#3F5C37;color:#fff;border:0;border-radius:10px;padding:12px 18px;font:inherit;font-weight:700;min-height:44px}
table{border-collapse:collapse;width:100%} th,td{border-bottom:1px solid #D8C5AE;padding:8px;text-align:left;vertical-align:top}
.pass{color:#2F4729;font-weight:700} .fail{color:#8A2B2B;font-weight:700} .skipped{color:#6E5566} code{word-break:break-all}
</style></head><body><h1>${esc(title)}</h1>${body}</body></html>`;
  return new Response(html, { status, headers });
}

export function esc(value) {
  return String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

function readCookie(request, name) {
  const header = request.headers.get("Cookie") || "";
  for (const part of header.split(";")) {
    const [key, ...rest] = part.trim().split("=");
    if (key === name) return rest.join("=");
  }
  return null;
}

function randomHex(bytes) {
  const array = new Uint8Array(bytes);
  crypto.getRandomValues(array);
  return Array.from(array, (b) => b.toString(16).padStart(2, "0")).join("");
}

function b64url(text) {
  return btoa(unescape(encodeURIComponent(text))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function unb64url(text) {
  const padded = text.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((text.length + 3) % 4);
  return decodeURIComponent(escape(atob(padded)));
}
