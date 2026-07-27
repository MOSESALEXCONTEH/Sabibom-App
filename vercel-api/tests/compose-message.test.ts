import {describe, expect, it} from "vitest";
import {composeMessageRequestSchema} from "../src/schemas/compose-message-schema";

describe("compose message schema", () => {
  it("accepts promo drafts", () => {
    const parsed = composeMessageRequestSchema.parse({
      businessId: "biz-1",
      messageType: "promo",
      notes: "10 percent off rice this weekend",
      businessName: "Demo Shop",
    });
    expect(parsed.messageType).toBe("promo");
  });

  it("rejects unknown message types", () => {
    expect(() =>
      composeMessageRequestSchema.parse({
        businessId: "biz-1",
        messageType: "spam",
      }),
    ).toThrow();
  });
});
