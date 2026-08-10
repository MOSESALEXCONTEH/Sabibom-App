type MemberData = Record<string, unknown>;

export interface BranchAuthorization {
  isOwner: boolean;
  assignedBranchIds: Set<string>;
  canAccessBranch: (branchId: string) => boolean;
}

function stringSet(value: unknown): Set<string> {
  if (!Array.isArray(value)) return new Set();
  return new Set(
    value
      .filter((item): item is string => typeof item === "string")
      .map((item) => item.trim())
      .filter(Boolean),
  );
}

export function resolveBranchAuthorization(input: {
  uid: string;
  ownerId: unknown;
  memberExists: boolean;
  memberData: MemberData;
}): BranchAuthorization {
  const isOwner =
    input.ownerId === input.uid ||
    input.memberData.isOwner === true ||
    input.memberData.role === "owner" ||
    input.memberData.roleId === "owner";
  const active =
    input.memberExists && input.memberData.status === "active";
  const assignedBranchIds = stringSet(input.memberData.assignedBranchIds);
  const permissions = new Set([
    ...stringSet(input.memberData.permissions),
    ...stringSet(input.memberData.permissionOverrides),
  ]);
  const denials = stringSet(input.memberData.permissionDenials);
  const role = String(
    input.memberData.roleId || input.memberData.role || "",
  );
  const roleHasDefaultBranchAccess = [
    "admin",
    "manager",
    "cashier",
    "staff",
    "stock_keeper",
    "accountant",
  ].includes(role);
  const mayView =
    !denials.has("view_branch") &&
    (permissions.has("view_branch") ||
      permissions.has("view_branches") ||
      roleHasDefaultBranchAccess);

  return {
    isOwner,
    assignedBranchIds,
    canAccessBranch: (branchId: string) =>
      isOwner || (active && mayView && assignedBranchIds.has(branchId)),
  };
}
