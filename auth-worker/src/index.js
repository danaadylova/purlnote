// Purlnote token-exchange function (Cloudflare Worker).
//
// Ravelry's OAuth 2.0 token endpoint only accepts the client ID and secret in a
// Basic auth header, and a phone app cannot keep a secret. This function holds
// the secret and swaps authorization codes and refresh tokens for access tokens.
// It stores nothing and never logs codes or tokens. Retire it once Ravelry's
// OAuth 2.1 (with PKCE) ships.

import { handleSpike } from "./spike.js";
import { isConfigured, ravelryToken, json, noStore } from "./ravelry.js";

const MAX_BODY_BYTES = 4096;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (url.pathname === "/health") {
        if (request.method !== "GET") return methodNotAllowed("GET");
        return json(200, { ok: true, configured: isConfigured(env) });
      }
      if (url.pathname === "/token") {
        if (request.method !== "POST") return methodNotAllowed("POST");
        return await handleToken(request, env);
      }
      if (url.pathname === "/spike" || url.pathname.startsWith("/spike/")) {
        if (env.SPIKE_ENABLED !== "true") return json(404, { error: "not_found" });
        return await handleSpike(request, env, url);
      }
      return json(404, { error: "not_found" });
    } catch {
      // Deliberately no details: an error message could carry request data.
      return json(500, { error: "server_error" });
    }
  },
};

async function handleToken(request, env) {
  if (!isConfigured(env)) {
    return json(500, { error: "server_error", error_description: "Sign-in is not set up yet." });
  }

  const params = await readParams(request);
  if (params === null) {
    return json(400, { error: "invalid_request", error_description: "Body must be a small form or JSON object." });
  }

  const grantType = params.grant_type;
  let upstream;
  if (grantType === "authorization_code") {
    if (!params.code) return invalid("code is required.");
    // Only the app's own redirect is allowed, so a code meant for another
    // client can't be redeemed here with a made-up redirect.
    if (params.redirect_uri !== env.APP_REDIRECT_URI) return invalid("redirect_uri is not allowed.");
    upstream = { grant_type: "authorization_code", code: params.code, redirect_uri: params.redirect_uri };
  } else if (grantType === "refresh_token") {
    if (!params.refresh_token) return invalid("refresh_token is required.");
    upstream = { grant_type: "refresh_token", refresh_token: params.refresh_token };
  } else {
    return json(400, { error: "unsupported_grant_type" });
  }

  const result = await ravelryToken(env, upstream);
  return json(result.status, result.body);
}

// Calls Ravelry's token endpoint. Returns { status, body } where body holds
// only the standard token or error fields. Shared with the spike.

async function readParams(request) {
  const declared = Number(request.headers.get("Content-Length") || "0");
  if (declared > MAX_BODY_BYTES) return null;
  const text = await request.text();
  if (text.length > MAX_BODY_BYTES) return null;

  const type = (request.headers.get("Content-Type") || "").toLowerCase();
  if (type.startsWith("application/json")) {
    try {
      const value = JSON.parse(text);
      if (!value || typeof value !== "object" || Array.isArray(value)) return null;
      return stringsOnly(value);
    } catch {
      return null;
    }
  }
  if (type.startsWith("application/x-www-form-urlencoded")) {
    return Object.fromEntries(new URLSearchParams(text));
  }
  return null;
}

function stringsOnly(object) {
  const out = {};
  for (const [key, value] of Object.entries(object)) {
    if (typeof value === "string") out[key] = value;
  }
  return out;
}

function invalid(description) {
  return json(400, { error: "invalid_request", error_description: description });
}

function methodNotAllowed(allow) {
  return new Response(JSON.stringify({ error: "method_not_allowed" }), {
    status: 405,
    headers: { ...noStore(), "Content-Type": "application/json", Allow: allow },
  });
}
