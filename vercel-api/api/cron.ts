import type {VercelRequest, VercelResponse} from "@vercel/node";
import dailySummaries from "../src/http/cron/daily-summaries";
import endOfDayReminders from "../src/http/cron/end-of-day-reminders";
import productExpiry from "../src/http/cron/product-expiry";

type Handler = (req: VercelRequest, res: VercelResponse) => Promise<void>;

function jobKey(req: VercelRequest): string {
  const raw = req.query.job;
  if (typeof raw === "string" && raw.length > 0) return raw;
  if (Array.isArray(raw) && typeof raw[0] === "string") return raw[0];
  const url = req.url ?? "";
  const match = url.match(/\/api\/cron\/([^/?#]+)/);
  return match?.[1] ?? "";
}

const routes: Record<string, Handler> = {
  "daily-summaries": dailySummaries,
  "end-of-day-reminders": endOfDayReminders,
  "product-expiry": productExpiry,
};

export default async function cronRouter(
  req: VercelRequest,
  res: VercelResponse,
): Promise<void> {
  const key = jobKey(req);
  const handler = routes[key];
  if (!handler) {
    res.statusCode = 404;
    res.setHeader("content-type", "application/json");
    res.end(JSON.stringify({error: {message: `Unknown cron job: ${key}`}}));
    return;
  }
  await handler(req, res);
}
