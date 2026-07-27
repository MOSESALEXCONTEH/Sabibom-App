import type {VercelRequest, VercelResponse} from "@vercel/node";
import {FieldValue} from "firebase-admin/firestore";
import {z} from "zod";
import {adminFirestore} from "../../config/firebase-admin";
import {authenticateRequest} from "../../middleware/authenticate-request";
import {enforceRateLimit} from "../../middleware/rate-limit";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler, readJsonBody} from "../../utils/handler";

const unregisterSchema = z.object({
  token: z.string().trim().min(20).max(4096),
  platform: z.enum(["android", "ios"]),
});

export default createHandler(["POST"], async (req: VercelRequest, res: VercelResponse) => {
  const identity = await authenticateRequest(req);
  const parsed = unregisterSchema.safeParse(readJsonBody(req));
  if (!parsed.success) throw errors.invalidArgument("Invalid device unregistration.");

  await enforceRateLimit({
    uid: identity.uid,
    businessId: "_account",
    operation: "notifications_unregister_device",
    windowSeconds: 60,
    maxPerWindow: 10,
    dailyMax: 50,
  });

  const db = adminFirestore();
  const user = db.collection("users").doc(identity.uid);
  const matchingDevices = await user
    .collection("devices")
    .where("fcmToken", "==", parsed.data.token)
    .get();

  await Promise.all(
    matchingDevices.docs.map((device) =>
      device.ref.set(
        {
          isActive: false,
          notificationsEnabled: false,
          invalidatedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      ),
    ),
  );

  await user.set(
    {
      fcmTokens: FieldValue.arrayRemove([parsed.data.token]),
      fcmTokenUpdatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );

  sendSuccess(res, {disabled: matchingDevices.docs.length > 0});
});