import type {VercelRequest, VercelResponse} from "@vercel/node";
import {authenticateRequest} from "../../middleware/authenticate-request";
import {trainingStatusRequestSchema} from "../../schemas/sabi-training-schema";
import {updateTrainingStatus} from "../../services/sabi-training-service";
import {loadMembership} from "../../services/team/membership-service";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler, readJsonBody} from "../../utils/handler";

export default createHandler(
  ["POST"],
  async (req: VercelRequest, res: VercelResponse) => {
    const identity = await authenticateRequest(req);
    const parsed = trainingStatusRequestSchema.safeParse(readJsonBody(req));
    if (!parsed.success) throw errors.invalidArgument();
    const membership = await loadMembership({
      uid: identity.uid,
      businessId: parsed.data.businessId,
    });
    if (!membership.isOwner) throw errors.permissionDenied("Owner access required.");
    await updateTrainingStatus({...parsed.data, actorId: identity.uid});
    sendSuccess(res, {id: parsed.data.id, status: parsed.data.status});
  },
);

