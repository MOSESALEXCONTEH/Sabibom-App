import {describe, expect, it} from "vitest";
import {detectMetric} from "../src/services/business-data-service";

describe("detectMetric", () => {
  it("detects today’s sales total", () => {
    expect(detectMetric("How much did I sell today?")).toEqual({
      metric: "sales_total",
      period: "today",
    });
  });

  it("detects customer count from Firestore questions", () => {
    expect(detectMetric("How many customers do I have?")).toEqual({
      metric: "customer_count",
      period: "all",
    });
  });

  it("detects sales count without opening a sale draft", () => {
    expect(detectMetric("How many sales do I have?")).toEqual({
      metric: "sales_count",
      period: "all",
    });
  });

  it("detects low stock", () => {
    expect(detectMetric("Which products are low in stock?")).toEqual({
      metric: "low_stock",
      period: "all",
    });
  });

  it("detects products expiring soon", () => {
    expect(detectMetric("Which products expire soon?")).toEqual({
      metric: "products_expiring",
      period: "all",
    });
  });

  it("detects remaining product profit", () => {
    expect(detectMetric("How much potential profit remains in stock?")).toEqual({
      metric: "product_potential_profit",
      period: "all",
    });
  });

  it("returns unknown for unverified topics", () => {
    expect(detectMetric("What is the weather?")).toEqual({
      metric: "unknown",
      period: "today",
    });
  });

  it("detects yesterday sales", () => {
    expect(detectMetric("How much did I sell yesterday?")).toEqual({
      metric: "sales_total",
      period: "yesterday",
    });
  });

  it("detects this week's sales", () => {
    expect(detectMetric("What are this week's sales?")).toEqual({
      metric: "sales_total",
      period: "week",
    });
  });

  it("detects expense spend questions", () => {
    expect(detectMetric("How much did I spend this week?")).toEqual({
      metric: "expense_total",
      period: "week",
    });
  });

  it("detects supplier balances", () => {
    expect(detectMetric("What do I owe suppliers?")).toEqual({
      metric: "supplier_balances",
      period: "all",
    });
  });

  it("detects who owes me", () => {
    expect(detectMetric("Who owes me money?")).toEqual({
      metric: "customer_balances",
      period: "all",
    });
  });

  it("does not map bare look-for-products to low stock", () => {
    expect(detectMetric("Look for products").metric).toBe("unknown");
  });
});
