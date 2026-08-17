import type {VercelRequest, VercelResponse} from "@vercel/node";
import {FieldValue} from "firebase-admin/firestore";
import {z} from "zod";
import {adminFirestore} from "../../config/firebase-admin";
import {authenticateRequest} from "../../middleware/authenticate-request";
import {enforceRateLimit} from "../../middleware/rate-limit";
import {businessIdSchema} from "../../schemas/common-schemas";
import {
  enforceBusinessCapacity,
  ENTITLEMENT_KEYS,
} from "../../services/billing/entitlements";
import {requireAppPermission} from "../../services/team/membership-service";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler, readJsonBody} from "../../utils/handler";

const branchSchema = z.object({
  businessId: businessIdSchema,
  name: z.string().trim().min(1).max(120),
  code: z.string().trim().toUpperCase().regex(/^[A-Z0-9_-]{2,12}$/),
  address: z.string().trim().max(240).optional(),
  city: z.string().trim().max(120).optional(),
  country: z.string().trim().max(120).optional(),
  phone: z.string().trim().max(32).optional(),
  email: z.string().trim().email().optional(),
  managerUid: z.string().trim().max(128).optional(),
});

export default createHandler(["POST"], async (req: VercelRequest, res: VercelResponse) => {
  const identity = await authenticateRequest(req);
  const parsed = branchSchema.safeParse(readJsonBody(req));
  if (!parsed.success) throw errors.invalidArgument("Check the branch details and try again.");
  const data = parsed.data;
  if (data.code === "MAIN") throw errors.invalidArgument("Main branch already exists.");

  await requireAppPermission({
    uid: identity.uid,
    businessId: data.businessId,
    permission: "manage_branches",
  });
  await enforceRateLimit({
    uid: identity.uid,
    businessId: data.businessId,
    operation: "branch_create",
    windowSeconds: 60,
    maxPerWindow: 5,
    dailyMax: 30,
  });

  const db = adminFirestore();
  const branches = db.collection("businesses").doc(data.businessId).collection("branches");
  const activeBranches = await branches.where("status", "==", "active").get();
  await enforceBusinessCapacity({
    db,
    businessId: data.businessId,
    entitlement: ENTITLEMENT_KEYS.branchesMax,
    currentUsage: activeBranches.size,
    featureName: "branches",
  });

  const duplicate = await branches.where("code", "==", data.code).limit(1).get();
  if (!duplicate.empty) throw errors.invalidArgument("Branch code already exists.");
  if (data.managerUid) {
    const manager = await db.collection("businesses").doc(data.businessId)
      .collection("members").doc(data.managerUid).get();
    if (!manager.exists || manager.data()?.status !== "active") {
      throw errors.invalidArgument("Assigned manager must be an active member of this business.");
    }
  }

  const ref = branches.doc();
  const branch = {
    branchId: ref.id,
    businessId: data.businessId,
    name: data.name,
    code: data.code,
    address: data.address || null,
    city: data.city || null,
    country: data.country || null,
    phone: data.phone || null,
    email: data.email || null,
    managerUid: data.managerUid || null,
    isMainBranch: false,
    status: "active",
    createdBy: identity.uid,
  };
  const audit = db.collection("businesses").doc(data.businessId)
    .collection("staff_activity").doc();
  const batch = db.batch();
  batch.set(ref, {...branch, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  batch.set(audit, {
    businessId: data.businessId,
    userId: identity.uid,
    userName: identity.email ?? "Team member",
    userRole: "",
    actionType: "branch.created",
    entityType: "branch",
    entityId: ref.id,
    entityLabel: data.name,
    description: "branch created",
    metadata: {branchStatus: "active"},
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  sendSuccess(res, branch, 201);
});
