import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { create, getNumericDate } from "https://deno.land/x/djwt@v2.2/mod.ts";

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

  const key = serviceAccount.private_key;
  
  const jwt = await create(
    { alg: "RS256", typ: "JWT" },
    {
      iss: serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/datastore",
      aud: "https://oauth2.googleapis.com/token",
      exp: getNumericDate(3600),
      iat: getNumericDate(0),
    },
    key
  );

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
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
      if (v.arrayValue) {
        result[key] = (v.arrayValue.values || []).map((item: any) => 
          item.stringValue ?? item.integerValue ?? item.doubleValue ?? item.booleanValue ?? null
        );
      } else {
        result[key] = v.stringValue ?? v.integerValue ?? v.doubleValue ?? v.booleanValue ?? v.timestampValue ?? null;
      }
    }
    return result;
  });
}

async function queryFirestoreWithFilter(collection: string, field: string, operator: string, value: any): Promise<any[]> {
  const accessToken = await getAccessToken();
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID")!;
  
  const allDocs = await queryFirestore(collection);
  
  // Simple client-side filtering since Firestore REST API structured queries are complex
  return allDocs.filter((doc) => {
    const fieldValue = doc[field];
    switch (operator) {
      case "==": return fieldValue == value;
      case "!=": return fieldValue != value;
      case ">": return fieldValue > value;
      case "<": return fieldValue < value;
      default: return false;
    }
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { type } = await req.json();
    const now = new Date();
    const threeDaysAgo = new Date(now.getTime() - 3 * 24 * 60 * 60 * 1000);
    const threeHoursAgo = new Date(now.getTime() - 3 * 60 * 60 * 1000);
    const sixHoursAgo = new Date(now.getTime() - 6 * 60 * 60 * 1000);

    let sent = 0;

    switch (type) {
      case "review_reminder": {
        // Find pending gigs where client hasn't submitted a review
        const gigs = await queryFirestore("gigs");
        for (const gig of gigs) {
          if (gig.status === "pending" && gig.clientId) {
            const provider = await getProfile(gig.providerId);
            const providerName = provider?.name || "your provider";
            await callSendPush(gig.clientId, "Rate your gig", `Rate ${providerName}'s work to help them build their reputation.`, { screen: "gig", gigId: gig.id });
            sent++;
          }
        }
        break;
      }

      case "register_gig_reminder": {
        // Find chats with recent messages but no active gig
        const chats = await queryFirestore("chats");
        for (const chat of chats) {
          if (!chat.gigId && chat.lastMessageTime) {
            const lastTime = new Date(chat.lastMessageTime);
            if (lastTime > sixHoursAgo) {
              const participants = chat.participants || [];
              for (const uid of participants) {
                if (uid) {
                  const otherPerson = await getProfile(participants.find((p: string) => p !== uid));
                  const otherName = otherPerson?.name || "this person";
                  await callSendPush(uid, "Register a gig?", `Offering services to ${otherName}? Register a gig to get rated and reviewed.`, { screen: "chat", chatId: chat.id });
                  sent++;
                }
              }
            }
          }
        }
        break;
      }

      case "inactive_users": {
        const profiles = await queryFirestore("profiles");
        for (const profile of profiles) {
          const updatedAt = profile.updatedAt ? new Date(profile.updatedAt) : null;
          if (updatedAt && updatedAt < threeDaysAgo) {
            await callSendPush(profile.id, "We miss you!", "Discover new providers near you on GigsCourt", { screen: "home" });
            sent++;
          }
        }
        break;
      }

      case "provider_inactive_7d": {
        const profiles = await queryFirestore("profiles");
        for (const profile of profiles) {
          const services = profile.services || [];
          const gigCount7Days = parseInt(profile.gigCount7Days || "0");
          if (services.length > 0 && gigCount7Days === 0) {
            await callSendPush(profile.id, "No gigs this week", "You haven't completed a gig this week. Update your services to attract more clients.", { screen: "edit_services" });
            sent++;
          }
        }
        break;
      }

      case "low_credits": {
        const profiles = await queryFirestore("profiles");
        for (const profile of profiles) {
          const services = profile.services || [];
          const credits = parseInt(profile.credits || "0");
          if (services.length > 0 && credits <= 1) {
            await callSendPush(profile.id, "Low credits", `You have ${credits} credit${credits === 1 ? "" : "s"} left. Buy more credits to register gigs and get reviewed.`, { screen: "credits" });
            sent++;
          }
        }
        break;
      }

      case "boost_reputation": {
        const profiles = await queryFirestore("profiles");
        for (const profile of profiles) {
          const lastGigAt = profile.lastGigCompletedAt ? new Date(profile.lastGigCompletedAt) : null;
          const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000);
          if (lastGigAt && lastGigAt > yesterday) {
            await callSendPush(profile.id, "Keep it up!", "Great work! You completed a gig today, keep it up to get more clients. This will boost your reputation.", { screen: "profile" });
            sent++;
          }
        }
        break;
      }

      case "profile_incomplete": {
        const profiles = await queryFirestore("profiles");
        for (const profile of profiles) {
          const hasPhoto = !!profile.photoUrl;
          const hasAddress = !!profile.workspaceAddress;
          if (!hasPhoto || !hasAddress) {
            await callSendPush(profile.id, "Complete your profile", "Complete your profile to get discovered by more clients.", { screen: "edit_profile" });
            sent++;
          }
        }
        break;
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

// Helper: get a single profile by ID
async function getProfile(userId: string): Promise<any | null> {
  if (!userId) return null;
  const accessToken = await getAccessToken();
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID")!;
  
  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/profiles/${userId}`,
    { headers: { "Authorization": `Bearer ${accessToken}` } }
  );

  if (response.status === 404) return null;
  const data = await response.json();
  const fields = data.fields || {};
  const result: any = {};
  for (const [key, value] of Object.entries(fields)) {
    const v = value as any;
    result[key] = v.stringValue ?? v.integerValue ?? v.doubleValue ?? v.booleanValue ?? v.timestampValue ?? null;
  }
  return result;
}
