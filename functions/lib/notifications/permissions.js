"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.stringSet = stringSet;
exports.effectiveMembership = effectiveMembership;
exports.hasPermission = hasPermission;
exports.hasBranchAccess = hasBranchAccess;
const defaults = {
    owner: ["*"],
    admin: ["approve_sensitive_actions", "view_approval_notifications", "view_staff_activity", "view_staff_notifications", "view_notifications", "view_branch", "receive_push_notifications"],
    manager: ["approve_sensitive_actions", "view_approval_notifications", "view_staff_activity", "view_staff_notifications", "view_notifications", "view_branch", "receive_push_notifications"],
    cashier: ["view_approval_notifications", "view_notifications", "view_branch", "receive_push_notifications"],
    stock_keeper: ["view_notifications", "view_branch", "receive_push_notifications"],
    accountant: ["view_notifications", "view_branch", "receive_push_notifications"],
    staff: ["view_branch"],
};
const aliases = {
    view_branches: "view_branch",
    manage_branch_staff: "assign_staff_to_branches",
};
function stringSet(value) {
    if (!Array.isArray(value))
        return new Set();
    return new Set(value.filter((item) => typeof item === "string")
        .map((item) => aliases[item.trim()] ?? item.trim()).filter(Boolean));
}
function memberRole(member) {
    const value = member.roleId ?? member.role ?? "cashier";
    return typeof value === "string" ? value.trim().toLowerCase() : "cashier";
}
function effectiveMembership(input) {
    const roleId = memberRole(input.member);
    const owner = input.ownerId === input.userId || input.member.isOwner === true ||
        roleId === "owner";
    const explicit = stringSet(input.member.permissions);
    const rolePermissions = stringSet(input.role?.permissions);
    const base = explicit.size ? explicit :
        (rolePermissions.size ? rolePermissions : new Set(defaults[roleId] ?? []));
    const permissions = new Set([...base, ...stringSet(input.member.permissionOverrides)]);
    for (const denial of stringSet(input.member.permissionDenials))
        permissions.delete(denial);
    if (owner)
        permissions.add("*");
    return {
        userId: input.userId,
        active: owner || input.member.status === "active",
        owner,
        permissions,
        assignedBranchIds: stringSet(input.member.assignedBranchIds),
        allBranchesAccess: input.member.allBranchesAccess === true,
    };
}
function hasPermission(member, permission) {
    return member.active && (member.owner || member.permissions.has("*") ||
        member.permissions.has(permission));
}
function hasBranchAccess(member, branchId) {
    if (!branchId)
        return member.active;
    if (!hasPermission(member, "view_branch"))
        return false;
    return member.owner || member.allBranchesAccess || member.assignedBranchIds.has(branchId);
}
//# sourceMappingURL=permissions.js.map