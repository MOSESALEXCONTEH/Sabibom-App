import type {VercelRequest, VercelResponse} from "@vercel/node";
import {createHandler} from "../../utils/handler";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {adminFirestore} from "../../config/firebase-admin";
import {createNotificationForUser} from "../../services/notifications/push-service";

function assertCronAuthorized(req: VercelRequest) {
  const secret = process.env.CRON_SECRET?.trim();
  if (!secret) throw errors.permissionDenied("Cron is not configured.");
  const header = req.headers.authorization ?? "";
  const bearer = header.startsWith("Bearer ") ? header.slice(7) : "";
  const query = typeof req.query.secret === "string" ? req.query.secret : "";
  if (bearer !== secret && query !== secret) {
    throw errors.permissionDenied("Unauthorized cron request.");
  }
}

export default createHandler(["GET", "POST"], async (req: VercelRequest, res: VercelResponse) => {
  assertCronAuthorized(req);
  const db = adminFirestore();
  const businesses = await db.collection("businesses").limit(25).get();
  let processed = 0;
  let notified = 0;

  for (const biz of businesses.docs) {
    processed += 1;
    try {
      const businessId = biz.id;
      const businessName = (biz.data().name as string | undefined) ?? "Business";
      const dateKey = new Date().toISOString().slice(0, 10);
      const members = await db
        .collection("businesses")
        .doc(businessId)
        .collection("members")
        .where("status", "==", "active")
        .limit(20)
        .get();

      for (const member of members.docs) {
        const role = member.data().roleId ?? member.data().role;
        const isOwner = member.data().isOwner === true || role === "owner";
        if (!isOwner && role !== "manager" && role !== "cashier") continue;
        const result = await createNotificationForUser({
          userId: member.id,
          type: "end_of_day_incomplete",
          title: "End of Day reminder",
          message: "Today’s End-of-Day summary has not been finalized.",
          businessId,
          businessName,
          entityType: "end_of_day",
          entityId: dateKey,
          routeName: "reports",
          category: "end_of_day",
          priority: "high",
          deduplicationKey: `end_of_day_${businessId}_${dateKey}_incomplete_${member.id}`,
          sendPush: true,
          channelId: "sabibom_important",
        });
        if (!result.deduped) notified += 1;
      }
    } catch {
      // Continue safely when one business fails.
    }
  }

  sendSuccess(res, {processed, notified});
});
