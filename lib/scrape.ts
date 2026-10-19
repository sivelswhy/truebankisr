import path from 'node:path';
import { CompanyTypes, createScraper, type ScraperScrapingResult } from 'israeli-bank-scrapers';
import type { Account } from './compute.ts';
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

async function run(provider: Provider, credentials: Login, startDate: Date) {
  // On failure, keep what the site was showing so we can see why (data/ is git-ignored).
  const failureShot = path.join(process.cwd(), 'data', `debug-${provider}.png`);
  const scraper = createScraper({
    companyId: provider === 'leumi' ? CompanyTypes.leumi : CompanyTypes.max,
    startDate,
    combineInstallments: false,
    futureMonthsToScrape: 3, // future installments billed in the coming months
    showBrowser: process.env.SHOW_BROWSER === '1',
    storeFailureScreenShotPath: failureShot,
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
  return (result.accounts ?? []) as Account[];
}

// Logs into Leumi and Max in parallel.
export async function scrapeAll(leumi: Login, max: Login): Promise<{ bank: Account; cards: Account[] }> {
  const since = new Date();
  since.setMonth(since.getMonth() - 2);

  const [l, m] = await Promise.allSettled([run('leumi', leumi, since), run('max', max, since)]);
  if (l.status === 'rejected' || m.status === 'rejected') {
    const errorsOf = (r: PromiseSettledResult<unknown>) =>
      r.status === 'rejected' && r.reason instanceof ScrapeError ? r.reason.errors : {};
    throw new ScrapeError({ ...errorsOf(l), ...errorsOf(m) });
  }
  const bankAccounts = l.value;
  const cards = m.value;

  const wanted = process.env.LEUMI_ACCOUNT_NUMBER;
  const bank = wanted ? bankAccounts.find((a) => a.accountNumber.includes(wanted)) : bankAccounts.find((a) => a.balance != null);
  if (!bank) throw new ScrapeError({ leumi: 'NO_ACCOUNT' });
  return { bank, cards };
}
