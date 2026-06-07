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

async function recordGigPayment(token: string, projectId: string, amount: number, reference: string, metadata: any) {
  const checkResponse = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/gig_payments/${reference}`,
    { headers: { "Authorization": `Bearer ${token}` } }
  );

  if (checkResponse.status === 200) return;

  const price = Number(metadata.price || "0");
  const commission = Math.min(Math.round(price * 0.12), 2000);

  await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/gig_payments/${reference}`,
    {
      method: "PATCH",
      headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        fields: {
          clientId: { stringValue: metadata.userId || "" },
          providerId: { stringValue: metadata.providerId || "" },
          itemName: { stringValue: metadata.itemName || "" },
          price: { integerValue: price },
          commission: { integerValue: commission },
          reference: { stringValue: reference },
          status: { stringValue: "completed" },
          createdAt: { timestampValue: new Date().toISOString() },
        },
      }),
    }
  );

  const getResponse = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/metadata/admin_stats`,
    { headers: { "Authorization": `Bearer ${token}` } }
  );

  let currentTotal = 0;
  if (getResponse.status === 200) {
    const data = await getResponse.json();
    currentTotal = Number(data.fields?.totalRevenue?.integerValue || "0");
  }

  await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/metadata/admin_stats`,
    {
      method: "PATCH",
      headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        fields: {
          totalRevenue: { integerValue: currentTotal + commission },
          updatedAt: { timestampValue: new Date().toISOString() },
        },
      }),
    }
  );
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
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

    if (event.event !== "charge.success") {
      return new Response(JSON.stringify({ success: true, message: "Event ignored" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { amount, reference, metadata } = event.data;
    const projectId = Deno.env.get("FIREBASE_PROJECT_ID")!;
    const firestoreToken = await getAccessToken();

    await recordGigPayment(firestoreToken, projectId, amount / 100, reference, metadata);

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
