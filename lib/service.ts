import { readFile, rm, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { computeTrueBalance, type TrueBalance } from './compute.ts';
import { demoData } from './demo.ts';
import { scrapeAll, ScrapeError } from './scrape.ts';
import type { Session } from './vault.ts';

export type Snapshot = TrueBalance & { demo: boolean };

const SNAPSHOT = path.join(process.cwd(), 'data', 'snapshot.json');

let inFlight: Promise<Snapshot> | null = null;

// One scrape at a time: a second tap or pull joins the running one.
export function refresh(session: Session): Promise<Snapshot> {
  inFlight ??= run(session).finally(() => (inFlight = null));
  return inFlight;
}

async function run(session: Session): Promise<Snapshot> {
  const demo = session.mode === 'demo';
  const { bank, cards } = demo ? demoData() : await scrapeAll(session.leumi, session.max);
  const snapshot = { demo, ...computeTrueBalance(bank, cards, { billingDay: Number(process.env.BILLING_DAY ?? 2) }) };
  await mkdir(path.dirname(SNAPSHOT), { recursive: true, mode: 0o700 });
  await writeFile(SNAPSHOT, JSON.stringify(snapshot, null, 2), { mode: 0o600 });
  return snapshot;
}

export async function readSnapshot(): Promise<Snapshot | null> {
  try {
    return JSON.parse(await readFile(SNAPSHOT, 'utf8'));
  } catch {
    return null;
  }
}

export async function clearSnapshot(): Promise<void> {
  await rm(SNAPSHOT, { force: true });
}

export function errorResponse(e: unknown): Response {
  if (e instanceof ScrapeError) return Response.json({ errors: e.errors }, { status: 422 });
  console.error(e);
  return Response.json({ errors: { general: 'UNKNOWN' } }, { status: 500 });
}
