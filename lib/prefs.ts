import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import type { PurchaseNote } from './insights.ts';

// What the iPhone app keeps in its settings and on the device: kept here in
// data/prefs.json so it survives a browser's data being cleared.
export interface Prefs {
  firstName: string;
  hideAmounts: boolean;
  alertThreshold: number;
  budgets: Record<string, number>;
  notes: Record<string, PurchaseNote>;
}

export const DEFAULT_PREFS: Prefs = { firstName: '', hideAmounts: false, alertThreshold: 0, budgets: {}, notes: {} };

const FILE = path.join(process.cwd(), 'data', 'prefs.json');

export async function readPrefs(): Promise<Prefs> {
  try {
    return { ...DEFAULT_PREFS, ...JSON.parse(await readFile(FILE, 'utf8')) };
  } catch {
    return DEFAULT_PREFS;
  }
}

/** Only the known fields, with the right types. */
export function sanitize(input: unknown): Partial<Prefs> {
  const v = (input ?? {}) as Record<string, unknown>;
  const out: Partial<Prefs> = {};
  if (typeof v.firstName === 'string') out.firstName = v.firstName.slice(0, 40);
  if (typeof v.hideAmounts === 'boolean') out.hideAmounts = v.hideAmounts;
  if (typeof v.alertThreshold === 'number' && v.alertThreshold >= 0) out.alertThreshold = Math.min(v.alertThreshold, 1_000_000);
  if (v.budgets && typeof v.budgets === 'object') {
    out.budgets = Object.fromEntries(
      Object.entries(v.budgets as Record<string, unknown>).filter(([, n]) => typeof n === 'number' && n > 0) as [string, number][],
    );
  }
  if (v.notes && typeof v.notes === 'object') {
    out.notes = Object.fromEntries(
      Object.entries(v.notes as Record<string, PurchaseNote>)
        .filter(([, n]) => n && typeof n.text === 'string' && Array.isArray(n.tags))
        .map(([id, n]) => [id, { text: n.text.slice(0, 1000), tags: n.tags.filter((t) => typeof t === 'string').slice(0, 20) }])
        .filter(([, n]) => (n as PurchaseNote).text.trim() || (n as PurchaseNote).tags.length),
    );
  }
  return out;
}

// One write at a time, so quick edits (typing a budget) can't overwrite each other.
let queue: Promise<unknown> = Promise.resolve();

export function updatePrefs(patch: unknown): Promise<Prefs> {
  const run = async () => {
    const next = { ...(await readPrefs()), ...sanitize(patch) };
    await mkdir(path.dirname(FILE), { recursive: true, mode: 0o700 });
    await writeFile(FILE, JSON.stringify(next), { mode: 0o600 });
    return next;
  };
  const done = queue.then(run, run);
  queue = done.catch(() => {});
  return done;
}

export const clearPrefs = () => rm(FILE, { force: true });
