import {describe, expect, it} from "vitest";
import {sabiCommandResponseSchema} from "../src/schemas/sabi-command-schema";

describe("sabiCommandResponseSchema", () => {
  it("accepts a valid create_sale payload", () => {
    const parsed = sabiCommandResponseSchema.parse({
      intent: "create_sale",
      confidence: 0.9,
      items: [
        {
          spokenName: "rice",
          quantity: 2,
          spokenUnitPriceMinor: null,
          action: "add",
        },
      ],
      customerQuery: null,
      payment: {method: "cash", amountPaidMinor: 10000, isCredit: false},
      discount: {type: null, value: null},
      receiptTemplateQuery: null,
      requiresConfirmation: true,
      clarifyingQuestion: null,
      warnings: [],
    });
    expect(parsed.intent).toBe("create_sale");
  });

  it("rejects negative quantities", () => {
    expect(() =>
      sabiCommandResponseSchema.parse({
        intent: "create_sale",
        confidence: 0.5,
        items: [
          {
            spokenName: "oil",
            quantity: -1,
            spokenUnitPriceMinor: null,
            action: "add",
          },
        ],
        customerQuery: null,
        payment: {method: null, amountPaidMinor: null, isCredit: false},
        discount: {type: null, value: null},
        receiptTemplateQuery: null,
        requiresConfirmation: true,
        clarifyingQuestion: null,
        warnings: [],
      }),
    ).toThrow();
  });

  it("rejects percentage above 100", () => {
    expect(() =>
      sabiCommandResponseSchema.parse({
        intent: "apply_discount",
        confidence: 0.8,
        items: [],
        customerQuery: null,
        payment: {method: null, amountPaidMinor: null, isCredit: false},
        discount: {type: "percentage", value: 150},
        receiptTemplateQuery: null,
        requiresConfirmation: true,
        clarifyingQuestion: null,
        warnings: [],
      }),
    ).toThrow();
  });

  it("rejects invalid intents like complete_sale", () => {
    expect(() =>
      sabiCommandResponseSchema.parse({
        intent: "complete_sale",
        confidence: 1,
        items: [],
        customerQuery: null,
        payment: {method: null, amountPaidMinor: null, isCredit: false},
        discount: {type: null, value: null},
        receiptTemplateQuery: null,
        requiresConfirmation: true,
        clarifyingQuestion: null,
        warnings: [],
      }),
    ).toThrow();
  });
});
