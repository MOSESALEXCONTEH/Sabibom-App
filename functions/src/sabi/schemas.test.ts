import assert from "node:assert/strict";
import {describe, it} from "node:test";
import {sabiCommandResponseSchema} from "./schemas";

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
    assert.equal(parsed.intent, "create_sale");
  });

  it("rejects negative quantities", () => {
    assert.throws(() =>
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
    );
  });

  it("rejects invalid intents", () => {
    assert.throws(() =>
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
    );
  });
});
