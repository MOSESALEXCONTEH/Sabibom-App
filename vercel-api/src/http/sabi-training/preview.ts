import type {VercelRequest, VercelResponse} from "@vercel/node";
import {authenticateRequest} from "../../middleware/authenticate-request";
import {inferSabiIntentHint} from "../../prompts/sabi-agent-prompt";
import {trainingPreviewSchema} from "../../schemas/sabi-training-schema";
import {findPublishedTrainingExamples} from "../../services/sabi-training-service";
import {loadMembership} from "../../services/team/membership-service";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler, readJsonBody} from "../../utils/handler";

export default createHandler(
  ["POST"],
  async (req: VercelRequest, res: VercelResponse) => {
    const identity = await authenticateRequest(req);
    const parsed = trainingPreviewSchema.safeParse(readJsonBody(req));
    if (!parsed.success) throw errors.invalidArgument();
    const membership = await loadMembership({
      uid: identity.uid,
      businessId: parsed.data.businessId,
    });
    if (!membership.isOwner) throw errors.permissionDenied("Owner access required.");
    const matches = await findPublishedTrainingExamples({
      businessId: parsed.data.businessId,
      message: parsed.data.message,
    });
    sendSuccess(res, {
      builtInIntent: inferSabiIntentHint(parsed.data.message),
      matchedExamples: matches,
      resolvedIntent: matches[0]?.intent ?? inferSabiIntentHint(parsed.data.message),
    });
  },
);

