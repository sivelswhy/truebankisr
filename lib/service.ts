import { readFile, rm, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { computeTrueBalance, israelDay, type TrueBalance, type Txn } from './compute.ts';
import { DEMO_EXTRAS, demoData } from './demo.ts';
import { mergeHistory } from './insights.ts';
import { boiRates, scrapeAll, ScrapeError } from './scrape.ts';
import type { Session } from './vault.ts';

export type Snapshot = TrueBalance & { demo: boolean };

const DIR = path.join(process.cwd(), 'data');
const SNAPSHOT = path.join(DIR, 'snapshot.json');
// Card purchases kept across refreshes, so history grows beyond what one refresh downloads.
const HISTORY = path.join(DIR, 'history.json');

let inFlight: Promise<Snapshot> | null = null;

// One scrape at a time: a second tap or pull joins the running one.
export function refresh(session: Session): Promise<Snapshot> {
  inFlight ??= run(session).finally(() => (inFlight = null));
  return inFlight;
}

async function readJSON<T>(file: string): Promise<T | null> {
  try {
    return JSON.parse(await readFile(file, 'utf8'));
  } catch {
    return null;
  }
}

async function writeJSON(file: string, value: unknown): Promise<void> {
  await mkdir(DIR, { recursive: true, mode: 0o700 });
  await writeFile(file, JSON.stringify(value), { mode: 0o600 });
}

async function run(session: Session): Promise<Snapshot> {
  const billingDay = Number(process.env.BILLING_DAY ?? 2);
  if (session.mode === 'demo') {
    const { bank, cards } = demoData();
    const { fxRates, ...extras } = DEMO_EXTRAS;
    const snapshot = { demo: true, ...computeTrueBalance(bank, cards, { billingDay, fxRates }), ...extras };
    await writeJSON(SNAPSHOT, snapshot);
    return snapshot;
  }

  // A year of purchases the first time, then only the recent months.
  const cached = await readJSON<Txn[]>(HISTORY);
  const [{ bank, cards, maxSince }, fxRates] = await Promise.all([
    scrapeAll(session.leumi, session.max, cached?.length ? 2 : 12),
    boiRates(),
  ]);
  const history = mergeHistory(cached ?? [], cards.flatMap((c) => c.txns), israelDay(maxSince));
  await writeJSON(HISTORY, history);

  const snapshot = { demo: false, ...computeTrueBalance(bank, cards, { billingDay, fxRates, history }) };
  await writeJSON(SNAPSHOT, snapshot);
  return snapshot;
}

// A snapshot saved by an older version (no history yet) is treated as none,
// so the app refreshes instead of showing half the screens empty.
export async function readSnapshot(): Promise<Snapshot | null> {
  const s = await readJSON<Snapshot>(SNAPSHOT);
  return s && Array.isArray(s.history) && Array.isArray(s.bankTxns) ? s : null;
}

export async function clearSnapshot(): Promise<void> {
  await Promise.all([rm(SNAPSHOT, { force: true }), rm(HISTORY, { force: true })]);
}

export function errorResponse(e: unknown): Response {
  if (e instanceof ScrapeError) return Response.json({ errors: e.errors }, { status: 422 });
  console.error(e);
  return Response.json({ errors: { general: 'UNKNOWN' } }, { status: 500 });
}
