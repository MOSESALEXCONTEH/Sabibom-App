import type {VercelRequest, VercelResponse} from "@vercel/node";
import decide from "../src/http/approvals/decide";

type Handler = (req: VercelRequest, res: VercelResponse) => Promise<void>;

function actionKey(req: VercelRequest): string {
  const raw = req.query.action;
  if (typeof raw === "string" && raw.length > 0) return raw;
  if (Array.isArray(raw) && typeof raw[0] === "string") return raw[0];
  const url = req.url ?? "";
  const match = url.match(/\/api\/approvals\/([^/?#]+)/);
  return match?.[1] ?? "";
}

const routes: Record<string, Handler> = {
  decide,
};

export default async function approvalsRouter(
  req: VercelRequest,
  res: VercelResponse,
): Promise<void> {
  const key = actionKey(req);
  const handler = routes[key];
  if (!handler) {
    res.statusCode = 404;
    res.setHeader("content-type", "application/json");
    res.end(
      JSON.stringify({error: {message: `Unknown approvals route: ${key}`}}),
    );
    return;
  }
  await handler(req, res);
}
