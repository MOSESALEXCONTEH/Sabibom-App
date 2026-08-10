import { describe, expect, it } from "vitest";
import {
  adminHasPermission,
  permissionsForRole,
  ROLE_DEFAULT_PERMISSIONS,
} from "@/lib/permissions/registry";

describe("permission registry", () => {
  it("gives super_admin all permissions including manage_platform_admins", () => {
    const perms = permissionsForRole("super_admin");
    expect(perms).toContain("manage_platform_admins");
    expect(perms.length).toBe(ROLE_DEFAULT_PERMISSIONS.super_admin.length);
    expect(adminHasPermission("super_admin", [], "manage_platform_admins")).toBe(
      true,
    );
  });

  it("keeps analyst read-only (no write-style permissions)", () => {
    const perms = permissionsForRole("analyst");
    expect(perms).toContain("view_platform_analytics");
    expect(perms).not.toContain("manage_users");
    expect(perms).not.toContain("manage_platform_admins");
    expect(perms).not.toContain("manage_feature_flags");
    expect(adminHasPermission("analyst", [], "manage_users")).toBe(false);
  });

  it("support_admin cannot manage platform admins or security settings", () => {
    expect(
      adminHasPermission("support_admin", [], "manage_platform_admins"),
    ).toBe(false);
    expect(
      adminHasPermission("support_admin", [], "manage_maintenance_mode"),
    ).toBe(false);
    expect(adminHasPermission("support_admin", [], "manage_feedback")).toBe(
      true,
    );
  });
});
