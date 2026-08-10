import { withAdminRoute } from "@/lib/api/handler";
import { parseListQuery } from "@/lib/api/pagination";
import {
  betaTesterCreateSchema,
  createBetaTester,
  listBetaTesters,
  toPublicBetaTester,
} from "@/lib/beta/repository";
import { serializeDates } from "@/lib/utils/serialize";

export const GET = withAdminRoute(
  { permission: "manage_beta_testers" },
  async ({ request }) => {
    const url = new URL(request.url);
    const query = parseListQuery(url.searchParams);
    const status = url.searchParams.get("status") ?? undefined;
    const page = await listBetaTesters({
      limit: query.limit,
      cursor: query.cursor,
      status,
    });
    return serializeDates({
      items: page.items.map(toPublicBetaTester),
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    });
  },
);

export const POST = withAdminRoute(
  { permission: "manage_beta_testers" },
  async ({ request, ctx, requestId }) => {
    const body = betaTesterCreateSchema.parse(await request.json());
    const created = await createBetaTester({
      email: body.email,
      displayName: body.displayName,
      uid: body.uid,
      platform: body.platform,
      notes: body.notes,
      actorUid: ctx.uid,
      actorName: ctx.admin.displayName,
      actorRole: ctx.admin.role,
      requestId,
    });
    return serializeDates({ item: toPublicBetaTester(created) });
  },
);
