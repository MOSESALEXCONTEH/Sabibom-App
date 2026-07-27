import type {VercelRequest, VercelResponse} from "@vercel/node";
import {Timestamp} from "firebase-admin/firestore";
import {adminFirestore} from "../../config/firebase-admin";
import {createNotificationForUser} from "../../services/notifications/push-service";
import {
  daysRemainingForBusiness,
  expiryStatusForDate,
} from "../../services/inventory/product-intelligence";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler} from "../../utils/handler";

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

function priorityForDays(days: number): "normal" | "high" | "urgent" {
  if (days < 0 || days === 0) return "urgent";
  if (days <= 7) return "high";
  return "normal";
}

function reminderBucket(daysRemaining: number, reminderDays: number[]): number | null {
  const sorted = [...reminderDays].sort((a, b) => b - a);
  for (const day of sorted) {
    if (daysRemaining === day) return day;
    if (daysRemaining < 0 && day === 0) return 0;
  }
  if (daysRemaining < 0) return -1;
  return null;
}

export default createHandler(
  ["GET", "POST"],
  async (req: VercelRequest, res: VercelResponse) => {
    assertCronAuthorized(req);
    const db = adminFirestore();
    const businesses = await db.collection("businesses").limit(25).get();
    let processed = 0;
    let notified = 0;

    for (const biz of businesses.docs) {
      processed += 1;
      try {
        const businessId = biz.id;
        const businessName =
          (biz.data().name as string | undefined) ?? "Business";
        const timezone =
          (biz.data().timezone as string | undefined) ?? "Africa/Freetown";
        const settingsSnap = await biz.ref
          .collection("settings")
          .doc("inventory_expiry")
          .get();
        const settings = settingsSnap.data() ?? {};
        if (settings.enabled === false) continue;
        const reminderDays = Array.isArray(settings.defaultReminderDays)
          ? settings.defaultReminderDays
              .map((day) => Number(day))
              .filter((day) => Number.isFinite(day) && day >= 0 && day <= 365)
          : [30, 14, 7, 3, 1, 0];
        const pushEnabled = settings.pushEnabled !== false;
        const inAppEnabled = settings.inAppEnabled !== false;
        if (!inAppEnabled && !pushEnabled) continue;

        const batches = await biz.ref
          .collection("inventory_batches")
          .where("status", "in", ["active", "expired"])
          .limit(200)
          .get();
        const members = await biz.ref
          .collection("members")
          .where("status", "==", "active")
          .limit(40)
          .get();

        for (const batchDoc of batches.docs) {
          const batch = batchDoc.data();
          const remaining = Number(batch.quantityRemaining ?? 0);
          if (!Number.isFinite(remaining) || remaining <= 0) continue;
          const productName =
            (batch.productName as string | undefined) ?? "Product";
          const productId = String(batch.productId ?? "");
          const known = batch.expiryDateKnown === true;
          const expiryRaw = batch.expiryDate;
          const expiryDate =
            expiryRaw instanceof Timestamp
              ? expiryRaw.toDate().toISOString().slice(0, 10)
              : typeof expiryRaw === "string"
                ? expiryRaw.slice(0, 10)
                : null;

          let type = "product_expiry_unknown";
          let title = "Expiry date unknown";
          let message = `The expiry date for ${remaining} units of ${productName} is unknown.`;
          let priority: "normal" | "high" | "urgent" = "normal";
          let dedupeSuffix = "unknown";

          if (known && expiryDate) {
            const days = daysRemainingForBusiness({
              expiryDate,
              timezone,
            });
            const bucket = reminderBucket(days, reminderDays);
            if (bucket === null) continue;
            const status = expiryStatusForDate({
              expiryDate,
              timezone,
              reminderThresholdDays: Math.max(...reminderDays, 30),
            });
            priority = priorityForDays(days);
            if (status === "expired" || days < 0) {
              type = "product_expired";
              title = "Product expired";
              message = `${remaining} units of ${productName} have expired.`;
              dedupeSuffix = "expired";
            } else if (days === 0) {
              type = "product_expires_today";
              title = "Expires today";
              message = `${productName} expires today. ${remaining} units remain.`;
              dedupeSuffix = "0";
            } else {
              type = "product_expiry_approaching";
              title = "Expiry approaching";
              message = `${productName} will expire on ${expiryDate}. ${remaining} units remain.`;
              dedupeSuffix = String(bucket);
            }
          }

          for (const member of members.docs) {
            const data = member.data();
            const role = String(data.roleId ?? data.role ?? "");
            const permissions = Array.isArray(data.permissions)
              ? data.permissions.map(String)
              : [];
            const allowed =
              data.isOwner === true ||
              role === "owner" ||
              role === "manager" ||
              role === "stock_keeper" ||
              permissions.includes("view_product_expiry") ||
              permissions.includes("view_low_stock_alerts");
            if (!allowed) continue;
            if (settings.notifyOwners === false && role === "owner") continue;
            if (settings.notifyManagers === false && role === "manager") {
              continue;
            }
            if (
              settings.notifyStockKeepers === false &&
              role === "stock_keeper"
            ) {
              continue;
            }

            const deduplicationKey = `expiry_${businessId}_${batchDoc.id}_${dedupeSuffix}_${member.id}`;
            const result = await createNotificationForUser({
              userId: member.id,
              type,
              title,
              message,
              businessId,
              businessName,
              entityType: "inventory_batch",
              entityId: batchDoc.id,
              routeName: "productDetails",
              routeParameters: {productId},
              category: type === "product_expired" ? "expired_stock" : "expiry",
              priority,
              deduplicationKey,
              sendPush: pushEnabled,
              channelId:
                priority === "urgent" || priority === "high"
                  ? "sabibom_important"
                  : "sabibom_general",
            });
            if (!result.deduped) notified += 1;
          }
        }
      } catch {
        // Continue safely when one business fails.
      }
    }

    sendSuccess(res, {processed, notified});
  },
);
