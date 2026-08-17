import type {VercelRequest, VercelResponse} from "@vercel/node";
import {z} from "zod";
import {adminFirestore} from "../../config/firebase-admin";
import {authenticateRequest} from "../../middleware/authenticate-request";
import {verifyAndPersistGooglePlaySubscription} from "../../services/billing/google-play";
import {loadMembership} from "../../services/team/membership-service";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler, readJsonBody} from "../../utils/handler";

export const verifyGooglePlaySchema = z.object({
  businessId: z.string().trim().min(1).max(128),
  productId: z.string().trim().min(1).max(200),
  purchaseToken: z.string().trim().min(20).max(4096),
}).strict();

export default createHandler(["POST"], async (req: VercelRequest, res: VercelResponse) => {
  const identity = await authenticateRequest(req);
  const parsed = verifyGooglePlaySchema.safeParse(readJsonBody(req));
  if (!parsed.success) throw errors.invalidArgument("The Google Play purchase details are invalid.");
  const membership = await loadMembership({uid: identity.uid, businessId: parsed.data.businessId});
  if (!membership.isOwner) {
    throw errors.permissionDenied("Only the business owner can manage subscriptions.");
  }
  const verified = await verifyAndPersistGooglePlaySubscription({
    db: adminFirestore(),
    uid: identity.uid,
    ...parsed.data,
  });
  sendSuccess(res, {
    status: verified.status,
    productId: verified.productId,
    currentPeriodEnd: verified.currentPeriodEnd.toISOString(),
    cancelAtPeriodEnd: verified.cancelAtPeriodEnd,
  });
});
