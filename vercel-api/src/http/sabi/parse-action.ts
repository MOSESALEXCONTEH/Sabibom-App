import type {VercelRequest, VercelResponse} from "@vercel/node";
import {adminFirestore} from "../../config/firebase-admin";
import {authenticateRequest} from "../../middleware/authenticate-request";
import {enforceRateLimit} from "../../middleware/rate-limit";
import {actionCommandSystemPrompt} from "../../prompts/action-command-prompt";
import {
  sabiActionRequestSchema,
  sabiActionResponseSchema,
} from "../../schemas/sabi-action-schema";
import {requireBusinessAccess} from "../../services/business-access-service";
import {consumeSabiRequest} from "../../services/billing/entitlements";
import {groqChatJson} from "../../services/groq-service";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler, readJsonBody} from "../../utils/handler";

export default createHandler(["POST"], async (req: VercelRequest, res: VercelResponse) => {
  const identity = await authenticateRequest(req);
  const parsed = sabiActionRequestSchema.safeParse(readJsonBody(req));
  if (!parsed.success) {
    throw errors.invalidArgument(
      "Please enter or speak a clear instruction.",
    );
  }

  const {businessId, command} = parsed.data;

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
    operation: "parse_action",
    windowSeconds: 60,
    maxPerWindow: 12,
    dailyMax: 250,
  });

  const json = await groqChatJson({
    system: actionCommandSystemPrompt(),
    user: JSON.stringify({instruction: command}),
  });

  const validated = sabiActionResponseSchema.safeParse(json);
  if (!validated.success) {
    throw errors.invalidArgument(
      "I couldn’t understand that safely. Please rephrase your request.",
    );
  }

  sendSuccess(res, {
    ...validated.data,
    requiresConfirmation: true,
  });
});
