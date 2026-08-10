import { describe, expect, it } from "vitest";
import { hashIdentifier, maskEmail, maskPhone, maskToken } from "@/lib/utils/mask";

describe("mask utilities", () => {
  it("masks emails", () => {
    expect(maskEmail("alice@example.com")).toBe("al***@example.com");
  });

  it("masks phones and tokens", () => {
    expect(maskPhone("+23276123456")).toMatch(/\d{4}$/);
    expect(maskToken("abcdefghijklmnop")).toContain("…");
  });

  it("hashes identifiers stably", () => {
    expect(hashIdentifier("user-1")).toBe(hashIdentifier("user-1"));
    expect(hashIdentifier("user-1")).not.toBe(hashIdentifier("user-2"));
  });
});
