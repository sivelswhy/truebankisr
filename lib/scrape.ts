import path from 'node:path';
import { CompanyTypes, createScraper, type ScraperScrapingResult } from 'israeli-bank-scrapers';
import { categoryKey } from './categories.ts';
import { israelDay, type Account, type Txn } from './compute.ts';
import type { ErrorCode } from './i18n.ts';
import type { Login } from './vault.ts';

export type Provider = 'leumi' | 'max';

// Failed logins or scrapes, keyed by site so the UI can show each error next
// to the right fields.
export class ScrapeError extends Error {
  constructor(public errors: Partial<Record<Provider, ErrorCode>>) {
    super(Object.values(errors).join(' '));
  }
}

// Known scraper error types are passed through as codes; the UI words them.
function code(errorType?: string): ErrorCode {
  return errorType === 'INVALID_PASSWORD' || errorType === 'CHANGE_PASSWORD' || errorType === 'ACCOUNT_BLOCKED' || errorType === 'TIMEOUT'
    ? errorType
    : 'GENERIC';
}

type Transaction = NonNullable<ScraperScrapingResult['accounts']>[number]['txns'][number];

interface LeumiRaw {
  RunningBalance?: number;
  EffectiveDateUTC?: string;
  FITID?: string;
}

// The scraper's transaction → ours, with what the iPhone app keeps too.
function mapTxn(provider: Provider, account: string, t: Transaction, n: number): Txn {
  const raw = (provider === 'leumi' ? t.rawTransaction : undefined) as LeumiRaw | undefined;
  const valueDate = raw?.EffectiveDateUTC && israelDay(raw.EffectiveDateUTC) !== israelDay(t.date) ? raw.EffectiveDateUTC : undefined;
  const memo = t.memo?.trim();
  return {
    id: String(raw?.FITID || t.identifier || `${provider}-${t.date}-${t.chargedAmount}-${n}`),
    date: t.date,
    processedDate: t.processedDate,
    chargedAmount: t.chargedAmount,
    chargedCurrency: t.chargedCurrency ?? 'ILS',
    originalAmount: t.originalAmount,
    originalCurrency: t.originalCurrency,
    description: t.description.trim(),
    status: t.status === 'pending' ? 'pending' : 'completed',
    ...(t.installments ? { installments: { number: t.installments.number, total: t.installments.total } } : {}),
    ...(provider === 'max' ? { category: categoryKey(t.category), cardLast4: account.slice(-4) } : {}),
    ...(memo ? { memo } : {}),
    ...(typeof raw?.RunningBalance === 'number' ? { runningBalance: raw.RunningBalance } : {}),
    ...(valueDate ? { valueDate } : {}),
  };
}

async function run(provider: Provider, credentials: Login, startDate: Date): Promise<Account[]> {
  // On failure, keep what the site was showing so we can see why (data/ is git-ignored).
  const failureShot = path.join(process.cwd(), 'data', `debug-${provider}.png`);
  const scraper = createScraper({
    companyId: provider === 'leumi' ? CompanyTypes.leumi : CompanyTypes.max,
    startDate,
    combineInstallments: false,
    futureMonthsToScrape: 3, // future installments billed in the coming months
    showBrowser: process.env.SHOW_BROWSER === '1',
    storeFailureScreenShotPath: failureShot,
    includeRawTransaction: provider === 'leumi', // running balance and value date
  });
  let result: ScraperScrapingResult;
  try {
    result = await scraper.scrape(credentials);
  } catch (e) {
    console.error(`[${provider}] scraper crashed:`, e);
    const local = /Failed to launch the browser|Could not find Chrome/i.test((e as Error).message);
    throw new ScrapeError({ [provider]: local ? 'BROWSER' : 'GENERIC' });
  }
  if (!result.success) {
    console.error(`[${provider}] scrape failed:`, result.errorType, result.errorMessage, `(screenshot: ${failureShot})`);
    throw new ScrapeError({ [provider]: code(result.errorType) });
  }
  return (result.accounts ?? []).map((a) => ({
    accountNumber: a.accountNumber,
    balance: a.balance,
    txns: a.txns.map((t, n) => mapTxn(provider, a.accountNumber, t, n)),
  }));
}

/**
 * Logs into Leumi and Max in parallel. Max goes back `maxMonths` (a year the
 * first time, then only the recent months: older purchases are cached).
 */
export async function scrapeAll(leumi: Login, max: Login, maxMonths: number): Promise<{ bank: Account; cards: Account[]; maxSince: Date }> {
  const months = (n: number) => {
    const d = new Date();
    d.setMonth(d.getMonth() - n, 1);
    d.setHours(0, 0, 0, 0);
    return d;
  };
  const maxSince = months(maxMonths);

  const [l, m] = await Promise.allSettled([run('leumi', leumi, months(2)), run('max', max, maxSince)]);
  if (l.status === 'rejected' || m.status === 'rejected') {
    const errorsOf = (r: PromiseSettledResult<unknown>) =>
      r.status === 'rejected' && r.reason instanceof ScrapeError ? r.reason.errors : {};
    throw new ScrapeError({ ...errorsOf(l), ...errorsOf(m) });
  }

  const wanted = process.env.LEUMI_ACCOUNT_NUMBER;
  const bank = wanted ? l.value.find((a) => a.accountNumber.includes(wanted)) : l.value.find((a) => a.balance != null);
  if (!bank) throw new ScrapeError({ leumi: 'NO_ACCOUNT' });
  return { bank, cards: m.value, maxSince };
}

/** Shekels per unit of each currency (Bank of Israel), or {} when offline. */
export async function boiRates(): Promise<Record<string, number>> {
  try {
    const res = await fetch('https://boi.org.il/PublicApi/GetExchangeRates', { signal: AbortSignal.timeout(8000) });
    const json = (await res.json()) as { exchangeRates?: { key: string; currentExchangeRate: number; unit?: number }[] };
    return Object.fromEntries((json.exchangeRates ?? []).map((r) => [r.key, r.currentExchangeRate / (r.unit || 1)]));
  } catch {
    return {};
  }
}
