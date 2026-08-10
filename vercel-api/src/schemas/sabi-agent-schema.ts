import {z} from "zod";
import {businessIdSchema} from "./common-schemas";

export const sabiAgentRequestSchema = z.object({
  businessId: businessIdSchema,
  branchId: z.string().trim().min(1).max(128).nullable(),
  message: z.string().trim().min(1).max(1200),
  conversation: z
    .array(
      z.object({
        role: z.enum(["user", "assistant"]),
        content: z.string().trim().min(1).max(1200),
      }),
    )
    .max(12)
    .default([]),
});

export const sabiAgentToolSchema = z.enum([
  "answer_general",
  "list_customers",
  "list_suppliers",
  "list_products",
  "check_low_stock",
  "sales_report",
  "profit_report",
  "end_of_day_report",
  "draft_customer",
  "draft_supplier",
  "draft_product",
  "draft_expense",
  "draft_sale",
  "draft_purchase",
]);

export const sabiAgentPlanSchema = z.object({
  tool: sabiAgentToolSchema,
  reply: z.string().max(600).nullable().default(null),
  clarification: z.string().max(400).nullable().default(null),
  suggestedPrompt: z.string().max(400).nullable().default(null),
  arguments: z.record(z.unknown()).default({}),
});

export type SabiAgentPlan = z.infer<typeof sabiAgentPlanSchema>;
