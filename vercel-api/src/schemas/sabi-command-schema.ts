import {z} from "zod";
import {businessIdSchema} from "./common-schemas";

export const sabiCommandRequestSchema = z.object({
  businessId: businessIdSchema,
  command: z.string().trim().min(1).max(1200).optional(),
  transcript: z.string().trim().min(1).max(1200).optional(),
  currentDraft: z
    .object({
      itemCount: z.number().int().nonnegative().optional(),
      customerName: z.string().nullable().optional(),
      paymentMethod: z.string().nullable().optional(),
      totalMinor: z.number().int().nonnegative().optional(),
    })
    .optional(),
  draftSummary: z
    .object({
      itemCount: z.number().int().nonnegative().optional(),
      customerName: z.string().nullable().optional(),
      paymentMethod: z.string().nullable().optional(),
      totalMinor: z.number().int().nonnegative().optional(),
    })
    .optional(),
}).superRefine((value, ctx) => {
  const text = (value.command ?? value.transcript ?? "").trim();
  if (!text) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "command_required",
      path: ["command"],
    });
  }
});

export const sabiCommandResponseSchema = z.object({
  intent: z.enum([
    "create_sale",
    "modify_sale",
    "select_customer",
    "set_payment",
    "apply_discount",
    "select_template",
    "generate_pdf",
    "cancel_sale",
    "unknown",
  ]),
  confidence: z.number().min(0).max(1),
  items: z
    .array(
      z.object({
        spokenName: z.string().min(1).max(120),
        quantity: z.number().positive().max(100000),
        spokenUnit: z.string().min(1).max(40).nullable().optional(),
        quantityInput: z.string().min(1).max(80).nullable().optional(),
        spokenUnitPriceMinor: z.number().int().nonnegative().nullable(),
        spokenUnitPriceText: z.string().min(1).max(80).nullable().optional(),
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
  discount: z
    .object({
      type: z.enum(["fixed", "percentage"]).nullable(),
      value: z.number().nonnegative().nullable(),
    })
    .superRefine((discount, ctx) => {
      if (
        discount.type === "percentage" &&
        discount.value != null &&
        discount.value > 100
      ) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: "percentage_above_100",
        });
      }
    }),
  receiptTemplateQuery: z.string().max(80).nullable(),
  requiresConfirmation: z.boolean(),
  clarifyingQuestion: z.string().max(280).nullable(),
  warnings: z.array(z.string().max(200)).max(20),
});

export type SabiCommandResponse = z.infer<typeof sabiCommandResponseSchema>;
