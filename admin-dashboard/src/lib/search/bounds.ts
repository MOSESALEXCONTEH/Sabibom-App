import { z } from "zod";

/** Shared bounds for global admin search — keep queries cheap and safe. */
export const SEARCH_QUERY_MIN = 2;
export const SEARCH_QUERY_MAX = 100;
export const SEARCH_PER_COLLECTION_LIMIT = 10;

export const searchQuerySchema = z.object({
  q: z
    .string()
    .trim()
    .min(SEARCH_QUERY_MIN, `Query must be at least ${SEARCH_QUERY_MIN} characters.`)
    .max(SEARCH_QUERY_MAX, `Query must be at most ${SEARCH_QUERY_MAX} characters.`),
  limit: z.coerce
    .number()
    .int()
    .min(1)
    .max(SEARCH_PER_COLLECTION_LIMIT)
    .default(SEARCH_PER_COLLECTION_LIMIT),
});

export type SearchQueryInput = z.infer<typeof searchQuerySchema>;

export function parseSearchQuery(searchParams: URLSearchParams): SearchQueryInput {
  return searchQuerySchema.parse({
    q: searchParams.get("q") ?? "",
    limit: searchParams.get("limit") ?? undefined,
  });
}

export function clampSearchLimit(limit: number | undefined): number {
  if (!Number.isFinite(limit)) return SEARCH_PER_COLLECTION_LIMIT;
  return Math.min(
    Math.max(Math.floor(limit as number), 1),
    SEARCH_PER_COLLECTION_LIMIT,
  );
}
