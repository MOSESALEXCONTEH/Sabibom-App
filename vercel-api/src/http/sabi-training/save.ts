import type {VercelRequest, VercelResponse} from "@vercel/node";
import {authenticateRequest} from "../../middleware/authenticate-request";
import {trainingExampleSchema} from "../../schemas/sabi-training-schema";
import {saveTrainingExample} from "../../services/sabi-training-service";
import {loadMembership} from "../../services/team/membership-service";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler, readJsonBody} from "../../utils/handler";

export default createHandler(
  ["POST"],
  async (req: VercelRequest, res: VercelResponse) => {
    const identity = await authenticateRequest(req);
    const parsed = trainingExampleSchema.safeParse(readJsonBody(req));
    if (!parsed.success) throw errors.invalidArgument("Check the training example.");
    const membership = await loadMembership({
      uid: identity.uid,
      businessId: parsed.data.businessId,
    });
    if (!membership.isOwner) throw errors.permissionDenied("Owner access required.");
    sendSuccess(
      res,
      await saveTrainingExample({...parsed.data, actorId: identity.uid}),
      parsed.data.id ? 200 : 201,
    );
  },
);

