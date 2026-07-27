import type {VercelRequest, VercelResponse} from "@vercel/node";
import {z} from "zod";
import {FieldValue} from "firebase-admin/firestore";
import {authenticateRequest} from "../../middleware/authenticate-request";
import {enforceRateLimit} from "../../middleware/rate-limit";
import {adminFirestore} from "../../config/firebase-admin";
import {businessIdSchema} from "../../schemas/common-schemas";
import {requireAppPermission} from "../../services/team/membership-service";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler, readJsonBody} from "../../utils/handler";

const schema = z.object({
  businessId: businessIdSchema,
  approvalId: z.string().trim().min(1),
  action: z.enum(["approve", "reject", "cancel"]),
  rejectionReason: z.string().trim().max(500).optional(),
});

export default createHandler(["POST"], async (req: VercelRequest, res: VercelResponse) => {
  const identity = await authenticateRequest(req);
  const parsed = schema.safeParse(readJsonBody(req));
  if (!parsed.success) throw errors.invalidArgument();

  const {businessId, approvalId, action, rejectionReason} = parsed.data;
  const db = adminFirestore();
  const ref = db
    .collection("businesses")
    .doc(businessId)
    .collection("approval_requests")
    .doc(approvalId);

  await enforceRateLimit({
    uid: identity.uid,
    businessId,
    operation: `approval_${action}`,
    windowSeconds: 60,
    maxPerWindow: 30,
    dailyMax: 300,
  });

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw errors.invalidArgument("Approval not found.");
    const live = snap.data() ?? {};
    if (live.status !== "pending") {
      throw errors.invalidArgument(
        "This approval request has already been completed.",
      );
    }

    if (action === "cancel") {
      if (live.requestedBy !== identity.uid) throw errors.permissionDenied();
      tx.update(ref, {
        status: "cancelled",
        cancelledAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return;
    }

    await requireAppPermission({
      uid: identity.uid,
      businessId,
      permission: "approve_sensitive_actions",
    });

    if (live.requestedBy === identity.uid) {
      throw errors.permissionDenied("You cannot approve your own request.");
    }

    if (action === "approve") {
      tx.update(ref, {
        status: "approved",
        approvedBy: identity.uid,
        approvedByName: identity.email ?? "Approver",
        approvedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return;
    }

    if (!rejectionReason?.trim()) {
      throw errors.invalidArgument("Enter a reason for rejecting this request.");
    }
    tx.update(ref, {
      status: "rejected",
      rejectedBy: identity.uid,
      rejectedByName: identity.email ?? "Approver",
      rejectedAt: FieldValue.serverTimestamp(),
      rejectionReason: rejectionReason.trim(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  sendSuccess(res, {ok: true, action, approvalId});
});
