import { describe, expect, it } from "vitest";
import {
  decodeCursor,
  encodeCursor,
  listQuerySchema,
  parseListQuery,
} from "@/lib/api/pagination";

describe("pagination helpers", () => {
  it("encodes and decodes cursors", () => {
    const encoded = encodeCursor("doc_123");
    expect(decodeCursor(encoded)).toBe("doc_123");
    expect(decodeCursor(undefined)).toBeNull();
  });

  it("parses bounded list query defaults", () => {
    const parsed = parseListQuery(new URLSearchParams());
    expect(parsed.limit).toBe(25);
    expect(parsed.order).toBe("desc");
  });

  it("rejects oversized limits", () => {
    expect(() => listQuerySchema.parse({ limit: 500 })).toThrow();
  });
});
