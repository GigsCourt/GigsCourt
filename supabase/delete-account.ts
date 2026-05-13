import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { create, getNumericDate } from "https://deno.land/x/djwt@v2.2/mod.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

async function getAccessToken(scopes: string[]): Promise<string> {
  const serviceAccount = {
    client_email: Deno.env.get("FIREBASE_SERVICE_ACCOUNT_EMAIL")!,
    private_key: Deno.env.get("FIREBASE_SERVICE_ACCOUNT_KEY")!,
  };

  const jwt = await create(
    { alg: "RS256", typ: "JWT" },
    {
      iss: serviceAccount.client_email,
      scope: scopes.join(" "),
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

async function deleteFirestoreDocument(token: string, projectId: string, path: string) {
  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${path}`,
    { headers: { "Authorization": `Bearer ${token}` } }
  );
  if (response.status === 200) {
    await fetch(
      `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${path}`,
      { method: "DELETE", headers: { "Authorization": `Bearer ${token}` } }
    );
  }
}

async function deleteFirestoreCollectionDocs(token: string, projectId: string, collection: string, field: string, userId: string) {
  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${collection}`,
    { headers: { "Authorization": `Bearer ${token}` } }
  );
  
  const data = await response.json();
  if (!data.documents) return;

  for (const doc of data.documents) {
    const fields = doc.fields || {};
    const docField = fields[field]?.stringValue;
    
    if (docField === userId) {
      await fetch(
        `https://firestore.googleapis.com/v1/${doc.name}`,
        { method: "DELETE", headers: { "Authorization": `Bearer ${token}` } }
      );
    }
  }
}

async function deleteUserChats(token: string, projectId: string, userId: string) {
  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/chats`,
    { headers: { "Authorization": `Bearer ${token}` } }
  );
  
  const data = await response.json();
  if (!data.documents) return;

  for (const doc of data.documents) {
    const fields = doc.fields || {};
    const participants = fields.participants?.arrayValue?.values || [];
    const participantIds = participants.map((p: any) => p.stringValue).filter(Boolean);

    if (participantIds.includes(userId)) {
      // Delete only this user's messages from subcollection
      const messagesResponse = await fetch(
        `https://firestore.googleapis.com/v1/${doc.name}/messages`,
        { headers: { "Authorization": `Bearer ${token}` } }
      );
      
      const messagesData = await messagesResponse.json();
      if (messagesData.documents) {
        for (const msg of messagesData.documents) {
          const msgFields = msg.fields || {};
          const senderId = msgFields.senderId?.stringValue;
          if (senderId === userId) {
            await fetch(
              `https://firestore.googleapis.com/v1/${msg.name}`,
              { method: "DELETE", headers: { "Authorization": `Bearer ${token}` } }
            );
          }
        }
      }

      // Remove user from participants
      const updatedParticipants = participantIds
        .filter((id: string) => id !== userId)
        .map((id: string) => ({ stringValue: id }));
      
      await fetch(
        `https://firestore.googleapis.com/v1/${doc.name}`,
        {
          method: "PATCH",
          headers: {
            "Authorization": `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            fields: {
              participants: { arrayValue: { values: updatedParticipants } },
            },
          }),
        }
      );
    }
  }
}

async function deleteFirebaseUser(token: string, apiKey: string, userId: string) {
  await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:delete?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ localId: userId }),
    }
  );
}

async function deleteFromSupabase(userId: string) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  await fetch(`${supabaseUrl}/rest/v1/profiles?id=eq.${userId}`, {
    method: "DELETE",
    headers: {
      "Authorization": `Bearer ${serviceRoleKey}`,
      "apikey": serviceRoleKey,
    },
  });

  await fetch(`${supabaseUrl}/rest/v1/service_suggestions?suggested_by=eq.${userId}`, {
    method: "DELETE",
    headers: {
      "Authorization": `Bearer ${serviceRoleKey}`,
      "apikey": serviceRoleKey,
    },
  });
}

async function deleteFromImageKit(token: string, projectId: string, userId: string) {
  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/profiles/${userId}`,
    { headers: { "Authorization": `Bearer ${token}` } }
  );

  if (response.status !== 200) return;
  
  const data = await response.json();
  const fields = data.fields || {};
  const photoFileId = fields.photoFileId?.stringValue;
  const workPhotos = fields.workPhotos?.arrayValue?.values || [];

  const privateKey = Deno.env.get("IMAGEKIT_PRIVATE_KEY")!;
  const encodedKey = btoa(`${privateKey}:`);

  if (photoFileId) {
    await fetch(`https://api.imagekit.io/v1/files/${photoFileId}`, {
      method: "DELETE",
      headers: { "Authorization": `Basic ${encodedKey}` },
    });
  }

  for (const photo of workPhotos) {
    const fileId = photo.mapValue?.fields?.fileId?.stringValue;
    if (fileId) {
      await fetch(`https://api.imagekit.io/v1/files/${fileId}`, {
        method: "DELETE",
        headers: { "Authorization": `Basic ${encodedKey}` },
      });
    }
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { userId, idToken } = await req.json();

    if (!userId || !idToken) {
      return new Response(JSON.stringify({ error: "Missing userId or idToken" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Verify the Firebase ID token
    const apiKey = "AIzaSyDX7mFL2ls42zWUlBr9bhR84JD3McDWGFk";
    const verifyResponse = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ idToken }),
      }
    );
    
    const verifyData = await verifyResponse.json();
    if (!verifyData.users || verifyData.users[0].localId !== userId) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const projectId = Deno.env.get("FIREBASE_PROJECT_ID")!;
    const firestoreToken = await getAccessToken(["https://www.googleapis.com/auth/datastore"]);

    // 1. Delete photos from ImageKit
    await deleteFromImageKit(firestoreToken, projectId, userId);

    // 2. Delete Firestore documents
    await deleteFirestoreDocument(firestoreToken, projectId, `profiles/${userId}`);
    await deleteFirestoreCollectionDocs(firestoreToken, projectId, "gigs", "providerId", userId);
    await deleteFirestoreCollectionDocs(firestoreToken, projectId, "gigs", "clientId", userId);
    await deleteFirestoreCollectionDocs(firestoreToken, projectId, "reviews", "providerId", userId);
    await deleteFirestoreCollectionDocs(firestoreToken, projectId, "reviews", "clientId", userId);
    await deleteFirestoreCollectionDocs(firestoreToken, projectId, "notifications", "userId", userId);
    await deleteFirestoreCollectionDocs(firestoreToken, projectId, "credit_purchases", "userId", userId);
    await deleteFirestoreCollectionDocs(firestoreToken, projectId, "reported_issues", "userId", userId);
    await deleteUserChats(firestoreToken, projectId, userId);

    // 3. Delete from Supabase
    await deleteFromSupabase(userId);

    // 4. Delete Firebase Auth user LAST
    await deleteFirebaseUser(firestoreToken, apiKey, userId);

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
