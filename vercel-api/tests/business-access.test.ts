import {describe, expect, it} from "vitest";
import type {BusinessMembership} from "../src/types/authenticated-request";

function roleAllows(
  membership: BusinessMembership,
  permission: "use_sabi" | "upload_business_logo",
): boolean {
  if (membership.isOwner || membership.role === "owner") return true;
  if (permission === "use_sabi") {
    return ["manager", "cashier"].includes(membership.role);
  }
  return membership.role === "manager";
}

describe("business access roles", () => {
  it("allows owners everything", () => {
    expect(
      roleAllows({role: "owner", isOwner: true}, "upload_business_logo"),
    ).toBe(true);
  });

  it("allows cashiers to use Sabi", () => {
    expect(roleAllows({role: "cashier", isOwner: false}, "use_sabi")).toBe(
      true,
    );
  });

  it("rejects cashiers uploading logos", () => {
    expect(
      roleAllows({role: "cashier", isOwner: false}, "upload_business_logo"),
    ).toBe(false);
  });
});
