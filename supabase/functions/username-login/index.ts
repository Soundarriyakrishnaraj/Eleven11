import {
  createAdminClient,
  createAnonymousClient,
  corsHeaders,
  jsonResponse,
  parseJson,
  rateLimitPasses,
  validUsername,
} from "../_shared/security.ts";

const invalidCredentials = { error: "Invalid username or password." };

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  const body = await parseJson(request);
  const username = body?.username;
  const password = body?.password;
  if (!validUsername(username) || typeof password !== "string" || !password) {
    return jsonResponse(invalidCredentials, 401);
  }

  try {
    const admin = createAdminClient();
    const allowed = await rateLimitPasses(
      admin,
      request,
      "username-login",
      username.toLowerCase(),
      6,
      900,
    );
    if (!allowed) {
      return jsonResponse({ error: "Too many attempts. Try again later." }, 429);
    }

    const { data: email, error: lookupError } = await admin.rpc(
      "auth_lookup_email_for_username",
      { p_username: username },
    );
    if (lookupError) throw new Error("Username lookup failed.");
    if (typeof email !== "string") return jsonResponse(invalidCredentials, 401);

    const auth = createAnonymousClient();
    const { data, error } = await auth.auth.signInWithPassword({
      email,
      password,
    });
    if (error || !data.session) return jsonResponse(invalidCredentials, 401);

    return jsonResponse({
      access_token: data.session.access_token,
      refresh_token: data.session.refresh_token,
    });
  } catch (error) {
    console.error("Username sign-in failed.", error);
    return jsonResponse({ error: "Unable to sign in. Please try again." }, 500);
  }
});
