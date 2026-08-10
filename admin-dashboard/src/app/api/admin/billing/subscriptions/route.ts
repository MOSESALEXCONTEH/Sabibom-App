import { withAdminRoute } from "@/lib/api/handler";
import { parseListQuery } from "@/lib/api/pagination";
import { listBusinessSubscriptions } from "@/lib/billing/repository";
import { serializeDates } from "@/lib/utils/serialize";

export const GET = withAdminRoute(
  { permission: "view_subscriptions" },
  async ({ request }) => {
    const query = parseListQuery(new URL(request.url).searchParams);
    return serializeDates(
      await listBusinessSubscriptions({
        limit: query.limit,
        cursor: query.cursor,
      }),
    );
  },
);
