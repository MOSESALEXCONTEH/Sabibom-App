export type DocumentData = Record<string, unknown>;

const defaults: Record<string, readonly string[]> = {
  owner: ["*"],
  admin: ["approve_sensitive_actions", "view_approval_notifications", "view_staff_activity", "view_staff_notifications", "view_notifications", "view_branch", "receive_push_notifications"],
  manager: ["approve_sensitive_actions", "view_approval_notifications", "view_staff_activity", "view_staff_notifications", "view_notifications", "view_branch", "receive_push_notifications"],
  cashier: ["view_approval_notifications", "view_notifications", "view_branch", "receive_push_notifications"],
  stock_keeper: ["view_notifications", "view_branch", "receive_push_notifications"],
  accountant: ["view_notifications", "view_branch", "receive_push_notifications"],
  staff: ["view_branch"],
};

const aliases: Record<string, string> = {
  view_branches: "view_branch",
  manage_branch_staff: "assign_staff_to_branches",
};

export function stringSet(value: unknown): Set<string> {
  if (!Array.isArray(value)) return new Set();
  return new Set(value.filter((item): item is string => typeof item === "string")
    .map((item) => aliases[item.trim()] ?? item.trim()).filter(Boolean));
}

function memberRole(member: DocumentData): string {
  const value = member.roleId ?? member.role ?? "cashier";
  return typeof value === "string" ? value.trim().toLowerCase() : "cashier";
}

export interface EffectiveMembership {
  userId: string;
  active: boolean;
  owner: boolean;
  permissions: ReadonlySet<string>;
  assignedBranchIds: ReadonlySet<string>;
  allBranchesAccess: boolean;
}

export function effectiveMembership(input: {
  userId: string;
  ownerId?: string;
  member: DocumentData;
  role?: DocumentData;
}): EffectiveMembership {
  const roleId = memberRole(input.member);
  const owner = input.ownerId === input.userId || input.member.isOwner === true ||
    roleId === "owner";
  const explicit = stringSet(input.member.permissions);
  const rolePermissions = stringSet(input.role?.permissions);
  const base = explicit.size ? explicit :
    (rolePermissions.size ? rolePermissions : new Set(defaults[roleId] ?? []));
  const permissions = new Set([...base, ...stringSet(input.member.permissionOverrides)]);
  for (const denial of stringSet(input.member.permissionDenials)) permissions.delete(denial);
  if (owner) permissions.add("*");
  return {
    userId: input.userId,
    active: owner || input.member.status === "active",
    owner,
    permissions,
    assignedBranchIds: stringSet(input.member.assignedBranchIds),
    allBranchesAccess: input.member.allBranchesAccess === true,
  };
}

export function hasPermission(member: EffectiveMembership, permission: string): boolean {
  return member.active && (member.owner || member.permissions.has("*") ||
    member.permissions.has(permission));
}

export function hasBranchAccess(member: EffectiveMembership, branchId?: string): boolean {
  if (!branchId) return member.active;
  if (!hasPermission(member, "view_branch")) return false;
  return member.owner || member.allBranchesAccess || member.assignedBranchIds.has(branchId);
}
