import {z} from "zod";
import {businessIdSchema} from "./common-schemas";

export const MAX_UPLOAD_BYTES = Math.floor(1.5 * 1024 * 1024);

export const pinataUploadRequestSchema = z.object({
  businessId: businessIdSchema,
  fileName: z.string().min(1).max(180),
  mimeType: z.enum(["image/jpeg", "image/png", "image/webp"]),
  fileSize: z.number().int().positive().max(MAX_UPLOAD_BYTES),
  purpose: z
    .enum(["business_logo", "expense_receipt", "feedback_attachment"])
    .default("business_logo"),
  /** Base64-encoded image bytes (no data: URL prefix required). */
  fileBase64: z.string().min(8).max(Math.ceil(MAX_UPLOAD_BYTES * 1.4) + 64),
});
