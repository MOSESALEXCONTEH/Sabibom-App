import {z} from "zod";
import {businessIdSchema} from "./common-schemas";

export const sabiActionRequestSchema = z.object({
  businessId: businessIdSchema,
  command: z.string().trim().min(1).max(1200),
});

const customerDetailsSchema = z.object({
  name: z.string().min(1).max(120),
  phone: z.string().max(40).nullable(),
  email: z.string().max(160).nullable(),
  address: z.string().max(240).nullable(),
  notes: z.string().max(400).nullable(),
});

const productDetailsSchema = z.object({
  name: z.string().min(1).max(120),
  sellingPriceMinor: z.number().int().nonnegative().nullable(),
  costPriceMinor: z.number().int().nonnegative().nullable(),
  quantity: z.number().nonnegative().max(1000000).nullable(),
  unit: z.string().max(40).nullable(),
  lowStockThreshold: z.number().nonnegative().max(1000000).nullable(),
  categoryName: z.string().max(80).nullable(),
  description: z.string().max(400).nullable(),
});

export const sabiActionResponseSchema = z.object({
  intent: z.enum([
    "add_customer",
    "add_product",
    "create_receipt",
    "create_expense",
    "create_supplier",
    "create_purchase",
    "ask_expenses",
    "ask_profit",
    "ask_supplier_balance",
    "ask_stock_value",
    "unknown",
  ]),
  confidence: z.number().min(0).max(1),
  customer: customerDetailsSchema.nullable(),
  product: productDetailsSchema.nullable(),
  expense: z
    .object({
      amountMinor: z.number().int().positive().nullable(),
      categoryName: z.string().max(80).nullable(),
      description: z.string().max(240).nullable(),
      paymentMethod: z
        .enum([
          "cash",
          "mobile_money",
          "bank_transfer",
          "card",
          "credit",
          "other",
        ])
        .nullable(),
    })
    .nullable()
    .optional(),
  supplier: z
    .object({
      name: z.string().min(1).max(120).nullable(),
      phone: z.string().max(40).nullable(),
    })
    .nullable()
    .optional(),
  reply: z.string().max(400),
  requiresConfirmation: z.boolean(),
  clarifyingQuestion: z.string().max(280).nullable(),
  warnings: z.array(z.string().max(200)).max(20),
});

export type SabiActionResponse = z.infer<typeof sabiActionResponseSchema>;
