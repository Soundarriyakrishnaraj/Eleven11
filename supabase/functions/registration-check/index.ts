
import {
  createAdminClient,
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

  // Normalize input consistently.
  const username =
    typeof body?.username === "string"
      ? body.username.trim()
      : "";

  const email =
    typeof body?.email === "string"
      ? body.email.trim().toLowerCase()
      : "";

  if (!validUsername(username) || !validEmail(email)) {
    return jsonResponse(
      { error: "Enter valid account details." },
      400,
    );
  }

  try {
    const admin = createAdminClient();

    const allowed = await rateLimitPasses(
      admin,
      request,
      "registration-check",
      `${username.toLowerCase()}:${email}`,
      8,
      900,
    );

    if (!allowed) {
      return jsonResponse(
        { error: "Too many attempts. Try again later." },
        429,
      );
    }

    const { data, error } = await admin.rpc(
      "auth_registration_availability",
      {
        p_username: username,
        p_email: email,
      },
    );

    if (
      error ||
      !Array.isArray(data) ||
      data.length !== 1
    ) {
      throw new Error("Registration availability check failed.");
    }

    const result = data[0];

    return jsonResponse({
      usernameAvailable: result.username_exists !== true,
      emailAvailable: result.email_exists !== true,
    });
  } catch (error) {
    console.error(
      "Registration availability check failed.",
      error,
    );

    return jsonResponse(
      {
        error: "Unable to validate account details. Please try again.",
      },
      500,
    );
  }
});
