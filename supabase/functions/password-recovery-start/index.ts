import {
  createAdminClient,
  createAnonymousClient,
  corsHeaders,
  jsonResponse,
  parseJson,
  rateLimitPasses,
  validEmail,
  validUsername,
} from "../_shared/security.ts";

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  const body = await parseJson(request);
  const username = body?.username;
  const email = body?.email;
  const dateOfBirth = body?.dateOfBirth;
  if (
    !validUsername(username) ||
    !validEmail(email) ||
    typeof dateOfBirth !== "string" ||
    !/^\d{4}-\d{2}-\d{2}$/.test(dateOfBirth)
  ) {
    return jsonResponse({ error: "Unable to process this request." }, 400);
  }

  try {
    const admin = createAdminClient();
    const allowed = await rateLimitPasses(
      admin,
      request,
      "password-recovery",
      `${username.toLowerCase()}:${email.toLowerCase()}`,
      3,
      3600,
    );
    if (!allowed) {
      return jsonResponse({ error: "Too many attempts. Try again later." }, 429);
    }

    const { data, error } = await admin.rpc("auth_recovery_identity", {
      p_username: username,
      p_email: email,
      p_date_of_birth: dateOfBirth,
    });
    if (error) throw new Error("Recovery identity verification failed.");

    const account = Array.isArray(data) ? data[0] : null;
    if (!account || typeof account.email !== "string") {
      return jsonResponse({ accepted: true }, 202);
    }

    const auth = createAnonymousClient();
    const { error: deliveryError } = await auth.auth.resetPasswordForEmail(
      account.email,
    );
    if (deliveryError) {
      console.error("Password recovery email could not be sent.");
      return jsonResponse(
        { error: "Unable to process this request. Please try again later." },
        503,
      );
    }

    return jsonResponse({ accepted: true }, 202);
  } catch (error) {
    console.error("Password recovery request failed.", error);
    return jsonResponse(
      { error: "Unable to process this request. Please try again later." },
      500,
    );
  }
});
