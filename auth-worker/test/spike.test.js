import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";
import { TOKEN_URL } from "../src/ravelry.js";
import { API, AUTH_URL, runChecks, scrub, esc } from "../src/spike.js";

const env = {
  RAVELRY_CLIENT_ID: "client-id",
  RAVELRY_CLIENT_SECRET: "client-secret",
  APP_REDIRECT_URI: "purlnote://oauth-callback",
  SPIKE_ENABLED: "true",
};
const realFetch = globalThis.fetch;
let calls;

// A small fake of Ravelry: token endpoint plus the API calls the spike makes.
function fakeRavelry({ maxValueBytes = 64 * 1024, refreshOk = true, commentOk = true } = {}) {
  const store = {};
  return async (input, init = {}) => {
    const url = new URL(String(input));
    const method = init.method || "GET";
    calls.push(`${method} ${url.origin}${url.pathname}`);
    const ok = (data) => new Response(JSON.stringify(data), { status: 200 });

    if (url.href === TOKEN_URL) {
      const grant = new URLSearchParams(init.body).get("grant_type");
      if (grant === "refresh_token" && !refreshOk) return new Response(JSON.stringify({ error: "invalid_grant" }), { status: 400 });
      const n = grant === "refresh_token" ? 2 : 1;
      return ok({ access_token: `secret-access-${n}`, refresh_token: `secret-refresh-${n}`, expires_in: 86400, scope: "offline message-write library-pdf" });
    }
    if (url.href.startsWith("https://files.example")) return new Response(new TextEncoder().encode("%PDF-1.7 fake"), { status: 200 });
    assert.equal(url.origin, API);
    assert.match(init.headers.Authorization, /^Bearer secret-access-/);

    switch (url.pathname) {
      case "/current_user.json":
        return ok({ user: { username: "dana" } });
      case "/app/data/set.json": {
        const [key, value] = [...new URLSearchParams(init.body)][0];
        if (value.length > maxValueBytes) return new Response("Value too large", { status: 413 });
        store[key] = value;
        return ok({ data: { [key]: value } });
      }
      case "/app/data/get.json": {
        const key = url.searchParams.get("keys");
        return ok({ data: { [key]: store[key] } });
      }
      case "/app/data/delete.json": {
        const key = url.searchParams.get("keys");
        delete store[key];
        return ok({ data: {} });
      }
      case "/people/dana/library/search.json":
        return ok({ volumes: [{ id: 7, title: "Harbour Raglan" }] });
      case "/volumes/7.json":
        return ok({ volume: { id: 7, volume_attachments: [{ product_attachment_id: 99 }] } });
      case "/product_attachments/99/generate_download_link.json":
        return ok({ download_link: { url: "https://files.example/p.pdf", expires_at: "2026-11-04T20:00:00Z" } });
      case "/projects/dana/list.json":
        return ok({ projects: [{ id: 5, name: "Harbour Raglan", permalink: "harbour-raglan" }, { id: 6, name: "Fennel Socks" }] });
      case "/comments/create.json":
        if (!commentOk) return new Response("Forbidden", { status: 403 });
        return ok({ comment: { id: 1234 } });
      default:
        return new Response("not found", { status: 404 });
    }
  };
}

beforeEach(() => {
  calls = [];
});
afterEach(() => {
  globalThis.fetch = realFetch;
});

test("start redirects to Ravelry with state and only the scopes needed", async () => {
  const req = new Request("https://w.dev/spike/start", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: "comment=1&project=raglan",
  });
  const res = await worker.fetch(req, env);
  assert.equal(res.status, 303);
  const location = new URL(res.headers.get("Location"));
  assert.equal(location.origin + location.pathname, AUTH_URL);
  assert.equal(location.searchParams.get("redirect_uri"), "https://w.dev/spike/callback");
  assert.equal(location.searchParams.get("scope"), "offline message-write");
  const cookie = res.headers.get("Set-Cookie");
  assert.match(cookie, /HttpOnly/);
  assert.ok(cookie.includes(location.searchParams.get("state") + "."));
});

test("callback refuses a state that does not match the cookie", async () => {
  globalThis.fetch = fakeRavelry();
  const req = new Request("https://w.dev/spike/callback?code=c&state=bbb", { headers: { Cookie: "purlnote_spike=aaa.e30" } });
  const res = await worker.fetch(req, env);
  assert.equal(res.status, 400);
  assert.equal(calls.length, 0);
});

test("full run: every check passes and no token appears in the page", async () => {
  globalThis.fetch = fakeRavelry();
  const options = Buffer.from(JSON.stringify({ pdf: true, comment: true, project: "raglan" })).toString("base64url");
  const req = new Request("https://w.dev/spike/callback?code=c&state=s1", { headers: { Cookie: `purlnote_spike=s1.${options}` } });
  const res = await worker.fetch(req, env);
  const html = await res.text();
  assert.equal(res.status, 200);
  assert.ok(!html.includes("secret-access") && !html.includes("secret-refresh"));
  assert.equal((html.match(/class="pass"/g) || []).length, 6);
  assert.match(html, /Signed in as dana/);
  assert.match(html, /Largest value that worked: 64 KB/);
  assert.match(html, /test key removed/);
  assert.match(html, /a real PDF/);
  assert.match(html, /Posted comment 1234 on &quot;Harbour Raglan&quot;/);
});

test("app data probe deletes the test key even when a write fails", async () => {
  globalThis.fetch = fakeRavelry({ maxValueBytes: 100 });
  const results = await runChecks(env, "c", "https://w.dev/spike/callback", { pdf: false, comment: false });
  const probe = results.find((r) => r.name === "Notes backup storage");
  assert.equal(probe.ok, false);
  assert.match(probe.detail, /1 KB write failed/);
  assert.ok(calls.includes(`POST ${API}/app/data/delete.json`));
});

test("skipped checks make no PDF or comment calls", async () => {
  globalThis.fetch = fakeRavelry();
  const results = await runChecks(env, "c", "https://w.dev/spike/callback", { pdf: false, comment: false });
  assert.deepEqual(results.filter((r) => r.ok === null).map((r) => r.name), ["Purchased PDF download", "Project comment"]);
  assert.ok(!calls.some((c) => c.includes("generate_download_link") || c.includes("comments")));
});

test("a refused comment and failed refresh are reported as failures", async () => {
  globalThis.fetch = fakeRavelry({ refreshOk: false, commentOk: false });
  const results = await runChecks(env, "c", "https://w.dev/spike/callback", { pdf: false, comment: true, project: "socks" });
  assert.equal(results.find((r) => r.name === "Refresh token").ok, false);
  const comment = results.find((r) => r.name === "Project comment");
  assert.equal(comment.ok, false);
  assert.match(comment.detail, /HTTP 403/);
});

test("scrub removes tokens and esc escapes HTML", () => {
  assert.equal(scrub("bad secret-access-1 here", ["secret-access-1"]), "bad [token] here");
  assert.equal(esc(`<a href="x">'&`), "&lt;a href=&quot;x&quot;&gt;&#39;&amp;");
});
