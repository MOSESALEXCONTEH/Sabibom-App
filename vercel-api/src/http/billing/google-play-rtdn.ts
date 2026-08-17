import type {VercelRequest, VercelResponse} from "@vercel/node";
import {adminFirestore} from "../../config/firebase-admin";
import {getEnv} from "../../config/env";
import {
  purchaseTokenHash,
  verifyAndPersistGooglePlaySubscription,
} from "../../services/billing/google-play";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler, readJsonBody} from "../../utils/handler";

type RtdnPayload = {
  packageName?: string;
  subscriptionNotification?: {
    purchaseToken?: string;
    subscriptionId?: string;
  };
};

function providedSecret(req: VercelRequest): string {
  const header = req.headers["x-sabibom-rtdn-token"];
  if (typeof header === "string") return header;
  const query = req.query.token;
  return typeof query === "string" ? query : "";
}

export default createHandler(["POST"], async (req: VercelRequest, res: VercelResponse) => {
  const env = getEnv();
  if (!env.googlePlayRtdnToken || providedSecret(req) !== env.googlePlayRtdnToken) {
    throw errors.unauthenticated();
  }
  const body = readJsonBody(req) as {message?: {data?: unknown}};
  const encoded = body.message?.data;
  if (typeof encoded !== "string" || !encoded) throw errors.invalidArgument("Invalid RTDN message.");
  let payload: RtdnPayload;
  try {
    payload = JSON.parse(Buffer.from(encoded, "base64").toString("utf8")) as RtdnPayload;
  } catch {
    throw errors.invalidArgument("Invalid RTDN payload.");
  }
  const notification = payload.subscriptionNotification;
  const purchaseToken = notification?.purchaseToken?.trim();
  const productId = notification?.subscriptionId?.trim();
  if (payload.packageName !== env.googlePlayPackageName || !purchaseToken || !productId) {
    throw errors.invalidArgument("RTDN subscription details are invalid.");
  }
  const db = adminFirestore();
  const ledger = await db.collection("billing_purchase_tokens").doc(purchaseTokenHash(purchaseToken)).get();
  if (!ledger.exists) {
    sendSuccess(res, {ignored: true, reason: "unknown_purchase_token"});
    return;
  }
  const data = ledger.data() ?? {};
  await verifyAndPersistGooglePlaySubscription({
    db,
    businessId: String(data.businessId ?? ""),
    uid: String(data.userId ?? "google-play-rtdn"),
    productId,
    purchaseToken,
  });
  sendSuccess(res, {processed: true});
});
