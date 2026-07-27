import {z} from "zod";
import {businessIdSchema} from "./common-schemas";

export const businessQuestionRequestSchema = z.object({
  businessId: businessIdSchema,
  question: z.string().trim().min(3).max(500),
  timezone: z.string().trim().max(80).optional(),
  /** `en` (default) or `krio` for Sierra Leone Krio replies. */
  replyLanguage: z.enum(["en", "krio"]).optional(),
});
