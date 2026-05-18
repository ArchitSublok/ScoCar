/**
 * ─────────────────────────────────────────────────────────────────────────────
 * AREA 5: Firestore Schema Upgrades + Cloud Functions
 *
 * Changes:
 *   1. residents.fcmToken  →  residents.fcmTokens (array of strings)
 *   2. Cloud Functions loop through ALL tokens to notify every family device
 *   3. vehicles collection now supports multiple vehicles per flat / ownerUserId
 *
 * DEPLOY: firebase deploy --only functions
 * ─────────────────────────────────────────────────────────────────────────────
 */

const functions = require("firebase-functions/v2");
const admin = require("firebase-admin");

// Guard against double-init when imported alongside existing index.js
if (!admin.apps.length) admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: Send push to ALL tokens registered for a flat
//
// Handles stale tokens: removes them from the array on InvalidRegistration error
// ─────────────────────────────────────────────────────────────────────────────
async function sendToAllFlatTokens(flatNumber, message) {
  // 1. Try doc-ID-based lookup first (flatNumber == doc ID)
  let tokenArray = [];

  try {
    const residentDoc = await db.collection("residents").doc(flatNumber).get();
    if (residentDoc.exists) {
      const data = residentDoc.data();
      // Support both old schema (fcmToken: string) and new (fcmTokens: array)
      if (Array.isArray(data.fcmTokens) && data.fcmTokens.length > 0) {
        tokenArray = data.fcmTokens;
      } else if (typeof data.fcmToken === "string" && data.fcmToken) {
        tokenArray = [data.fcmToken]; // backward-compat with old single-token docs
      }
    }
  } catch (e) {
    console.log("Resident doc lookup failed:", e.message);
  }

  // 2. Fallback: query by flatNumber field
  if (tokenArray.length === 0) {
    const snap = await db
      .collection("residents")
      .where("flatNumber", "==", flatNumber)
      .limit(1)
      .get();
    if (!snap.empty) {
      const data = snap.docs[0].data();
      if (Array.isArray(data.fcmTokens)) tokenArray = data.fcmTokens;
      else if (data.fcmToken) tokenArray = [data.fcmToken];
    }
  }

  if (tokenArray.length === 0) {
    console.log(`⚠️ No FCM tokens found for flat ${flatNumber}`);
    return;
  }

  // 3. Send to every token, collect stale ones for cleanup
  const staleTokens = [];

  await Promise.all(
    tokenArray.map(async (token) => {
      try {
        await messaging.send({ ...message, token });
        console.log(`✅ Notified token ending ...${token.slice(-6)}`);
      } catch (err) {
        if (
          err.code === "messaging/invalid-registration-token" ||
          err.code === "messaging/registration-token-not-registered"
        ) {
          staleTokens.push(token);
          console.log(`🗑 Stale token queued for removal: ...${token.slice(-6)}`);
        } else {
          console.error("FCM send error:", err.code, err.message);
        }
      }
    })
  );

  // 4. Clean up stale tokens from Firestore
  if (staleTokens.length > 0) {
    await db
      .collection("residents")
      .doc(flatNumber)
      .update({
        fcmTokens: admin.firestore.FieldValue.arrayRemove(...staleTokens),
      });
    console.log(`🗑 Removed ${staleTokens.length} stale token(s) for flat ${flatNumber}`);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TRIGGER 1 (UPDATED): Guard submits delivery → notify ALL resident devices
// ─────────────────────────────────────────────────────────────────────────────
exports.onDeliveryRequestCreated = functions.firestore.onDocumentCreated(
  "approvals/{docId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const { flatNumber, company, sentBy: guardId } = data;
    if (!flatNumber || !company) return;

    console.log(`📬 New delivery: ${company} → Flat ${flatNumber}`);

    const messagePayload = {
      notification: {
        title: "🚚 Delivery at Gate",
        body: `${company} delivery arrived for Flat ${flatNumber}. Approve or deny?`,
      },
      data: {
        type: "delivery_request",
        approvalId: event.params.docId,
        flatNumber,
        company,
      },
      android: {
        priority: "high",
        notification: { channelId: "soccar_high_importance", sound: "default" },
      },
      apns: { payload: { aps: { sound: "default", badge: 1 } } },
    };

    // ── NEW: sends to ALL tokens on the flat ──────────────────────────────
    await sendToAllFlatTokens(flatNumber, messagePayload);

    await db.collection("alerts").add({
      type: "DELIVERY_REQUEST",
      targetFlat: flatNumber,
      company,
      guardId,
      approvalId: event.params.docId,
      message: `${company} delivery arrived. Approve or deny?`,
      read: false,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// TRIGGER 2 (UPDATED): Resident decision → notify guard
// (unchanged from original except using guard fcmTokens array too)
// ─────────────────────────────────────────────────────────────────────────────
exports.onApprovalDecision = functions.firestore.onDocumentUpdated(
  "approvals/{docId}",
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    if (before.status === after.status) return;
    if (after.status !== "APPROVED" && after.status !== "DENIED") return;

    const { flatNumber, company, sentBy: guardId } = after;
    const approved = after.status === "APPROVED";
    const emoji = approved ? "✅" : "🚫";
    const statusWord = approved ? "APPROVED" : "DENIED";

    // Get guard token(s)
    let guardTokens = [];
    try {
      const guardDoc = await db.collection("guards").doc(guardId).get();
      if (guardDoc.exists) {
        const d = guardDoc.data();
        guardTokens = Array.isArray(d.fcmTokens)
          ? d.fcmTokens
          : d.fcmToken
          ? [d.fcmToken]
          : [];
      }
    } catch (e) {
      console.log("Guard lookup failed:", e.message);
    }

    for (const token of guardTokens) {
      try {
        await messaging.send({
          token,
          notification: {
            title: `${emoji} Flat ${flatNumber} has responded`,
            body: `${company} delivery ${statusWord} by Flat ${flatNumber}.`,
          },
          data: {
            type: "delivery_decision",
            guardId,
            flatNumber,
            company,
            approved: String(approved),
            approvalId: event.params.docId,
          },
          android: { priority: "high" },
        });
      } catch (err) {
        console.error("Guard notify error:", err.code);
      }
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// TRIGGER 3 (UPDATED): Vehicle entry → notify ALL resident devices
// ─────────────────────────────────────────────────────────────────────────────
exports.onVehicleLog = functions.firestore.onDocumentCreated(
  "vehicleLogs/{docId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const { flatNumber, plateNumber, type } = data;
    if (!flatNumber || !plateNumber) return;

    const emoji = type === "ENTRY" ? "🚗" : "🏁";
    const action = type === "ENTRY" ? "entered" : "exited";

    await sendToAllFlatTokens(flatNumber, {
      notification: {
        title: `${emoji} Vehicle ${type === "ENTRY" ? "Entered" : "Exited"}`,
        body: `Your vehicle ${plateNumber} has ${action} the society gate.`,
      },
      data: { type: "vehicle_movement", plateNumber, movementType: type, flatNumber },
      android: { priority: "normal", notification: { channelId: "soccar_high_importance" } },
    });
  }
);
