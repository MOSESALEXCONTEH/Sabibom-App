"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.approvalRecipients = approvalRecipients;
exports.staffObserverRecipients = staffObserverRecipients;
exports.isApprovalOwnedAction = isApprovalOwnedAction;
exports.activityTargetId = activityTargetId;
const permissions_1 = require("./permissions");
function approvalRecipients(input) {
    const assigned = new Set(input.assignedApproverIds ?? []);
    return input.members.filter((member) => member.userId !== input.requesterId && member.active &&
        (assigned.size === 0 || assigned.has(member.userId)) &&
        (0, permissions_1.hasPermission)(member, "approve_sensitive_actions") &&
        (0, permissions_1.hasPermission)(member, "view_approval_notifications") &&
        (0, permissions_1.hasBranchAccess)(member, input.branchId)).map((member) => member.userId).sort();
}
function staffObserverRecipients(input) {
    return input.members.filter((member) => member.userId !== input.actorId && member.userId !== input.targetId &&
        member.active && (0, permissions_1.hasPermission)(member, "view_staff_activity") &&
        (0, permissions_1.hasPermission)(member, "view_staff_notifications") &&
        (0, permissions_1.hasBranchAccess)(member, input.branchId)).map((member) => member.userId).sort();
}
const approvalOwnedActions = new Set([
    "approval_requested", "approval_approved", "approval_rejected",
    "approval_expired",
]);
function isApprovalOwnedAction(actionType) {
    return typeof actionType === "string" && approvalOwnedActions.has(actionType);
}
function activityTargetId(activity) {
    const direct = activity.targetUserId ?? activity.targetUid;
    if (typeof direct === "string" && direct.trim())
        return direct.trim();
    const entityId = activity.entityId ?? activity.referenceId;
    if ((activity.entityType === "member" || activity.entityType === "membership") &&
        typeof entityId === "string" && entityId.trim())
        return entityId.trim();
    return undefined;
}
//# sourceMappingURL=recipients.js.map