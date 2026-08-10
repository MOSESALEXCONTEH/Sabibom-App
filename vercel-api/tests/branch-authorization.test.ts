import {describe, expect, it} from "vitest";
import {resolveBranchAuthorization} from "../src/services/team/branch-access";

describe("branch authorization", () => {
  it("allows owners to access any branch", () => {
    const access = resolveBranchAuthorization({
      uid: "owner",
      ownerId: "owner",
      memberExists: false,
      memberData: {},
    });
    expect(access.canAccessBranch("east")).toBe(true);
  });

  it("allows active members only in assigned branches", () => {
    const access = resolveBranchAuthorization({
      uid: "manager",
      ownerId: "owner",
      memberExists: true,
      memberData: {
        status: "active",
        assignedBranchIds: ["east"],
        permissions: ["view_branch", "manage_branch_operations"],
      },
    });
    expect(access.canAccessBranch("east")).toBe(true);
    expect(access.canAccessBranch("main")).toBe(false);
  });

  it("does not turn all-branch visibility into write access", () => {
    const access = resolveBranchAuthorization({
      uid: "admin",
      ownerId: "owner",
      memberExists: true,
      memberData: {
        status: "active",
        allBranchesAccess: true,
        assignedBranchIds: ["east"],
        permissions: ["view_branch", "view_all_branches"],
      },
    });
    expect(access.canAccessBranch("east")).toBe(true);
    expect(access.canAccessBranch("west")).toBe(false);
  });

  it("does not authorize default branch or empty assignment fallbacks", () => {
    const access = resolveBranchAuthorization({
      uid: "staff",
      ownerId: "owner",
      memberExists: true,
      memberData: {
        status: "active",
        assignedBranchIds: [],
        defaultBranchId: "main",
        permissions: ["view_branch"],
      },
    });
    expect(access.canAccessBranch("main")).toBe(false);
  });

  it("keeps assigned staff compatible when legacy permissions omit view_branch", () => {
    const access = resolveBranchAuthorization({
      uid: "staff",
      ownerId: "owner",
      memberExists: true,
      memberData: {
        roleId: "staff",
        status: "active",
        assignedBranchIds: ["east"],
        permissions: ["create_sale"],
      },
    });
    expect(access.canAccessBranch("east")).toBe(true);
    expect(access.canAccessBranch("main")).toBe(false);
  });

  it("rejects disabled members and permission denials", () => {
    const disabled = resolveBranchAuthorization({
      uid: "staff",
      ownerId: "owner",
      memberExists: true,
      memberData: {
        status: "disabled",
        assignedBranchIds: ["east"],
        permissions: ["view_branch"],
      },
    });
    const denied = resolveBranchAuthorization({
      uid: "staff",
      ownerId: "owner",
      memberExists: true,
      memberData: {
        status: "active",
        assignedBranchIds: ["east"],
        permissions: ["view_branch"],
        permissionDenials: ["view_branch"],
      },
    });
    expect(disabled.canAccessBranch("east")).toBe(false);
    expect(denied.canAccessBranch("east")).toBe(false);
  });
});
