import type {VercelRequest, VercelResponse} from "@vercel/node";
import {z} from "zod";
import {FieldValue} from "firebase-admin/firestore";
import {authenticateRequest} from "../../middleware/authenticate-request";
import {enforceRateLimit} from "../../middleware/rate-limit";
import {adminFirestore} from "../../config/firebase-admin";
import {businessIdSchema} from "../../schemas/common-schemas";
import {
  requireAppPermission,
} from "../../services/team/membership-service";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler, readJsonBody} from "../../utils/handler";

const inviteSchema = z.object({
  businessId: businessIdSchema,
  email: z.string().email().optional(),
  phone: z.string().trim().min(5).max(32).optional(),
  displayName: z.string().trim().max(120).optional(),
  roleId: z.string().trim().min(1).max(64),
  roleName: z.string().trim().min(1).max(64),
  permissions: z.array(z.string()).default([]),
  message: z.string().trim().max(500).optional(),
  expiresInDays: z.number().int().min(1).max(30).default(7),
});

function randomInviteCode(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let out = "";
  for (let i = 0; i < 8; i++) {
    out += chars[Math.floor(Math.random() * chars.length)];
  }
  return out;
}

export default createHandler(["POST"], async (req: VercelRequest, res: VercelResponse) => {
  const identity = await authenticateRequest(req);
  const parsed = inviteSchema.safeParse(readJsonBody(req));
  if (!parsed.success) throw errors.invalidArgument("Invalid invitation details.");

  const data = parsed.data;
  if (!data.email && !data.phone) {
    throw errors.invalidArgument("Enter an email or phone number.");
  }

  await requireAppPermission({
    uid: identity.uid,
    businessId: data.businessId,
    permission: "manage_staff",
  });

  await enforceRateLimit({
    uid: identity.uid,
    businessId: data.businessId,
    operation: "team_invite",
    windowSeconds: 60,
    maxPerWindow: 10,
    dailyMax: 100,
  });

  if (data.roleId === "owner") {
    throw errors.permissionDenied("Only ownership transfer can create owners.");
  }

  const db = adminFirestore();
  const biz = await db.collection("businesses").doc(data.businessId).get();
  const businessName = (biz.data()?.name as string | undefined) ?? "Business";
  const ref = db
    .collection("businesses")
    .doc(data.businessId)
    .collection("staff_invitations")
    .doc();

  const inviteCode = randomInviteCode();
  const expiresAt = new Date(
    Date.now() + data.expiresInDays * 24 * 60 * 60 * 1000,
  );

  await ref.set({
    id: ref.id,
    businessId: data.businessId,
    businessName,
    email: data.email ?? null,
    normalizedEmail: data.email?.toLowerCase() ?? null,
    phone: data.phone ?? null,
    normalizedPhone: data.phone ?? null,
    displayName: data.displayName ?? null,
    roleId: data.roleId,
    roleName: data.roleName,
    permissionsSnapshot: data.permissions,
    status: "pending",
    invitedBy: identity.uid,
    invitedByName: identity.email ?? "Admin",
    inviteCode,
    expiresAt,
    message: data.message ?? null,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  sendSuccess(res, {
    invitationId: ref.id,
    inviteCode,
    expiresAt: expiresAt.toISOString(),
    link: `https://app.sabibom.com/invite/${ref.id}`,
  });
});
