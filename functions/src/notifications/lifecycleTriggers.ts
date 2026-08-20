import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {
  asString,
  loadBusinessAudience,
  sameStrings,
} from "./business";
import {deliverMany} from "./delivery";
import {activityId, eventKey} from "./ids";

interface LifecycleEvent {
  transition: string;
  actionType: string;
  actorId?: string;
  targetId?: string;
  targetLabel: string;
  personal?: {type: string; title: string; body: string};
}

function status(data: Record<string, unknown> | undefined): string | undefined {
  return asString(data?.status);
}

function memberEvent(
  memberId: string,
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined,
): LifecycleEvent | undefined {
  if (!after) return undefined;
  const label = asString(after.displayName) ?? "Team member";
  if (!before) return {
    transition: "created", actionType: "member_joined", targetId: memberId,
    targetLabel: label, actorId: asString(after.invitedBy),
  };
  const oldStatus = status(before);
  const newStatus = status(after);
  const actorId = asString(after.updatedBy) ?? asString(after.disabledBy) ??
    asString(after.removedBy);
  if (oldStatus !== newStatus) {
    if (newStatus === "disabled") return {
      transition: "disabled", actionType: "member_disabled", actorId,
      targetId: memberId, targetLabel: label,
      personal: {type: "membership_disabled", title: "Membership disabled", body: "Your business membership was disabled."},
    };
    if (oldStatus === "disabled" && newStatus === "active") return {
      transition: "restored", actionType: "member_restored", actorId,
      targetId: memberId, targetLabel: label,
      personal: {type: "membership_restored", title: "Membership restored", body: "Your business membership was restored."},
    };
    if (newStatus === "removed") return {
      transition: "removed", actionType: "member_removed", actorId,
      targetId: memberId, targetLabel: label,
      personal: {type: "membership_removed", title: "Membership removed", body: "Your business membership was removed."},
    };
  }
  const oldRole = asString(before.roleId) ?? asString(before.role);
  const newRole = asString(after.roleId) ?? asString(after.role);
  if (oldRole !== newRole) return {
    transition: `role_${newRole ?? "changed"}`, actionType: "role_changed", actorId,
    targetId: memberId, targetLabel: label,
    personal: {type: "role_changed", title: "Role changed", body: `Your role is now ${asString(after.roleName) ?? "updated"}.`},
  };
  if (!sameStrings(before.permissions, after.permissions) ||
      !sameStrings(before.permissionOverrides, after.permissionOverrides) ||
      !sameStrings(before.permissionDenials, after.permissionDenials)) return {
    transition: "permissions_changed", actionType: "permissions_changed", actorId,
    targetId: memberId, targetLabel: label,
    personal: {type: "permissions_changed", title: "Permissions changed", body: "Your business permissions were updated."},
  };
  return undefined;
}

function invitationEvent(
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined,
): LifecycleEvent | undefined {
  if (!after) return undefined;
  const targetLabel = asString(after.displayName) ?? "Team member";
  if (!before) return {
    transition: "created", actionType: "member_invited",
    actorId: asString(after.invitedBy), targetLabel,
  };
  const oldStatus = status(before);
  const newStatus = status(after);
  if (oldStatus === newStatus) return undefined;
  if (newStatus === "accepted") return {
    transition: "accepted", actionType: "invitation_accepted",
    actorId: asString(after.acceptedBy), targetId: asString(after.acceptedBy),
    targetLabel,
  };
  if (newStatus === "cancelled" || newStatus === "expired") return {
    transition: newStatus, actionType: `invitation_${newStatus}`,
    actorId: asString(after.cancelledBy), targetLabel,
  };
  return undefined;
}

async function writeActivity(input: {
  eventId: string;
  businessId: string;
  entityType: string;
  entityId: string;
  event: LifecycleEvent;
}): Promise<void> {
  const ref = getFirestore().collection("businesses").doc(input.businessId)
    .collection("staff_activity").doc(activityId(input.eventId));
  await ref.create({
    id: ref.id,
    businessId: input.businessId,
    userId: input.event.actorId ?? "system",
    userName: input.event.actorId ? "Team member" : "System",
    userRole: "",
    targetUserId: input.event.targetId ?? null,
    actionType: input.event.actionType,
    entityType: input.entityType,
    entityId: input.entityId,
    entityLabel: input.event.targetLabel,
    description: input.event.actionType.replace(/[._]/g, " "),
    metadata: {},
    generatedBy: "notification_functions",
    createdAt: FieldValue.serverTimestamp(),
    timestamp: FieldValue.serverTimestamp(),
  }).catch((error: unknown) => {
    const code = (error as {code?: string}).code ?? "";
    if (!code.includes("already-exists") && code !== "6") throw error;
  });
}

async function processLifecycle(input: {
  source: string;
  businessId: string;
  entityType: string;
  entityId: string;
  event: LifecycleEvent;
}): Promise<void> {
  const id = eventKey(input.source, input.businessId, input.entityId, input.event.transition);
  await writeActivity({...input, eventId: id});
  if (!input.event.personal || !input.event.targetId) return;
  const audience = await loadBusinessAudience(input.businessId);
  await deliverMany([{
    eventId: id,
    userId: input.event.targetId,
    category: "staffActivity",
    type: input.event.personal.type,
    title: input.event.personal.title,
    body: input.event.personal.body,
    businessId: input.businessId,
    businessName: audience.businessName,
    entityType: input.entityType,
    entityId: input.entityId,
    routeName: "myRole",
    routeParameters: {businessId: input.businessId},
    priority: input.event.personal.type === "membership_removed" ? "high" : "normal",
  }]);
}

export const onStaffInvitationWritten = onDocumentWritten(
  "businesses/{businessId}/staff_invitations/{invitationId}",
  async (trigger) => {
    try {
      const before = trigger.data?.before.exists ? trigger.data.before.data() : undefined;
      const after = trigger.data?.after.exists ? trigger.data.after.data() : undefined;
      const event = invitationEvent(before, after);
      if (!event) return;
      await processLifecycle({source: "invitation", businessId: trigger.params.businessId,
        entityType: "invitation", entityId: trigger.params.invitationId, event});
      if (!before && after) {
        const email = asString(after.normalizedEmail) ?? asString(after.email)?.toLowerCase();
        const phone = asString(after.normalizedPhone) ?? asString(after.phone);
        if (email || phone) {
          const users = getFirestore().collection("users");
          const matches = await Promise.all([
            email ? users.where("email", "==", email).limit(1).get() : undefined,
            phone ? users.where("phoneNumber", "==", phone).limit(1).get() : undefined,
          ]);
          const invitee = matches.find((snapshot) => snapshot && !snapshot.empty)?.docs[0];
          if (invitee) {
            const audience = await loadBusinessAudience(trigger.params.businessId);
            await deliverMany([{
              eventId: eventKey("invitation", trigger.params.businessId, trigger.params.invitationId, "received"),
              userId: invitee.id,
              category: "staffActivity",
              type: "invitation_received",
              title: "Team invitation",
              body: `You were invited to join ${audience.businessName} as ${asString(after.roleName) ?? "a team member"}.`,
              businessId: trigger.params.businessId,
              businessName: audience.businessName,
              entityType: "invitation",
              entityId: trigger.params.invitationId,
              routeName: "inviteWithId",
              routeParameters: {businessId: trigger.params.businessId, invitationId: trigger.params.invitationId},
            }]);
          }
        }
      }
    } catch (error) {
      console.error("invitation lifecycle trigger failed safely", {error: error instanceof Error ? error.message : "unknown"});
    }
  },
);

export const onMembershipWritten = onDocumentWritten(
  "businesses/{businessId}/members/{memberId}",
  async (trigger) => {
    try {
      const before = trigger.data?.before.exists ? trigger.data.before.data() : undefined;
      const after = trigger.data?.after.exists ? trigger.data.after.data() : undefined;
      const event = memberEvent(trigger.params.memberId, before, after);
      if (!event) return;
      await processLifecycle({source: "membership", businessId: trigger.params.businessId,
        entityType: "membership", entityId: trigger.params.memberId, event});
    } catch (error) {
      console.error("membership lifecycle trigger failed safely", {error: error instanceof Error ? error.message : "unknown"});
    }
  },
);

export const onRoleWritten = onDocumentWritten(
  "businesses/{businessId}/roles/{roleId}",
  async (trigger) => {
    try {
      const before = trigger.data?.before.exists ? trigger.data.before.data() : undefined;
      const after = trigger.data?.after.exists ? trigger.data.after.data() : undefined;
      if (!after || after.isSystemRole === true) return;
      const changed = !before || asString(before.name) !== asString(after.name) ||
        before.isActive !== after.isActive || !sameStrings(before.permissions, after.permissions);
      if (!changed) return;
      const transition = before ? "updated" : "created";
      await processLifecycle({source: "role", businessId: trigger.params.businessId,
        entityType: "role", entityId: trigger.params.roleId, event: {
          transition, actionType: `custom_role_${transition}`,
          actorId: asString(after.updatedBy) ?? asString(after.createdBy),
          targetLabel: asString(after.name) ?? "Custom role",
        }});
    } catch (error) {
      console.error("role lifecycle trigger failed safely", {error: error instanceof Error ? error.message : "unknown"});
    }
  },
);
