import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { initializeApp, cert, getApps } from "npm:firebase-admin/app";
import { getFirestore } from "npm:firebase-admin/firestore";
import { getMessaging } from "npm:firebase-admin/messaging";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Initialize Firebase Admin (once)
function getFirebaseAdmin() {
  if (getApps().length === 0) {
    const serviceAccount = {
      projectId: Deno.env.get("FIREBASE_PROJECT_ID")!,
      clientEmail: Deno.env.get("FIREBASE_SERVICE_ACCOUNT_EMAIL")!,
      privateKey: Deno.env.get("FIREBASE_SERVICE_ACCOUNT_KEY")!.replace(/\\n/g, "\n"),
    };
    initializeApp({ credential: cert(serviceAccount) });
  }
  return { db: getFirestore(), messaging: getMessaging() };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { user_id, title, body, data } = await req.json();

    if (!user_id || !title || !body) {
      return new Response(JSON.stringify({ error: "Missing required fields" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { db, messaging } = getFirebaseAdmin();

    // Get FCM token from Firestore
    const profileDoc = await db.collection("profiles").doc(user_id).get();
    const fcmToken = profileDoc.data()?.fcmToken;

    // Write in-app notification to Firestore
    await db.collection("notifications").add({
      userId: user_id,
      title,
      body,
      data: data || {},
      read: false,
      createdAt: new Date(),
    });

    // Send push if token exists
    if (fcmToken) {
      try {
        await messaging.send({
          token: fcmToken,
          notification: { title, body },
          data: data || {},
        });
      } catch (pushError) {
        // Token might be invalid — don't fail the whole function
        console.error("Push failed:", pushError);
      }
    }

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
