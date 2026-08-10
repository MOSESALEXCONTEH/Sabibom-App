import { withAdminRoute } from "@/lib/api/handler";
import {
  getReleaseReadiness,
  releaseAssessmentSchema,
  saveReleaseAssessment,
} from "@/lib/release-readiness/repository";
import { serializeDates } from "@/lib/utils/serialize";

export const GET = withAdminRoute(
  { permission: "view_release_readiness" },
  async () => serializeDates(await getReleaseReadiness()),
);

export const PATCH = withAdminRoute(
  { permission: "view_release_readiness" },
  async ({ request, ctx, requestId }) => {
    const assessment = releaseAssessmentSchema.parse(await request.json());
    const saved = await saveReleaseAssessment({
      assessment,
      actorUid: ctx.uid,
      actorName: ctx.admin.displayName,
      actorRole: ctx.admin.role,
      requestId,
    });
    return serializeDates(saved);
  },
);
