import type {VercelRequest, VercelResponse} from "@vercel/node";
import disposeBatch from "../src/http/inventory/batches/dispose";
import createProduct from "../src/http/inventory/products/create";
import completePurchase from "../src/http/inventory/purchases/complete";
import completeSale from "../src/http/inventory/sales/complete";
import voidSale from "../src/http/inventory/sales/void";
import stockIn from "../src/http/inventory/stock-in";

type Handler = (req: VercelRequest, res: VercelResponse) => Promise<void>;

function routeKey(req: VercelRequest): string {
  const q = req.query;
  const fromQuery = [q.p1, q.p2, q.p3]
    .flatMap((v) => (Array.isArray(v) ? v : v ? [v] : []))
    .filter((v): v is string => typeof v === "string" && v.length > 0);
  if (fromQuery.length > 0) return fromQuery.join("/");

  const url = req.url ?? "";
  const match = url.match(/\/api\/inventory\/?([^?]*)/);
  return (match?.[1] ?? "").replace(/\/+$/, "");
}

const routes: Record<string, Handler> = {
  "sales/complete": completeSale,
  "sales/void": voidSale,
  "purchases/complete": completePurchase,
  "products/create": createProduct,
  "stock-in": stockIn,
  "batches/dispose": disposeBatch,
};

export default async function inventoryRouter(
  req: VercelRequest,
  res: VercelResponse,
): Promise<void> {
  const key = routeKey(req);
  const handler = routes[key];
  if (!handler) {
    res.statusCode = 404;
    res.setHeader("content-type", "application/json");
    res.end(
      JSON.stringify({error: {message: `Unknown inventory route: ${key}`}}),
    );
    return;
  }
  await handler(req, res);
}
