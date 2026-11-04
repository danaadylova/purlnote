// Shared helpers for the token endpoint and the spike.

export const TOKEN_URL = "https://www.ravelry.com/oauth2/token";
const TOKEN_FIELDS = ["access_token", "token_type", "expires_in", "refresh_token", "scope"];
const ERROR_FIELDS = ["error", "error_description"];


export function isConfigured(env) {
  return Boolean(env.RAVELRY_CLIENT_ID && env.RAVELRY_CLIENT_SECRET && env.APP_REDIRECT_URI);
}

export async function ravelryToken(env, form) {
  let response;
  try {
    response = await fetch(TOKEN_URL, {
      method: "POST",
      headers: {
        Authorization: "Basic " + btoa(`${env.RAVELRY_CLIENT_ID}:${env.RAVELRY_CLIENT_SECRET}`),
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      },
      body: new URLSearchParams(form).toString(),
    });
  } catch {
    return { status: 502, body: { error: "temporarily_unavailable", error_description: "Ravelry could not be reached." } };
  }

  let data;
  try {
    data = await response.json();
  } catch {
    return { status: 502, body: { error: "temporarily_unavailable", error_description: `Ravelry answered ${response.status} without JSON.` } };
  }

  if (response.ok && data && typeof data.access_token === "string") {
    return { status: 200, body: pick(data, TOKEN_FIELDS) };
  }
  const status = response.ok ? 502 : response.status;
  const body = pick(data || {}, ERROR_FIELDS);
  if (!body.error) body.error = "invalid_grant";
  return { status, body };
}

export function pick(object, fields) {
  const out = {};
  for (const field of fields) {
    if (object[field] !== undefined) out[field] = object[field];
  }
  return out;
}

export function noStore() {
  return { "Cache-Control": "no-store", Pragma: "no-cache", "Referrer-Policy": "no-referrer" };
}

export function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...noStore(), "Content-Type": "application/json" },
  });
}
