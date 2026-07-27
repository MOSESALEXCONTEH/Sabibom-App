import type {VercelRequest, VercelResponse} from "@vercel/node";
import {createHash} from "node:crypto";
import {z} from "zod";
import {FieldValue} from "firebase-admin/firestore";
import {authenticateRequest} from "../../middleware/authenticate-request";
import {enforceRateLimit} from "../../middleware/rate-limit";
import {adminFirestore} from "../../config/firebase-admin";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler, readJsonBody} from "../../utils/handler";

const registerSchema = z.object({
  token: z.string().trim().min(20).max(4096).optional(),
  // Retained temporarily for existing non-Flutter clients.
  fcmToken: z.string().trim().min(20).max(4096).optional(),
  deviceId: z.string().trim().min(4).max(128).optional(),
  platform: z.enum(["android", "ios", "web", "other"]).default("android"),
  appVersion: z.string().trim().max(40).optional(),
  deviceName: z.string().trim().max(80).optional(),
  notificationsEnabled: z.boolean().default(true),
}).refine((value) => Boolean(value.token ?? value.fcmToken));

export default createHandler(["POST"], async (req: VercelRequest, res: VercelResponse) => {
  const identity = await authenticateRequest(req);
  const parsed = registerSchema.safeParse(readJsonBody(req));
  if (!parsed.success) throw errors.invalidArgument("Invalid device registration.");
  const fcmToken = parsed.data.token ?? parsed.data.fcmToken!;
  const deviceId = parsed.data.deviceId ?? `fcm_${createHash("sha256")
    .update(fcmToken)
    .digest("hex")
    .slice(0, 32)}`;

  await enforceRateLimit({
    uid: identity.uid,
    businessId: "_account",
    operation: "notifications_register_device",
    windowSeconds: 60,
    maxPerWindow: 10,
    dailyMax: 50,
  });

  const db = adminFirestore();
  const ref = db
    .collection("users")
    .doc(identity.uid)
    .collection("devices")
    .doc(deviceId);

  await ref.set(
    {
      deviceId,
      userId: identity.uid,
      fcmToken,
      platform: parsed.data.platform,
      appVersion: parsed.data.appVersion ?? null,
      deviceName: parsed.data.deviceName ?? null,
      isActive: true,
      notificationsEnabled: parsed.data.notificationsEnabled,
      updatedAt: FieldValue.serverTimestamp(),
      lastSeenAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );

  await db.collection("users").doc(identity.uid).set(
    {
      fcmTokens: FieldValue.arrayUnion([fcmToken]),
      fcmTokenUpdatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );

  sendSuccess(res, {deviceId});
});
