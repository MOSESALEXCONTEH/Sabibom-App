import type {VercelRequest, VercelResponse} from "@vercel/node";
import {z} from "zod";
import {FieldValue} from "firebase-admin/firestore";
import {authenticateRequest} from "../../middleware/authenticate-request";
import {enforceRateLimit} from "../../middleware/rate-limit";
import {adminFirestore} from "../../config/firebase-admin";
import {businessIdSchema} from "../../schemas/common-schemas";
import {
  countActiveOwners,
  requireAppPermission,
} from "../../services/team/membership-service";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler, readJsonBody} from "../../utils/handler";

const schema = z.object({
  businessId: businessIdSchema,
  targetUid: z.string().trim().min(1),
  action: z.enum(["disable", "restore", "remove"]),
  reason: z.string().trim().max(500).optional(),
});

export default createHandler(["POST"], async (req: VercelRequest, res: VercelResponse) => {
  const identity = await authenticateRequest(req);
  const parsed = schema.safeParse(readJsonBody(req));
  if (!parsed.success) throw errors.invalidArgument();

  const {businessId, targetUid, action, reason} = parsed.data;
  await requireAppPermission({
    uid: identity.uid,
    businessId,
    permission: "manage_staff",
  });

  await enforceRateLimit({
    uid: identity.uid,
    businessId,
    operation: `team_${action}`,
    windowSeconds: 60,
    maxPerWindow: 20,
    dailyMax: 200,
  });

  const db = adminFirestore();
  const memberRef = db
    .collection("businesses")
    .doc(businessId)
    .collection("members")
    .doc(targetUid);
  const snap = await memberRef.get();
  if (!snap.exists) throw errors.notFound("Member not found.");

  const member = snap.data() ?? {};
  const isOwner =
    member.isOwner === true ||
    member.role === "owner" ||
    member.roleId === "owner";

  if ((action === "disable" || action === "remove") && isOwner) {
    const owners = await countActiveOwners(businessId);
    if (owners <= 1) {
      throw errors.invalidArgument(
        "This business must always have at least one active owner.",
      );
    }
  }

  if (action === "disable") {
    await memberRef.update({
      status: "disabled",
      disabledAt: FieldValue.serverTimestamp(),
      disabledBy: identity.uid,
      disableReason: reason ?? null,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: identity.uid,
    });
  } else if (action === "restore") {
    await memberRef.update({
      status: "active",
      disabledAt: null,
      disabledBy: null,
      disableReason: null,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: identity.uid,
    });
  } else {
    await memberRef.update({
      status: "removed",
      removedAt: FieldValue.serverTimestamp(),
      removedBy: identity.uid,
      removeReason: reason ?? null,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: identity.uid,
    });
    const userRef = db.collection("users").doc(targetUid);
    const userSnap = await userRef.get();
    if (userSnap.data()?.activeBusinessId === businessId) {
      await userRef.set(
        {activeBusinessId: null, updatedAt: FieldValue.serverTimestamp()},
        {merge: true},
      );
    }
  }

  sendSuccess(res, {ok: true, action, targetUid});
});
