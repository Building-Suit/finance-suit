export type CatalogSummary = {
  activeProducts: number;
  marketVariants: number;
  countries: number;
  dueOrStale: number;
  queued: number;
  leased: number;
  failed: number;
};

const numberValue = (value: unknown) =>
  typeof value === "number" && Number.isFinite(value) ? value : 0;

export function normalizeCatalogSummary(
  raw: Record<string, unknown> | null | undefined,
): CatalogSummary {
  return {
    activeProducts: numberValue(raw?.canonicalProducts ?? raw?.activeProducts),
    marketVariants: numberValue(raw?.productMarketVariants),
    countries: numberValue(raw?.countriesCovered ?? raw?.countries),
    dueOrStale: numberValue(raw?.staleWork ?? raw?.staleProducts),
    queued: numberValue(raw?.queuedWork ?? raw?.queued),
    leased: numberValue(raw?.leasedWork ?? raw?.leased),
    failed: numberValue(raw?.failedWork ?? raw?.failed),
  };
}
