import {z} from "zod";

export const sabiCommandRequestSchema = z.object({
  businessId: z.string().min(1).max(128),
  transcript: z.string().trim().min(1).max(1200),
  draftSummary: z
    .object({
      itemCount: z.number().int().nonnegative().optional(),
      customerName: z.string().nullable().optional(),
      paymentMethod: z.string().nullable().optional(),
      totalMinor: z.number().int().nonnegative().optional(),
    })
    .optional(),
});

export const sabiCommandResponseSchema = z.object({
  intent: z.enum([
    "create_sale",
    "modify_sale",
    "select_customer",
    "set_payment",
    "select_template",
    "generate_pdf",
    "unknown",
  ]),
  confidence: z.number().min(0).max(1),
  items: z
    .array(
      z.object({
        spokenName: z.string().min(1).max(120),
        quantity: z.number().positive().max(100000),
        spokenUnitPriceMinor: z.number().int().nonnegative().nullable(),
        action: z.enum(["add", "remove", "set_quantity"]),
      }),
    )
    .max(40),
  customerQuery: z.string().max(120).nullable(),
  payment: z.object({
    method: z
      .enum(["cash", "mobile_money", "bank_transfer", "card", "credit"])
      .nullable(),
    amountPaidMinor: z.number().int().nonnegative().nullable(),
    isCredit: z.boolean(),
  }),
  discount: z.object({
    type: z.enum(["fixed", "percentage"]).nullable(),
    value: z.number().nonnegative().nullable(),
  }),
  receiptTemplateQuery: z.string().max(80).nullable(),
  requiresConfirmation: z.boolean(),
  clarifyingQuestion: z.string().max(280).nullable(),
  warnings: z.array(z.string().max(200)).max(20),
});

export type SabiCommandResponse = z.infer<typeof sabiCommandResponseSchema>;

export const businessQuestionRequestSchema = z.object({
  businessId: z.string().min(1).max(128),
  question: z.string().trim().min(3).max(500),
});

export const businessQuestionMetricSchema = z.object({
  metric: z.enum([
    "sales_total",
    "sales_count",
    "customer_count",
    "product_count",
    "low_stock",
    "customer_balances",
    "best_sellers",
    "recent_sales",
    "cash_paid",
    "unknown",
  ]),
  period: z.enum(["today", "week", "month", "all"]).default("today"),
});
