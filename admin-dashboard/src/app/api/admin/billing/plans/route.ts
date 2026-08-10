import { withAdminRoute } from "@/lib/api/handler";
import { parseListQuery } from "@/lib/api/pagination";
import {
  createSubscriptionPlan,
  listSubscriptionPlans,
} from "@/lib/billing/repository";
import { subscriptionPlanCreateSchema } from "@/lib/billing/schemas";
import { serializeDates } from "@/lib/utils/serialize";

export const GET = withAdminRoute(
  { permission: "manage_subscription_plans" },
  async ({ request }) => {
    const query = parseListQuery(new URL(request.url).searchParams);
    const page = await listSubscriptionPlans({
      limit: query.limit,
      cursor: query.cursor,
    });
    return serializeDates(page);
  },
);

export const POST = withAdminRoute(
  { permission: "manage_subscription_plans" },
  async ({ request, ctx, requestId }) => {
    const plan = subscriptionPlanCreateSchema.parse(await request.json());
    const created = await createSubscriptionPlan({
      plan,
      actorUid: ctx.uid,
      actorName: ctx.admin.displayName,
      actorRole: ctx.admin.role,
      requestId,
    });
    return serializeDates({ item: created });
  },
);
