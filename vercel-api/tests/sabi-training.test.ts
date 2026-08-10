import {describe, expect, it} from "vitest";
import {
  trainingExampleSchema,
  trainingStatusRequestSchema,
} from "../src/schemas/sabi-training-schema";
import {trainingMatchScore} from "../src/services/sabi-training-service";

describe("Sabi training contracts", () => {
  it("accepts a publishable owner training example", () => {
    const parsed = trainingExampleSchema.parse({
      businessId: "business-1",
      utterance: "add cutomer",
      intent: "draft_customer",
      clarification: "What is the customer's name?",
      suggestedPrompt: "Add customer James, phone 07892537",
      status: "published",
    });
    expect(parsed.intent).toBe("draft_customer");
    expect(parsed.status).toBe("published");
  });

  it("rejects unsupported tools and statuses", () => {
    expect(() =>
      trainingExampleSchema.parse({
        businessId: "business-1",
        utterance: "remove everything",
        intent: "delete_everything",
        suggestedPrompt: "Delete everything",
        status: "published",
      }),
    ).toThrow();
    expect(() =>
      trainingStatusRequestSchema.parse({
        businessId: "business-1",
        id: "example-1",
        status: "deleted",
      }),
    ).toThrow();
  });
});

describe("Sabi training retrieval scoring", () => {
  it("prioritizes exact and phrase matches", () => {
    expect(trainingMatchScore("add cutomer", "add cutomer")).toBe(100);
    expect(trainingMatchScore("please add cutomer now", "add cutomer")).toBe(70);
  });

  it("scores token overlap and rejects unrelated wording", () => {
    expect(trainingMatchScore("record light bill expense", "light bill")).toBeGreaterThan(0);
    expect(trainingMatchScore("show profit", "add customer")).toBe(0);
  });
});

