import {describe, expect, it} from "vitest";
import {sabiActionResponseSchema} from "../src/schemas/sabi-action-schema";

describe("sabiActionResponseSchema", () => {
  it("accepts a valid add_customer payload", () => {
    const parsed = sabiActionResponseSchema.parse({
      intent: "add_customer",
      confidence: 0.92,
      customer: {
        name: "Aminata Kamara",
        phone: "+23276123456",
        email: null,
        address: "12 Siaka Stevens St, Freetown",
        notes: null,
      },
      product: null,
      reply: "I prepared Aminata Kamara as a new customer. Confirm to save.",
      requiresConfirmation: true,
      clarifyingQuestion: null,
      warnings: [],
    });
    expect(parsed.intent).toBe("add_customer");
    expect(parsed.customer?.name).toBe("Aminata Kamara");
  });

  it("accepts a valid add_product payload", () => {
    const parsed = sabiActionResponseSchema.parse({
      intent: "add_product",
      confidence: 0.9,
      customer: null,
      product: {
        name: "Palm oil",
        sellingPriceMinor: 5000,
        costPriceMinor: 3500,
        quantity: 24,
        unit: "Bottle",
        lowStockThreshold: 5,
        categoryName: "Cooking",
        description: null,
      },
      reply: "Palm oil is ready to add at 50 Leones. Confirm to save.",
      requiresConfirmation: true,
      clarifyingQuestion: null,
      warnings: [],
    });
    expect(parsed.intent).toBe("add_product");
    expect(parsed.product?.sellingPriceMinor).toBe(5000);
  });

  it("rejects negative prices", () => {
    expect(() =>
      sabiActionResponseSchema.parse({
        intent: "add_product",
        confidence: 0.5,
        customer: null,
        product: {
          name: "Rice",
          sellingPriceMinor: -100,
          costPriceMinor: null,
          quantity: null,
          unit: null,
          lowStockThreshold: null,
          categoryName: null,
          description: null,
        },
        reply: "",
        requiresConfirmation: true,
        clarifyingQuestion: null,
        warnings: [],
      }),
    ).toThrow();
  });

  it("rejects unsupported intents", () => {
    expect(() =>
      sabiActionResponseSchema.parse({
        intent: "delete_customer",
        confidence: 1,
        customer: null,
        product: null,
        reply: "",
        requiresConfirmation: true,
        clarifyingQuestion: null,
        warnings: [],
      }),
    ).toThrow();
  });
});
