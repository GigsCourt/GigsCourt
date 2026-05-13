import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const SEND_PUSH_URL = "https://ohysatmlieiatzwqwjyt.supabase.co/functions/v1/send-push";

async function callSendPush(userId: string, title: string, body: string, data: Record<string, string>) {
  try {
    await fetch(SEND_PUSH_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ user_id: userId, title, body, data }),
    });
  } catch (e) {
    console.error(`Failed to send to ${userId}:`, e);
  }
}

async function getAccessToken(): Promise<string> {
  const serviceAccount = {
    client_email: Deno.env.get("FIREBASE_SERVICE_ACCOUNT_EMAIL")!,
    private_key: Deno.env.get("FIREBASE_SERVICE_ACCOUNT_KEY")!,
  };

  const header = { alg: "RS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/datastore",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };

  const encoder = new TextEncoder();
  const keyData = serviceAccount.private_key
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\n/g, "");
  
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(keyData), (c) => c.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const jwt = `${btoa(JSON.stringify(header))}.${btoa(JSON.stringify(claim))}`;
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, encoder.encode(jwt));
  const signedJwt = `${jwt}.${btoa(String.fromCharCode(...new Uint8Array(signature)))}`;

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${signedJwt}`,
  });

  const data = await response.json();
  return data.access_token;
}

async function queryFirestore(collection: string): Promise<any[]> {
  const accessToken = await getAccessToken();
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID")!;
  
  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${collection}`,
    { headers: { "Authorization": `Bearer ${accessToken}` } }
  );

  const data = await response.json();
  if (!data.documents) return [];
  
  return data.documents.map((doc: any) => {
    const fields = doc.fields || {};
    const result: any = { id: doc.name.split("/").pop() };
    for (const [key, value] of Object.entries(fields)) {
      const v = value as any;
      result[key] = v.stringValue ?? v.integerValue ?? v.doubleValue ?? v.booleanValue ?? v.timestampValue ?? null;
    }
    return result;
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { type } = await req.json();
    const profiles = await queryFirestore("profiles");
    const now = new Date();
    const threeDaysAgo = new Date(now.getTime() - 3 * 24 * 60 * 60 * 1000);

    let sent = 0;

    for (const profile of profiles) {
      const profileId = profile.id;
      if (!profileId) continue;

      switch (type) {
        case "inactive_users": {
          const updatedAt = profile.updatedAt ? new Date(profile.updatedAt) : null;
          if (updatedAt && updatedAt < threeDaysAgo) {
            await callSendPush(profileId, "We miss you!", "Discover new providers near you on GigsCourt", { screen: "home" });
            sent++;
          }
          break;
        }

        case "provider_inactive_7d": {
          const services = Array.isArray(profile.services) ? profile.services : [];
          const gigCount7Days = parseInt(profile.gigCount7Days || "0");
          if (services.length > 0 && gigCount7Days === 0) {
            await callSendPush(profileId, "No gigs this week", "You haven't completed a gig this week. Update your services to attract more clients.", { screen: "edit_services" });
            sent++;
          }
          break;
        }

        case "low_credits": {
          const services = Array.isArray(profile.services) ? profile.services : [];
          const credits = parseInt(profile.credits || "0");
          if (services.length > 0 && credits <= 1) {
            await callSendPush(profileId, "Low credits", `You have ${credits} credit${credits === 1 ? "" : "s"} left. Buy more credits to register gigs and get reviewed.`, { screen: "credits" });
            sent++;
          }
          break;
        }

        case "boost_reputation": {
          const lastGigAt = profile.lastGigCompletedAt ? new Date(profile.lastGigCompletedAt) : null;
          const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000);
          if (lastGigAt && lastGigAt > yesterday) {
            await callSendPush(profileId, "Keep it up!", "Great work! You completed a gig today, keep it up to get more clients. This will boost your reputation.", { screen: "profile" });
            sent++;
          }
          break;
        }

        case "profile_incomplete": {
          const hasPhoto = !!profile.photoUrl;
          const hasAddress = !!profile.workspaceAddress;
          if (!hasPhoto || !hasAddress) {
            await callSendPush(profileId, "Complete your profile", "Complete your profile to get discovered by more clients.", { screen: "edit_profile" });
            sent++;
          }
          break;
        }
      }
    }

    return new Response(JSON.stringify({ success: true, type, sent }), {
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
