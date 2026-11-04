import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";
import { TOKEN_URL } from "../src/ravelry.js";

const env = {
  RAVELRY_CLIENT_ID: "client-id",
  RAVELRY_CLIENT_SECRET: "client-secret",
  APP_REDIRECT_URI: "purlnote://oauth-callback",
  SPIKE_ENABLED: "false",
};

let calls;
let reply;
const realFetch = globalThis.fetch;

beforeEach(() => {
  calls = [];
  reply = () => new Response(JSON.stringify({ access_token: "at-123456789", token_type: "bearer", expires_in: 86400, refresh_token: "rt-123456789", scope: "offline", extra: "dropped" }), { status: 200 });
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    return reply();
  };
});
afterEach(() => {
  globalThis.fetch = realFetch;
});

function post(body, type = "application/x-www-form-urlencoded") {
  return new Request("https://purlnote-auth.example.workers.dev/token", {
    method: "POST",
    headers: { "Content-Type": type },
    body,
  });
}

test("health reports configured", async () => {
  const res = await worker.fetch(new Request("https://x.dev/health"), env);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true, configured: true });
  assert.equal(res.headers.get("Cache-Control"), "no-store");
});

test("health reports not configured without secrets", async () => {
  const res = await worker.fetch(new Request("https://x.dev/health"), { APP_REDIRECT_URI: "purlnote://oauth-callback" });
  assert.deepEqual(await res.json(), { ok: true, configured: false });
});

test("code exchange sends Basic auth and form body to Ravelry", async () => {
  const res = await worker.fetch(post("grant_type=authorization_code&code=abc&redirect_uri=purlnote%3A%2F%2Foauth-callback"), env);
  assert.equal(res.status, 200);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, TOKEN_URL);
  assert.equal(calls[0].init.headers.Authorization, "Basic " + btoa("client-id:client-secret"));
  const sent = new URLSearchParams(calls[0].init.body);
  assert.equal(sent.get("grant_type"), "authorization_code");
  assert.equal(sent.get("code"), "abc");
  assert.equal(sent.get("redirect_uri"), "purlnote://oauth-callback");
  assert.equal(sent.get("client_secret"), null);
});

test("only standard token fields are returned", async () => {
  const res = await worker.fetch(post("grant_type=authorization_code&code=abc&redirect_uri=purlnote%3A%2F%2Foauth-callback"), env);
  const body = await res.json();
  assert.deepEqual(Object.keys(body).sort(), ["access_token", "expires_in", "refresh_token", "scope", "token_type"]);
  assert.equal(res.headers.get("Cache-Control"), "no-store");
});

test("JSON bodies are accepted", async () => {
  const res = await worker.fetch(post(JSON.stringify({ grant_type: "refresh_token", refresh_token: "rt" }), "application/json"), env);
  assert.equal(res.status, 200);
  assert.equal(new URLSearchParams(calls[0].init.body).get("refresh_token"), "rt");
});

test("refresh grant forwards only the refresh token", async () => {
  await worker.fetch(post("grant_type=refresh_token&refresh_token=rt&code=ignored"), env);
  const sent = new URLSearchParams(calls[0].init.body);
  assert.deepEqual([...sent.keys()].sort(), ["grant_type", "refresh_token"]);
});

test("a redirect other than the app's is refused without calling Ravelry", async () => {
  const res = await worker.fetch(post("grant_type=authorization_code&code=abc&redirect_uri=https%3A%2F%2Fevil.example%2Fcb"), env);
  assert.equal(res.status, 400);
  assert.equal((await res.json()).error, "invalid_request");
  assert.equal(calls.length, 0);
});

test("missing code or refresh token is refused", async () => {
  assert.equal((await worker.fetch(post("grant_type=authorization_code&redirect_uri=purlnote%3A%2F%2Foauth-callback"), env)).status, 400);
  assert.equal((await worker.fetch(post("grant_type=refresh_token"), env)).status, 400);
  assert.equal(calls.length, 0);
});

test("other grant types are refused", async () => {
  const res = await worker.fetch(post("grant_type=client_credentials"), env);
  assert.equal(res.status, 400);
  assert.equal((await res.json()).error, "unsupported_grant_type");
  assert.equal(calls.length, 0);
});

test("oversized or unknown bodies are refused", async () => {
  assert.equal((await worker.fetch(post("grant_type=refresh_token&refresh_token=" + "x".repeat(5000)), env)).status, 400);
  assert.equal((await worker.fetch(post("grant_type=refresh_token", "text/plain"), env)).status, 400);
  assert.equal((await worker.fetch(post("[1,2]", "application/json"), env)).status, 400);
  assert.equal(calls.length, 0);
});

test("Ravelry errors pass through with only error fields", async () => {
  reply = () => new Response(JSON.stringify({ error: "invalid_grant", error_description: "expired", trace: "internal" }), { status: 400 });
  const res = await worker.fetch(post("grant_type=refresh_token&refresh_token=rt"), env);
  assert.equal(res.status, 400);
  assert.deepEqual(await res.json(), { error: "invalid_grant", error_description: "expired" });
});

test("Ravelry unreachable or non-JSON gives 502", async () => {
  globalThis.fetch = async () => {
    throw new Error("network down");
  };
  assert.equal((await worker.fetch(post("grant_type=refresh_token&refresh_token=rt"), env)).status, 502);
  globalThis.fetch = async () => new Response("<html>oops</html>", { status: 503 });
  assert.equal((await worker.fetch(post("grant_type=refresh_token&refresh_token=rt"), env)).status, 502);
});

test("not configured gives 500 without calling Ravelry", async () => {
  const res = await worker.fetch(post("grant_type=refresh_token&refresh_token=rt"), { APP_REDIRECT_URI: "purlnote://oauth-callback" });
  assert.equal(res.status, 500);
  assert.equal(calls.length, 0);
});

test("wrong methods and unknown paths", async () => {
  assert.equal((await worker.fetch(new Request("https://x.dev/token"), env)).status, 405);
  assert.equal((await worker.fetch(new Request("https://x.dev/nope"), env)).status, 404);
});

test("spike is hidden unless enabled", async () => {
  assert.equal((await worker.fetch(new Request("https://x.dev/spike"), env)).status, 404);
  assert.equal((await worker.fetch(new Request("https://x.dev/spike"), { ...env, SPIKE_ENABLED: "true" })).status, 200);
});

test("main module exports only the handler (the Workers runtime rejects other exports)", async () => {
  const mod = await import("../src/index.js");
  assert.deepEqual(Object.keys(mod), ["default"]);
});
