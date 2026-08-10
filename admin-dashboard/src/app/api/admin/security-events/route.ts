import { withAdminRoute } from "@/lib/api/handler";
import { parseListQuery } from "@/lib/api/pagination";
import {
  listSecurityEvents,
  toPublicSecurityEvent,
} from "@/lib/security/repository";
import { serializeDates } from "@/lib/utils/serialize";

export const GET = withAdminRoute(
  { permission: "view_security_logs" },
  async ({ request }) => {
    const url = new URL(request.url);
    const query = parseListQuery(url.searchParams);
    const category = url.searchParams.get("category") ?? undefined;
    const page = await listSecurityEvents({
      limit: query.limit,
      cursor: query.cursor,
      category,
    });
    return serializeDates({
      items: page.items.map(toPublicSecurityEvent),
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    });
  },
);
