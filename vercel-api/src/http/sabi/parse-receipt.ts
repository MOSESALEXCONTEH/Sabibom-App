import type {VercelRequest, VercelResponse} from "@vercel/node";
import {adminFirestore} from "../../config/firebase-admin";
import {authenticateRequest} from "../../middleware/authenticate-request";
import {enforceRateLimit} from "../../middleware/rate-limit";
import {receiptCommandSystemPrompt} from "../../prompts/receipt-command-prompt";
import {
  sabiCommandRequestSchema,
  sabiCommandResponseSchema,
} from "../../schemas/sabi-command-schema";
import {requireBusinessAccess} from "../../services/business-access-service";
import {consumeSabiRequest} from "../../services/billing/entitlements";
import {groqChatJson} from "../../services/groq-service";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler, readJsonBody} from "../../utils/handler";

export default createHandler(["POST"], async (req: VercelRequest, res: VercelResponse) => {
  const identity = await authenticateRequest(req);
  const parsed = sabiCommandRequestSchema.safeParse(readJsonBody(req));
  if (!parsed.success) {
    throw errors.invalidArgument(
      "Please enter or speak a clear instruction.",
    );
  }

  const command = (parsed.data.command ?? parsed.data.transcript ?? "").trim();
  const draft = parsed.data.currentDraft ?? parsed.data.draftSummary ?? null;
  const {businessId} = parsed.data;

  await requireBusinessAccess({
    uid: identity.uid,
    businessId,
    requiredPermission: "use_sabi",
  });
  await consumeSabiRequest({
    db: adminFirestore(),
    businessId,
    uid: identity.uid,
  });

  await enforceRateLimit({
    uid: identity.uid,
    businessId,
    operation: "parse_receipt",
    windowSeconds: 60,
    maxPerWindow: 12,
    dailyMax: 250,
  });

  const json = await groqChatJson({
    system: receiptCommandSystemPrompt(),
    user: JSON.stringify({
      transcript: command,
      draftSummary: draft,
      schemaHint: {
        intent:
          "create_sale|modify_sale|select_customer|set_payment|apply_discount|select_template|generate_pdf|cancel_sale|unknown",
        items: [
          {
            spokenName: "string",
            quantity: 1,
            spokenUnit: "bags|bottles|kg|null",
            quantityInput: "2 bags|null",
            spokenUnitPriceMinor: null,
            spokenUnitPriceText: "50 Le|paid|null",
            action: "add|remove|set_quantity",
          },
        ],
        customerQuery: null,
        payment: {method: null, amountPaidMinor: null, isCredit: false},
        discount: {type: null, value: null},
        receiptTemplateQuery: null,
        requiresConfirmation: true,
        clarifyingQuestion: null,
        warnings: [],
        confidence: 0.0,
      },
    }),
  });

  const validated = sabiCommandResponseSchema.safeParse(json);
  if (!validated.success) {
    throw errors.invalidArgument(
      "I couldn’t understand that safely. Please rephrase or enter the sale manually.",
    );
  }

  sendSuccess(res, {
    ...validated.data,
    requiresConfirmation: true,
  });
});
