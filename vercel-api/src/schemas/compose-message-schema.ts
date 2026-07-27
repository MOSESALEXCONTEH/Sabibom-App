import {z} from "zod";
import {businessIdSchema} from "./common-schemas";

export const composeMessageRequestSchema = z.object({
  businessId: businessIdSchema,
  messageType: z.enum([
    "greeting",
    "new_product",
    "promo",
    "thank_you",
    "custom",
  ]),
  notes: z.string().max(500).optional().nullable(),
  customerName: z.string().max(120).optional().nullable(),
  businessName: z.string().max(120).optional().nullable(),
});

export type ComposeMessageRequest = z.infer<typeof composeMessageRequestSchema>;
