import {z} from "zod";
import {businessIdSchema} from "./common-schemas";
import {sabiAgentToolSchema} from "./sabi-agent-schema";

export const trainingStatusSchema = z.enum(["draft", "published", "archived"]);

export const trainingExampleSchema = z.object({
  businessId: businessIdSchema,
  id: z.string().trim().min(1).max(128).optional(),
  utterance: z.string().trim().min(2).max(500),
  intent: sabiAgentToolSchema,
  clarification: z.string().trim().max(400).nullable().default(null),
  suggestedPrompt: z.string().trim().min(2).max(400),
  notes: z.string().trim().max(500).nullable().default(null),
  status: trainingStatusSchema.default("draft"),
  sourceUnansweredId: z.string().trim().max(128).nullable().default(null),
});

export const trainingStatusRequestSchema = z.object({
  businessId: businessIdSchema,
  id: z.string().trim().min(1).max(128),
  status: trainingStatusSchema,
});

export const trainingOverviewQuerySchema = z.object({
  businessId: businessIdSchema,
});

export const trainingPreviewSchema = z.object({
  businessId: businessIdSchema,
  message: z.string().trim().min(1).max(1200),
});

