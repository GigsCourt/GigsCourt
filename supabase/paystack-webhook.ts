import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { create, getNumericDate } from "https://deno.land/x/djwt@v2.2/mod.ts";
import { createHmac } from "https://deno.land/std@0.177.0/node/crypto.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

async function getAccessToken(): Promise<string> {
  const serviceAccount = {
    client_email: Deno.env.get("FIREBASE_SERVICE_ACCOUNT_EMAIL")!,
    private_key: Deno.env.get("FIREBASE_SERVICE_ACCOUNT_KEY")!,
  };

  const jwt = await create(
    { alg: "RS256", typ: "JWT" },
    {
      iss: serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/datastore",
      aud: "https://oauth2.googleapis.com/token",
      exp: getNumericDate(3600),
      iat: getNumericDate(0),
    },
    serviceAccount.private_key
  );

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  const data = await response.json();
  return data.access_token;
}

async function atomicIncrementCredits(token: string, projectId: string, userId: string, credits: number) {
  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/profiles/${userId}`,
    { headers: { "Authorization": `Bearer ${token}` } }
  );

  if (response.status !== 200) return;
  
  const data = await response.json();
  const fields = data.fields || {};
  const currentCredits = parseInt(fields.credits?.integerValue || "0");

  const newCredits = currentCredits + credits;

  await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/profiles/${userId}`,
    {
      method: "PATCH",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        fields: {
          credits: { integerValue: newCredits },
          updatedAt: { timestampValue: new Date().toISOString() },
        },
      }),
    }
  );
}

async function updateAdminStats(token: string, projectId: string, amount: number) {
  // Use set with merge: true so the document is auto-created if it doesn't exist
  await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/metadata/admin_stats`,
    {
      method: "PATCH",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        fields: {
          totalRevenue: { integerValue: `INCREMENT_${amount}` },
        },
      }),
    }
  );
}

async function recordPurchase(token: string, projectId: string, userId: string, amount: number, credits: number, reference: string) {
  // Check idempotency — don't process same reference twice
  const checkResponse = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/credit_purchases/${reference}`,
    { headers: { "Authorization": `Bearer ${token}` } }
  );

  if (checkResponse.status === 200) {
    return; // Already processed
  }

  // Record purchase
  await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/credit_purchases/${reference}`,
    {
      method: "PATCH",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        fields: {
          userId: { stringValue: userId },
          amount: { integerValue: amount },
          credits: { integerValue: credits },
          reference: { stringValue: reference },
          status: { stringValue: "completed" },
          createdAt: { timestampValue: new Date().toISOString() },
        },
      }),
    }
  );

  // Increment user credits
  await atomicIncrementCredits(token, projectId, userId, credits);

  // Update admin revenue stats
  await updateAdminStats(token, projectId, amount);
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Verify Paystack signature
    const secretKey = Deno.env.get("PAYSTACK_SECRET_KEY")!;
    const body = await req.text();
    const signature = req.headers.get("x-paystack-signature");

    if (!signature) {
      return new Response(JSON.stringify({ error: "Missing signature" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const hash = createHmac("sha512", secretKey).update(body).digest("hex");
    if (hash !== signature) {
      return new Response(JSON.stringify({ error: "Invalid signature" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const event = JSON.parse(body);

    // Only process successful charge events
    if (event.event !== "charge.success") {
      return new Response(JSON.stringify({ success: true, message: "Event ignored" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { amount, reference, metadata } = event.data;
    const userId = metadata?.userId;
    const credits = metadata?.credits;

    if (!userId || !credits) {
      return new Response(JSON.stringify({ error: "Missing metadata" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const projectId = Deno.env.get("FIREBASE_PROJECT_ID")!;
    const firestoreToken = await getAccessToken();

    // Record purchase with idempotency (reference as document ID)
    await recordPurchase(
      firestoreToken,
      projectId,
      userId,
      amount / 100, // Convert kobo to Naira
      credits,
      reference,
    );

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
