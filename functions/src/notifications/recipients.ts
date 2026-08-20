import {
  EffectiveMembership,
  hasBranchAccess,
  hasPermission,
} from "./permissions";

export function approvalRecipients(input: {
  members: readonly EffectiveMembership[];
  requesterId: string;
  branchId?: string;
  assignedApproverIds?: readonly string[];
}): string[] {
  const assigned = new Set(input.assignedApproverIds ?? []);
  return input.members.filter((member) =>
    member.userId !== input.requesterId && member.active &&
    (assigned.size === 0 || assigned.has(member.userId)) &&
    hasPermission(member, "approve_sensitive_actions") &&
    hasPermission(member, "view_approval_notifications") &&
    hasBranchAccess(member, input.branchId)
  ).map((member) => member.userId).sort();
}

export function staffObserverRecipients(input: {
  members: readonly EffectiveMembership[];
  actorId?: string;
  targetId?: string;
  branchId?: string;
}): string[] {
  return input.members.filter((member) =>
    member.userId !== input.actorId && member.userId !== input.targetId &&
    member.active && hasPermission(member, "view_staff_activity") &&
    hasPermission(member, "view_staff_notifications") &&
    hasBranchAccess(member, input.branchId)
  ).map((member) => member.userId).sort();
}

const approvalOwnedActions = new Set([
  "approval_requested", "approval_approved", "approval_rejected",
  "approval_expired",
]);

export function isApprovalOwnedAction(actionType: unknown): boolean {
  return typeof actionType === "string" && approvalOwnedActions.has(actionType);
}

export function activityTargetId(activity: Record<string, unknown>): string | undefined {
  const direct = activity.targetUserId ?? activity.targetUid;
  if (typeof direct === "string" && direct.trim()) return direct.trim();
  const entityId = activity.entityId ?? activity.referenceId;
  if ((activity.entityType === "member" || activity.entityType === "membership") &&
      typeof entityId === "string" && entityId.trim()) return entityId.trim();
  return undefined;
}
