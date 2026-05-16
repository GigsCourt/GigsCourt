import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createHmac } from "https://deno.land/std@0.177.0/node/crypto.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

async function verifyFirebaseToken(idToken: string, expectedUserId: string): Promise<boolean> {
  try {
    // Verify the Firebase ID token using Firebase Auth REST API
    const apiKey = Deno.env.get("FIREBASE_API_KEY")!;
    const response = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ idToken }),
      }
    );
    
    const data = await response.json();
    if (!data.users || data.users.length === 0) return false;
    
    return data.users[0].localId === expectedUserId;
  } catch (e) {
    console.error("Token verification failed:", e);
    return false;
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");

    // Parse request body to get userId
    let userId = "";
    try {
      const body = await req.clone().json();
      userId = body.userId || "";
    } catch {
      // Body might not be JSON, try parsing the token directly
      // The client sends userId as the token, but we need to validate it
      userId = token;
    }

    // Verify the Firebase ID token
    const isValid = await verifyFirebaseToken(token, userId);
    if (!isValid) {
      return new Response(JSON.stringify({ error: "Invalid credentials" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const privateKey = Deno.env.get("IMAGEKIT_PRIVATE_KEY");
    if (!privateKey) {
      return new Response(JSON.stringify({ error: "Server configuration error" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Generate auth params for ImageKit upload
    const uploadToken = crypto.randomUUID();
    const expire = Math.floor(Date.now() / 1000) + 3600; // 1 hour
    const signatureData = uploadToken + expire;
    const signature = createHmac("sha1", privateKey).update(signatureData).digest("hex");

    return new Response(
      JSON.stringify({
        token: uploadToken,
        expire,
        signature,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
