import type {VercelRequest, VercelResponse} from "@vercel/node";
import {z} from "zod";
import {authenticateRequest} from "../../middleware/authenticate-request";
import {enforceRateLimit} from "../../middleware/rate-limit";
import {businessIdSchema} from "../../schemas/common-schemas";
import {requireAppPermission} from "../../services/team/membership-service";
import {
  createNotificationForUser,
  sendPushToUser,
} from "../../services/notifications/push-service";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler, readJsonBody} from "../../utils/handler";

const testSchema = z.object({
  businessId: businessIdSchema.optional(),
  title: z.string().trim().min(1).max(80).default("SabiBom test notification"),
  message: z.string().trim().min(1).max(180).default("Push delivery is working."),
});

export default createHandler(["POST"], async (req: VercelRequest, res: VercelResponse) => {
  const identity = await authenticateRequest(req);
  const parsed = testSchema.safeParse(readJsonBody(req));
  if (!parsed.success) throw errors.invalidArgument("Invalid test notification payload.");

  if (parsed.data.businessId) {
    await requireAppPermission({
      uid: identity.uid,
      businessId: parsed.data.businessId,
      permission: "receive_push_notifications",
    });
  }

  await enforceRateLimit({
    uid: identity.uid,
    businessId: parsed.data.businessId ?? "_account",
    operation: "notifications_send_test",
    windowSeconds: 60,
    maxPerWindow: 3,
    dailyMax: 20,
  });

  const created = await createNotificationForUser({
    userId: identity.uid,
    type: "system_message",
    title: parsed.data.title,
    message: parsed.data.message,
    businessId: parsed.data.businessId,
    routeName: "notifications",
    deduplicationKey: `test_push_${identity.uid}_${Date.now()}`,
    sendPush: true,
    channelId: "sabibom_general",
  });

  const push = await sendPushToUser(identity.uid, {
    title: parsed.data.title,
    body: parsed.data.message,
    data: {routeName: "notifications"},
    channelId: "sabibom_general",
  });

  sendSuccess(res, {notificationId: created.id, push});
});
