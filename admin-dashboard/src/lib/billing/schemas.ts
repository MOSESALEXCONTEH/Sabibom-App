import { z } from "zod";

export const PLAN_STATUSES = ["draft", "active", "retired"] as const;
export const PLAN_INTERVALS = ["monthly", "yearly", "lifetime"] as const;

/** Draft/read-only plan management — no payment processing fields required. */
export const subscriptionPlanCreateSchema = z.object({
  name: z.string().trim().min(1).max(120),
  code: z
    .string()
    .trim()
    .min(2)
    .max(64)
    .regex(/^[a-z0-9_.-]+$/i, "Code must be alphanumeric with _ . -"),
  description: z.string().trim().max(2000).optional().nullable(),
  priceAmount: z.coerce.number().min(0).max(1_000_000).default(0),
  currency: z.string().trim().length(3).default("SLE"),
  interval: z.enum(PLAN_INTERVALS).default("monthly"),
  features: z.array(z.string().trim().min(1).max(200)).max(50).default([]),
  /** New plans always start as draft; active/retired only via PATCH. */
  status: z.literal("draft").default("draft"),
});

export const subscriptionPlanPatchSchema = z.object({
  name: z.string().trim().min(1).max(120).optional(),
  description: z.string().trim().max(2000).optional().nullable(),
  priceAmount: z.coerce.number().min(0).max(1_000_000).optional(),
  currency: z.string().trim().length(3).optional(),
  interval: z.enum(PLAN_INTERVALS).optional(),
  features: z.array(z.string().trim().min(1).max(200)).max(50).optional(),
  status: z.enum(PLAN_STATUSES).optional(),
});

export type SubscriptionPlanCreate = z.infer<typeof subscriptionPlanCreateSchema>;
export type SubscriptionPlanPatch = z.infer<typeof subscriptionPlanPatchSchema>;
