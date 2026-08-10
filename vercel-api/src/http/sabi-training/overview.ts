import type {VercelRequest, VercelResponse} from "@vercel/node";
import {authenticateRequest} from "../../middleware/authenticate-request";
import {trainingOverviewQuerySchema} from "../../schemas/sabi-training-schema";
import {listTrainingOverview} from "../../services/sabi-training-service";
import {loadMembership} from "../../services/team/membership-service";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler} from "../../utils/handler";

export default createHandler(
  ["GET"],
  async (req: VercelRequest, res: VercelResponse) => {
    const identity = await authenticateRequest(req);
    const parsed = trainingOverviewQuerySchema.safeParse(req.query);
    if (!parsed.success) throw errors.invalidArgument();
    const membership = await loadMembership({
      uid: identity.uid,
      businessId: parsed.data.businessId,
    });
    if (!membership.isOwner) throw errors.permissionDenied("Owner access required.");
    sendSuccess(res, await listTrainingOverview(parsed.data.businessId));
  },
);

