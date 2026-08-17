import type {VercelRequest, VercelResponse} from "@vercel/node";
import googlePlayRtdn from "../src/http/billing/google-play-rtdn";
import verifyGooglePlay from "../src/http/billing/verify-google-play";

type Handler = (req: VercelRequest, res: VercelResponse) => Promise<void>;

function actionKey(req: VercelRequest): string {
  const raw = req.query.action;
  if (typeof raw === "string" && raw.length > 0) return raw;
  if (Array.isArray(raw) && typeof raw[0] === "string") return raw[0];
  return req.url?.match(/\/api\/billing\/([^/?#]+)/)?.[1] ?? "";
}

const routes: Record<string, Handler> = {
  "verify-google-play": verifyGooglePlay,
  "google-play-rtdn": googlePlayRtdn,
};

export default async function billingRouter(req: VercelRequest, res: VercelResponse): Promise<void> {
  const handler = routes[actionKey(req)];
  if (!handler) {
    res.status(404).json({success: false, error: {code: "not_found", message: "Unknown billing route."}});
    return;
  }
  await handler(req, res);
}
