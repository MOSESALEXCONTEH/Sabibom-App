import type {VercelRequest, VercelResponse} from "@vercel/node";
import {adminFirestore} from "../../config/firebase-admin";
import {authenticateRequest} from "../../middleware/authenticate-request";
import {enforceRateLimit} from "../../middleware/rate-limit";
import {
  composeCustomerMessageSystemPrompt,
  composeMessageTypeLabel,
} from "../../prompts/compose-message-prompt";
import {composeMessageRequestSchema} from "../../schemas/compose-message-schema";
import {requireBusinessAccess} from "../../services/business-access-service";
import {consumeSabiRequest} from "../../services/billing/entitlements";
import {groqChatJson} from "../../services/groq-service";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler, readJsonBody} from "../../utils/handler";

export default createHandler(["POST"], async (req: VercelRequest, res: VercelResponse) => {
  const identity = await authenticateRequest(req);
  const parsed = composeMessageRequestSchema.safeParse(readJsonBody(req));
  if (!parsed.success) {
    throw errors.invalidArgument(
      "Please choose a message type and try again.",
    );
  }

  const {businessId, messageType, notes, customerName, businessName} =
    parsed.data;

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
    operation: "compose_message",
    windowSeconds: 60,
    maxPerWindow: 20,
    dailyMax: 200,
  });

  const json = await groqChatJson({
    system: composeCustomerMessageSystemPrompt(),
    user: JSON.stringify({
      messageType,
      messageTypeLabel: composeMessageTypeLabel(messageType),
      notes: notes?.trim() || null,
      customerName: customerName?.trim() || null,
      businessName: businessName?.trim() || null,
      localeHint: "global merchant messaging customers",
    }),
    temperature: 0.5,
  });

  const message =
    json &&
    typeof json === "object" &&
    "message" in json &&
    typeof (json as {message?: unknown}).message === "string"
      ? String((json as {message: string}).message).trim()
      : "";

  if (!message) {
    throw errors.invalidArgument(
      "Sabi could not draft that message. Please try again with clearer notes.",
    );
  }

  sendSuccess(res, {
    message: message.slice(0, 400),
    messageType,
  });
});
