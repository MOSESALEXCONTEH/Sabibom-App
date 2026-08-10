import { withAdminRoute } from "@/lib/api/handler";
import { parseListQuery } from "@/lib/api/pagination";
import { listBillingEvents } from "@/lib/billing/repository";
import { serializeDates } from "@/lib/utils/serialize";

export const GET = withAdminRoute(
  { permission: "view_billing_events" },
  async ({ request }) => {
    const query = parseListQuery(new URL(request.url).searchParams);
    return serializeDates(
      await listBillingEvents({
        limit: query.limit,
        cursor: query.cursor,
      }),
    );
  },
);
