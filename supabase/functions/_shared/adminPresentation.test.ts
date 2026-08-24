import { assertEquals } from "jsr:@std/assert@1";
import { normalizeCatalogSummary } from "./adminPresentation.ts";

Deno.test("catalog summary maps the live v2 contract", () => {
  assertEquals(
    normalizeCatalogSummary({
      canonicalProducts: 10,
      productMarketVariants: 12,
      countriesCovered: 2,
      staleWork: 3,
      queuedWork: 4,
      leasedWork: 1,
      failedWork: 2,
    }),
    {
      activeProducts: 10,
      marketVariants: 12,
      countries: 2,
      dueOrStale: 3,
      queued: 4,
      leased: 1,
      failed: 2,
    },
  );
});

Deno.test("catalog summary safely defaults missing counters", () => {
  assertEquals(normalizeCatalogSummary(null), {
    activeProducts: 0,
    marketVariants: 0,
    countries: 0,
    dueOrStale: 0,
    queued: 0,
    leased: 0,
    failed: 0,
  });
});
