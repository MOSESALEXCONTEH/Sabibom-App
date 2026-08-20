"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onRoleWritten = exports.onMembershipWritten = exports.onStaffInvitationWritten = void 0;
const firestore_1 = require("firebase-admin/firestore");
const firestore_2 = require("firebase-functions/v2/firestore");
const business_1 = require("./business");
const delivery_1 = require("./delivery");
const ids_1 = require("./ids");
function status(data) {
    return (0, business_1.asString)(data?.status);
}
function memberEvent(memberId, before, after) {
    if (!after)
        return undefined;
    const label = (0, business_1.asString)(after.displayName) ?? "Team member";
    if (!before)
        return {
            transition: "created", actionType: "member_joined", targetId: memberId,
            targetLabel: label, actorId: (0, business_1.asString)(after.invitedBy),
        };
    const oldStatus = status(before);
    const newStatus = status(after);
    const actorId = (0, business_1.asString)(after.updatedBy) ?? (0, business_1.asString)(after.disabledBy) ??
        (0, business_1.asString)(after.removedBy);
    if (oldStatus !== newStatus) {
        if (newStatus === "disabled")
            return {
                transition: "disabled", actionType: "member_disabled", actorId,
                targetId: memberId, targetLabel: label,
                personal: { type: "membership_disabled", title: "Membership disabled", body: "Your business membership was disabled." },
            };
        if (oldStatus === "disabled" && newStatus === "active")
            return {
                transition: "restored", actionType: "member_restored", actorId,
                targetId: memberId, targetLabel: label,
                personal: { type: "membership_restored", title: "Membership restored", body: "Your business membership was restored." },
            };
        if (newStatus === "removed")
            return {
                transition: "removed", actionType: "member_removed", actorId,
                targetId: memberId, targetLabel: label,
                personal: { type: "membership_removed", title: "Membership removed", body: "Your business membership was removed." },
            };
    }
    const oldRole = (0, business_1.asString)(before.roleId) ?? (0, business_1.asString)(before.role);
    const newRole = (0, business_1.asString)(after.roleId) ?? (0, business_1.asString)(after.role);
    if (oldRole !== newRole)
        return {
            transition: `role_${newRole ?? "changed"}`, actionType: "role_changed", actorId,
            targetId: memberId, targetLabel: label,
            personal: { type: "role_changed", title: "Role changed", body: `Your role is now ${(0, business_1.asString)(after.roleName) ?? "updated"}.` },
        };
    if (!(0, business_1.sameStrings)(before.permissions, after.permissions) ||
        !(0, business_1.sameStrings)(before.permissionOverrides, after.permissionOverrides) ||
        !(0, business_1.sameStrings)(before.permissionDenials, after.permissionDenials))
        return {
            transition: "permissions_changed", actionType: "permissions_changed", actorId,
            targetId: memberId, targetLabel: label,
            personal: { type: "permissions_changed", title: "Permissions changed", body: "Your business permissions were updated." },
        };
    return undefined;
}
function invitationEvent(before, after) {
    if (!after)
        return undefined;
    const targetLabel = (0, business_1.asString)(after.displayName) ?? "Team member";
    if (!before)
        return {
            transition: "created", actionType: "member_invited",
            actorId: (0, business_1.asString)(after.invitedBy), targetLabel,
        };
    const oldStatus = status(before);
    const newStatus = status(after);
    if (oldStatus === newStatus)
        return undefined;
    if (newStatus === "accepted")
        return {
            transition: "accepted", actionType: "invitation_accepted",
            actorId: (0, business_1.asString)(after.acceptedBy), targetId: (0, business_1.asString)(after.acceptedBy),
            targetLabel,
        };
    if (newStatus === "cancelled" || newStatus === "expired")
        return {
            transition: newStatus, actionType: `invitation_${newStatus}`,
            actorId: (0, business_1.asString)(after.cancelledBy), targetLabel,
        };
    return undefined;
}
async function writeActivity(input) {
    const ref = (0, firestore_1.getFirestore)().collection("businesses").doc(input.businessId)
        .collection("staff_activity").doc((0, ids_1.activityId)(input.eventId));
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
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        timestamp: firestore_1.FieldValue.serverTimestamp(),
    }).catch((error) => {
        const code = error.code ?? "";
        if (!code.includes("already-exists") && code !== "6")
            throw error;
    });
}
async function processLifecycle(input) {
    const id = (0, ids_1.eventKey)(input.source, input.businessId, input.entityId, input.event.transition);
    await writeActivity({ ...input, eventId: id });
    if (!input.event.personal || !input.event.targetId)
        return;
    const audience = await (0, business_1.loadBusinessAudience)(input.businessId);
    await (0, delivery_1.deliverMany)([{
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
            routeParameters: { businessId: input.businessId },
            priority: input.event.personal.type === "membership_removed" ? "high" : "normal",
        }]);
}
exports.onStaffInvitationWritten = (0, firestore_2.onDocumentWritten)("businesses/{businessId}/staff_invitations/{invitationId}", async (trigger) => {
    try {
        const before = trigger.data?.before.exists ? trigger.data.before.data() : undefined;
        const after = trigger.data?.after.exists ? trigger.data.after.data() : undefined;
        const event = invitationEvent(before, after);
        if (!event)
            return;
        await processLifecycle({ source: "invitation", businessId: trigger.params.businessId,
            entityType: "invitation", entityId: trigger.params.invitationId, event });
        if (!before && after) {
            const email = (0, business_1.asString)(after.normalizedEmail) ?? (0, business_1.asString)(after.email)?.toLowerCase();
            const phone = (0, business_1.asString)(after.normalizedPhone) ?? (0, business_1.asString)(after.phone);
            if (email || phone) {
                const users = (0, firestore_1.getFirestore)().collection("users");
                const matches = await Promise.all([
                    email ? users.where("email", "==", email).limit(1).get() : undefined,
                    phone ? users.where("phoneNumber", "==", phone).limit(1).get() : undefined,
                ]);
                const invitee = matches.find((snapshot) => snapshot && !snapshot.empty)?.docs[0];
                if (invitee) {
                    const audience = await (0, business_1.loadBusinessAudience)(trigger.params.businessId);
                    await (0, delivery_1.deliverMany)([{
                            eventId: (0, ids_1.eventKey)("invitation", trigger.params.businessId, trigger.params.invitationId, "received"),
                            userId: invitee.id,
                            category: "staffActivity",
                            type: "invitation_received",
                            title: "Team invitation",
                            body: `You were invited to join ${audience.businessName} as ${(0, business_1.asString)(after.roleName) ?? "a team member"}.`,
                            businessId: trigger.params.businessId,
                            businessName: audience.businessName,
                            entityType: "invitation",
                            entityId: trigger.params.invitationId,
                            routeName: "inviteWithId",
                            routeParameters: { businessId: trigger.params.businessId, invitationId: trigger.params.invitationId },
                        }]);
                }
            }
        }
    }
    catch (error) {
        console.error("invitation lifecycle trigger failed safely", { error: error instanceof Error ? error.message : "unknown" });
    }
});
exports.onMembershipWritten = (0, firestore_2.onDocumentWritten)("businesses/{businessId}/members/{memberId}", async (trigger) => {
    try {
        const before = trigger.data?.before.exists ? trigger.data.before.data() : undefined;
        const after = trigger.data?.after.exists ? trigger.data.after.data() : undefined;
        const event = memberEvent(trigger.params.memberId, before, after);
        if (!event)
            return;
        await processLifecycle({ source: "membership", businessId: trigger.params.businessId,
            entityType: "membership", entityId: trigger.params.memberId, event });
    }
    catch (error) {
        console.error("membership lifecycle trigger failed safely", { error: error instanceof Error ? error.message : "unknown" });
    }
});
exports.onRoleWritten = (0, firestore_2.onDocumentWritten)("businesses/{businessId}/roles/{roleId}", async (trigger) => {
    try {
        const before = trigger.data?.before.exists ? trigger.data.before.data() : undefined;
        const after = trigger.data?.after.exists ? trigger.data.after.data() : undefined;
        if (!after || after.isSystemRole === true)
            return;
        const changed = !before || (0, business_1.asString)(before.name) !== (0, business_1.asString)(after.name) ||
            before.isActive !== after.isActive || !(0, business_1.sameStrings)(before.permissions, after.permissions);
        if (!changed)
            return;
        const transition = before ? "updated" : "created";
        await processLifecycle({ source: "role", businessId: trigger.params.businessId,
            entityType: "role", entityId: trigger.params.roleId, event: {
                transition, actionType: `custom_role_${transition}`,
                actorId: (0, business_1.asString)(after.updatedBy) ?? (0, business_1.asString)(after.createdBy),
                targetLabel: (0, business_1.asString)(after.name) ?? "Custom role",
            } });
    }
    catch (error) {
        console.error("role lifecycle trigger failed safely", { error: error instanceof Error ? error.message : "unknown" });
    }
});
//# sourceMappingURL=lifecycleTriggers.js.map