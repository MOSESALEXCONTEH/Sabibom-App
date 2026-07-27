import type {VercelRequest, VercelResponse} from "@vercel/node";
import businessQuestion from "../src/http/sabi/business-question";
import composeMessage from "../src/http/sabi/compose-message";
import parseAction from "../src/http/sabi/parse-action";
import parseReceipt from "../src/http/sabi/parse-receipt";

type Handler = (req: VercelRequest, res: VercelResponse) => Promise<void>;

function actionKey(req: VercelRequest): string {
  const raw = req.query.action;
  if (typeof raw === "string" && raw.length > 0) return raw;
  if (Array.isArray(raw) && typeof raw[0] === "string") return raw[0];
  const url = req.url ?? "";
  const match = url.match(/\/api\/sabi\/([^/?#]+)/);
  return match?.[1] ?? "";
}

const routes: Record<string, Handler> = {
  "business-question": businessQuestion,
  "compose-message": composeMessage,
  "parse-action": parseAction,
  "parse-receipt": parseReceipt,
};

export default async function sabiRouter(
  req: VercelRequest,
  res: VercelResponse,
): Promise<void> {
  const key = actionKey(req);
  const handler = routes[key];
  if (!handler) {
    res.statusCode = 404;
    res.setHeader("content-type", "application/json");
    res.end(JSON.stringify({error: {message: `Unknown sabi route: ${key}`}}));
    return;
  }
  await handler(req, res);
}
