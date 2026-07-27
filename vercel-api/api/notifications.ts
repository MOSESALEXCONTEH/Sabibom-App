import type {VercelRequest, VercelResponse} from "@vercel/node";
import registerDevice from "../src/http/notifications/register-device";
import sendTest from "../src/http/notifications/send-test";
import unregisterDevice from "../src/http/notifications/unregister-device";

type Handler = (req: VercelRequest, res: VercelResponse) => Promise<void>;

function actionKey(req: VercelRequest): string {
  const raw = req.query.action;
  if (typeof raw === "string" && raw.length > 0) return raw;
  if (Array.isArray(raw) && typeof raw[0] === "string") return raw[0];
  const url = req.url ?? "";
  const match = url.match(/\/api\/notifications\/([^/?#]+)/);
  return match?.[1] ?? "";
}

const routes: Record<string, Handler> = {
  "register-device": registerDevice,
  "unregister-device": unregisterDevice,
  "send-test": sendTest,
};

export default async function notificationsRouter(
  req: VercelRequest,
  res: VercelResponse,
): Promise<void> {
  const key = actionKey(req);
  const handler = routes[key];
  if (!handler) {
    res.statusCode = 404;
    res.setHeader("content-type", "application/json");
    res.end(
      JSON.stringify({error: {message: `Unknown notifications route: ${key}`}}),
    );
    return;
  }
  await handler(req, res);
}
