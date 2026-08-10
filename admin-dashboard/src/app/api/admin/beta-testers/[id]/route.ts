import { withAdminRoute } from "@/lib/api/handler";
import { AdminHttpError } from "@/lib/auth/errors";
import {
  betaTesterPatchSchema,
  patchBetaTester,
  toPublicBetaTester,
} from "@/lib/beta/repository";
import { serializeDates } from "@/lib/utils/serialize";

export const PATCH = withAdminRoute(
  { permission: "manage_beta_testers" },
  async ({ request, ctx, requestId, params }) => {
    const id = params.id;
    if (!id) {
      throw new AdminHttpError(400, "Missing beta tester id.", "invalid_argument");
    }
    const patch = betaTesterPatchSchema.parse(await request.json());
    const updated = await patchBetaTester({
      id,
      patch,
      actorUid: ctx.uid,
      actorName: ctx.admin.displayName,
      actorRole: ctx.admin.role,
      requestId,
    });
    if (!updated) {
      throw new AdminHttpError(404, "Beta tester not found.", "not_found");
    }
    return serializeDates({ item: toPublicBetaTester(updated) });
  },
);
