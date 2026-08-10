import { withAdminRoute } from "@/lib/api/handler";
import { AdminHttpError } from "@/lib/auth/errors";
import { patchSubscriptionPlan } from "@/lib/billing/repository";
import { subscriptionPlanPatchSchema } from "@/lib/billing/schemas";
import { serializeDates } from "@/lib/utils/serialize";

export const PATCH = withAdminRoute(
  { permission: "manage_subscription_plans" },
  async ({ request, ctx, requestId, params }) => {
    const id = params.id;
    if (!id) {
      throw new AdminHttpError(400, "Missing plan id.", "invalid_argument");
    }
    const patch = subscriptionPlanPatchSchema.parse(await request.json());
    const updated = await patchSubscriptionPlan({
      id,
      patch,
      actorUid: ctx.uid,
      actorName: ctx.admin.displayName,
      actorRole: ctx.admin.role,
      requestId,
    });
    if (!updated) {
      throw new AdminHttpError(404, "Plan not found.", "not_found");
    }
    return serializeDates({ item: updated });
  },
);
