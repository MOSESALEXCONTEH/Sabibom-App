import type {VercelRequest, VercelResponse} from "@vercel/node";
import invite from "../src/http/team/invite";
import memberStatus from "../src/http/team/member-status";

type Handler = (req: VercelRequest, res: VercelResponse) => Promise<void>;

function actionKey(req: VercelRequest): string {
  const raw = req.query.action;
  if (typeof raw === "string" && raw.length > 0) return raw;
  if (Array.isArray(raw) && typeof raw[0] === "string") return raw[0];
  const url = req.url ?? "";
  const match = url.match(/\/api\/team\/([^/?#]+)/);
  return match?.[1] ?? "";
}

const routes: Record<string, Handler> = {
  invite,
  "member-status": memberStatus,
};

export default async function teamRouter(
  req: VercelRequest,
  res: VercelResponse,
): Promise<void> {
  const key = actionKey(req);
  const handler = routes[key];
  if (!handler) {
    res.statusCode = 404;
    res.setHeader("content-type", "application/json");
    res.end(JSON.stringify({error: {message: `Unknown team route: ${key}`}}));
    return;
  }
  await handler(req, res);
}
