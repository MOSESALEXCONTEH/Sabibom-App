import type {VercelRequest, VercelResponse} from "@vercel/node";
import {adminFirestore} from "../../config/firebase-admin";
import {authenticateRequest} from "../../middleware/authenticate-request";
import {sendSuccess} from "../../utils/api-response";
import {createHandler} from "../../utils/handler";

export default createHandler(
  ["GET"],
  async (req: VercelRequest, res: VercelResponse) => {
    const identity = await authenticateRequest(req);
    const snap = await adminFirestore()
      .collection("businesses")
      .where("ownerId", "==", identity.uid)
      .limit(50)
      .get();
    sendSuccess(
      res,
      snap.docs
        .filter((doc) => doc.data().deleted !== true)
        .map((doc) => ({
          id: doc.id,
          name: String(doc.data().name ?? doc.data().businessName ?? "Business"),
        }))
        .sort((a, b) => a.name.localeCompare(b.name)),
    );
  },
);

