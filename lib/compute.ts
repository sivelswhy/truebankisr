// Pure "true balance" computation. No I/O, so it can be unit-tested and
// later reused as-is by the iPhone app.

export interface Txn {
  date: string; // purchase date (ISO)
  processedDate: string; // for card txns: the day it is debited from the bank (ISO)
  chargedAmount: number; // negative = expense
  chargedCurrency?: string;
  originalAmount?: number;
  originalCurrency?: string;
  description: string;
  status: 'completed' | 'pending';
  installments?: { number: number; total: number };
  category?: string; // Max category name (Hebrew), see lib/categories.ts
}

export interface Account {
  accountNumber: string;
  balance?: number;
  txns: Txn[];
}

export interface UpcomingCharge {
  chargeDate: string; // YYYY-MM-DD (Israel time)
  total: number; // positive amount in ILS that will leave the bank account
  txns: Txn[];
}

export interface TrueBalance {
  bankBalance: number;
  nextCharge: UpcomingCharge | null;
  // Bank balance minus the next card debit only.
  trueBalance: number;
  // Bank balance minus every card charge already known (incl. future installments).
  trueBalanceAllKnown: number;
  upcoming: UpcomingCharge[];
  // Card txns not in ILS: shown to the user but not subtracted.
  ignoredForeign: Txn[];
  computedAt: string;
}

const TZ = 'Asia/Jerusalem';

// YYYY-MM-DD of an instant, as seen in Israel.
export function israelDay(d: Date | string): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: TZ }).format(new Date(d));
}

// Next card billing day (e.g. the 2nd) strictly after `today`, or today itself
// if the debit has not reached the bank account yet.
function nextBillingDay(today: string, billingDay: number): string {
  const [y, m, d] = today.split('-').map(Number);
  const date = d <= billingDay ? new Date(Date.UTC(y, m - 1, billingDay)) : new Date(Date.UTC(y, m, billingDay));
  return date.toISOString().slice(0, 10);
}

// Leumi line for the monthly card debit, e.g. "מקס איט פיננ" / "MAX IT".
const CARD_DEBIT_PATTERN = /מקס|max|לאומי קארד|leumi card/i;

export function computeTrueBalance(
  bank: Account,
  cards: Account[],
  opts: { now?: Date; billingDay?: number } = {},
): TrueBalance {
  const now = opts.now ?? new Date();
  const billingDay = opts.billingDay ?? 2;
  const today = israelDay(now);

  if (bank.balance == null) throw new Error('Bank balance not available from the scraper');

  // If the bank already shows today's card debit, that cycle is in the balance.
  const debitedToday = bank.txns.some(
    (t) => israelDay(t.date) === today && t.chargedAmount < 0 && CARD_DEBIT_PATTERN.test(t.description),
  );

  const ignoredForeign: Txn[] = [];
  const byDay = new Map<string, Txn[]>();

  for (const txn of cards.flatMap((c) => c.txns).map(withPendingAmount)) {
    if (txn.chargedCurrency && txn.chargedCurrency !== 'ILS') {
      ignoredForeign.push(txn);
      continue;
    }
    // Pending txns have no payment date yet: they go to the next billing cycle.
    const day = txn.status === 'pending' ? nextBillingDay(today, billingDay) : israelDay(txn.processedDate);
    const notYetDebited = day > today || (day === today && !debitedToday);
    if (!notYetDebited) continue;
    if (!byDay.has(day)) byDay.set(day, []);
    byDay.get(day)!.push(txn);
  }

  const upcoming = [...byDay.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([chargeDate, txns]) => ({
      chargeDate,
      txns,
      total: round(-txns.reduce((sum, t) => sum + t.chargedAmount, 0)),
    }));

  const nextCharge = upcoming[0] ?? null;
  const allKnown = upcoming.reduce((sum, c) => sum + c.total, 0);

  return {
    bankBalance: bank.balance,
    nextCharge,
    trueBalance: round(bank.balance - (nextCharge?.total ?? 0)),
    trueBalanceAllKnown: round(bank.balance - allKnown),
    upcoming,
    ignoredForeign,
    computedAt: now.toISOString(),
  };
}

// Max reports pending purchases with a charged amount of 0 until they are
// processed; the real amount is the original one.
function withPendingAmount(txn: Txn): Txn {
  if (txn.status !== 'pending' || txn.chargedAmount !== 0 || !txn.originalAmount) return txn;
  return { ...txn, chargedAmount: txn.originalAmount, chargedCurrency: txn.originalCurrency ?? txn.chargedCurrency };
}

function round(n: number): number {
  return Math.round(n * 100) / 100;
}
