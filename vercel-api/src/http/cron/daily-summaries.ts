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
  // Bounded batch — do not scan every business unboundedly.
  const businesses = await db.collection("businesses").limit(25).get();
  let processed = 0;
  let notified = 0;

  for (const biz of businesses.docs) {
    processed += 1;
    try {
      const businessId = biz.id;
      const businessName = (biz.data().name as string | undefined) ?? "Business";
      const owners = await db
        .collection("businesses")
        .doc(businessId)
        .collection("members")
        .where("status", "==", "active")
        .limit(20)
        .get();

      const today = new Date();
      const dateKey = today.toISOString().slice(0, 10);

      for (const member of owners.docs) {
        const role = member.data().roleId ?? member.data().role;
        const isOwner = member.data().isOwner === true || role === "owner";
        if (!isOwner && role !== "manager" && role !== "accountant") continue;
        const result = await createNotificationForUser({
          userId: member.id,
          type: "daily_summary_ready",
          title: "Daily summary ready",
          message: `Your daily business summary for ${dateKey} is ready.`,
          businessId,
          businessName,
          entityType: "daily_summary",
          entityId: dateKey,
          routeName: "dailySummary",
          routeParameters: {dateKey},
          category: "reports",
          priority: "normal",
          deduplicationKey: `daily_summary_${member.id}_${businessId}_${dateKey}`,
          sendPush: true,
          channelId: "sabibom_summaries",
        });
        if (!result.deduped) notified += 1;
      }
    } catch {
      // Continue safely when one business fails.
    }
  }

  sendSuccess(res, {processed, notified});
});
