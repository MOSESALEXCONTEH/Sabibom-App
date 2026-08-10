import { withAdminRoute } from "@/lib/api/handler";
import { parseSearchQuery } from "@/lib/search/bounds";
import { globalAdminSearch } from "@/lib/search/repository";

export const GET = withAdminRoute({}, async ({ request }) => {
  const url = new URL(request.url);
  const { q, limit } = parseSearchQuery(url.searchParams);
  return globalAdminSearch({ q, limit });
});
