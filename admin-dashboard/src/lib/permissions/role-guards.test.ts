import { describe, expect, it } from "vitest";
import {
  adminHasPermission,
  permissionsForRole,
} from "@/lib/permissions/registry";

describe("role permission guards", () => {
  it("gives super admin all permissions", () => {
    expect(
      adminHasPermission("super_admin", [], "manage_platform_admins"),
    ).toBe(true);
    expect(adminHasPermission("super_admin", [], "issue_billing_adjustment")).toBe(
      true,
    );
  });

  it("restricts support admin from security settings", () => {
    expect(
      adminHasPermission("support_admin", [], "manage_platform_admins"),
    ).toBe(false);
    expect(adminHasPermission("support_admin", [], "view_security_logs")).toBe(
      false,
    );
    expect(adminHasPermission("support_admin", [], "manage_feedback")).toBe(true);
  });

  it("keeps analyst read-only", () => {
    const perms = permissionsForRole("analyst");
    expect(perms.every((p) => p.startsWith("view_"))).toBe(true);
    expect(adminHasPermission("analyst", [], "manage_users")).toBe(false);
    expect(adminHasPermission("analyst", [], "view_platform_analytics")).toBe(
      true,
    );
  });

  it("restricts finance from user content by default", () => {
    expect(adminHasPermission("finance_admin", [], "view_users")).toBe(false);
    expect(adminHasPermission("finance_admin", [], "view_subscriptions")).toBe(
      true,
    );
  });

  it("does not let custom role invent unknown permissions", () => {
    const perms = permissionsForRole("custom", [
      "view_users",
      "not_a_real_permission",
    ] as unknown as string[]);
    expect(perms).toEqual(["view_users"]);
  });
});
