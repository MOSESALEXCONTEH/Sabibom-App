import type {VercelRequest, VercelResponse} from "@vercel/node";
import businesses from "../src/http/sabi-training/businesses";
import overview from "../src/http/sabi-training/overview";
import preview from "../src/http/sabi-training/preview";
import save from "../src/http/sabi-training/save";
import status from "../src/http/sabi-training/status";

type Handler = (req: VercelRequest, res: VercelResponse) => Promise<void>;

const routes: Record<string, Handler> = {
  businesses,
  overview,
  preview,
  save,
  status,
};

export default async function sabiTrainingRouter(
  req: VercelRequest,
  res: VercelResponse,
): Promise<void> {
  const raw = req.query.action;
  const action =
    typeof raw === "string"
      ? raw
      : (req.url ?? "").match(/\/api\/sabi-training\/([^/?#]+)/)?.[1] ?? "";
  const handler = routes[action];
  if (!handler) {
    res.status(404).json({success: false, error: {message: "Unknown training route."}});
    return;
  }
  await handler(req, res);
}
