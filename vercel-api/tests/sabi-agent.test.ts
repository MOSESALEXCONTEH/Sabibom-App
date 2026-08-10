import {describe, expect, it} from "vitest";
import {
  sabiAgentPlanSchema,
  sabiAgentRequestSchema,
} from "../src/schemas/sabi-agent-schema";
import {inferSabiIntentHint} from "../src/prompts/sabi-agent-prompt";
import {agentRecordMatchesBranch} from "../src/services/sabi-agent-tools";

describe("Sabi agent contracts", () => {
  it("accepts bounded conversation context", () => {
    const parsed = sabiAgentRequestSchema.parse({
      businessId: "business-1",
      branchId: "east",
      message: "give me their names",
      conversation: [
        {role: "user", content: "how many customers do I have?"},
        {role: "assistant", content: "You have four customers."},
      ],
    });
    expect(parsed.conversation).toHaveLength(2);
  });

  it("accepts a safe draft plan", () => {
    const plan = sabiAgentPlanSchema.parse({
      tool: "draft_customer",
      reply: "I prepared James for review.",
      clarification: null,
      suggestedPrompt: null,
      arguments: {name: "James", phone: "07892537"},
    });
    expect(plan.tool).toBe("draft_customer");
    expect(plan.arguments.name).toBe("James");
  });

  it("accepts a clarification with a corrected example prompt", () => {
    const plan = sabiAgentPlanSchema.parse({
      tool: "draft_customer",
      reply: null,
      clarification: "What is the customer's name?",
      suggestedPrompt: "Add customer James, phone 07892537",
      arguments: {},
    });
    expect(plan.suggestedPrompt).toContain("Add customer");
  });

  it("rejects unknown tools", () => {
    expect(() =>
      sabiAgentPlanSchema.parse({
        tool: "delete_everything",
        reply: null,
        clarification: null,
        arguments: {},
      }),
    ).toThrow();
  });
});

describe("Sabi spelling-tolerant intent hints", () => {
  it.each([
    ["add cutomer", "draft_customer"],
    ["add custmer", "draft_customer"],
    ["create a suplier", "draft_supplier"],
    ["new suppier", "draft_supplier"],
    ["add prodcut soap", "draft_product"],
    ["record expens", "draft_expense"],
    ["I paid 200 for light", "draft_expense"],
    ["we bought 10 rice", "draft_purchase"],
    ["make a purchse", "draft_purchase"],
    ["I sold two rice", "draft_sale"],
    ["show my prodit", "profit_report"],
    ["how business do today", "end_of_day_report"],
  ])("maps %s to %s", (message, expected) => {
    expect(inferSabiIntentHint(message)).toBe(expected);
  });
});

describe("Sabi agent branch scope", () => {
  it("keeps branchless legacy records out of East", () => {
    const east = {branchId: "east", isMainBranch: false};
    expect(agentRecordMatchesBranch({branchId: "east"}, east)).toBe(true);
    expect(agentRecordMatchesBranch({branchId: "main"}, east)).toBe(false);
    expect(agentRecordMatchesBranch({}, east)).toBe(false);
  });

  it("keeps branchless compatibility in Main and All Branches", () => {
    expect(
      agentRecordMatchesBranch({}, {branchId: "main-id", isMainBranch: true}),
    ).toBe(true);
    expect(
      agentRecordMatchesBranch(
        {branchId: "east"},
        {branchId: null, isMainBranch: false},
      ),
    ).toBe(true);
  });
});
