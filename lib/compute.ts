// Pure "true balance" computation. No I/O, so it can be unit-tested.
// Same rules as `TrueBalance.compute` in the iPhone app's TrueBalanceCore.

export interface Txn {
  id: string;
  date: string; // purchase date (ISO)
  processedDate: string; // for card txns: the day it is debited from the bank (ISO)
  chargedAmount: number; // negative = expense
  chargedCurrency?: string;
  // For a foreign-currency charge converted to ILS: the original amount and currency.
  originalAmount?: number;
  originalCurrency?: string;
  description: string;
  status: 'completed' | 'pending';
  installments?: { number: number; total: number };
  category?: string; // key from lib/categories.ts
  cardLast4?: string;
  // Bank movements: Leumi's detail line, the balance right after it, and the
  // value date when it differs.
  memo?: string;
  runningBalance?: number;
  valueDate?: string;
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
  // When credits (refunds, money sent to the card) outweigh the charges, Max
  // debits nothing and keeps what it owes for the next statement.
  credit?: number;
}

export interface TrueBalance {
  bankBalance: number;
  nextCharge: UpcomingCharge | null;
  // Bank balance minus the next card debit only.
  trueBalance: number;
  // Bank balance minus every card charge already known (incl. future installments).
  trueBalanceAllKnown: number;
  upcoming: UpcomingCharge[];
  // Card txns not in ILS with no known rate: shown but not subtracted.
  ignoredForeign: Txn[];
  computedAt: string;
  // Every card purchase fetched (debited or not), newest first.
  history: Txn[];
  // Leumi current-account movements, newest first.
  bankTxns: Txn[];
  // Shekels per unit (Bank of Israel), used for the conversions above.
  fxRates?: Record<string, number>;
  // Savings and foreign-currency accounts, when known (net worth).
  savings?: { name: string; balance: number }[];
  foreignAccounts?: { currency: string; balance: number }[];
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

export const isCardDebit = (t: Txn) => t.chargedAmount < 0 && CARD_DEBIT_PATTERN.test(t.description);

export function computeTrueBalance(
  bank: Account,
  cards: Account[],
  opts: { now?: Date; billingDay?: number; fxRates?: Record<string, number>; history?: Txn[] } = {},
): TrueBalance {
  const now = opts.now ?? new Date();
  const billingDay = opts.billingDay ?? 2;
  const rates = opts.fxRates ?? {};
  const today = israelDay(now);

  if (bank.balance == null) throw new Error('Bank balance not available from the scraper');

  // If the bank already shows today's card debit, that cycle is in the balance.
  const debitedToday = bank.txns.some((t) => israelDay(t.date) === today && isCardDebit(t));

  // Foreign charges with a known rate become ILS estimates everywhere.
  const convert = (t: Txn) => {
    const c = withPendingAmount(t);
    const rate = c.chargedCurrency && c.chargedCurrency !== 'ILS' ? rates[c.chargedCurrency] : undefined;
    return rate ? converted(c, rate) : c;
  };
  const all = cards.flatMap((c) => c.txns).map(convert);

  const ignoredForeign: Txn[] = [];
  const byDay = new Map<string, Txn[]>();
  for (const txn of all) {
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

  let carried = 0;
  const upcoming = [...byDay.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([chargeDate, txns]): UpcomingCharge => {
      const net = round(-txns.reduce((sum, t) => sum + t.chargedAmount, 0) - carried);
      carried = Math.max(0, -net);
      return { chargeDate, txns: txns.sort(newestFirst), total: Math.max(0, net), ...(carried ? { credit: carried } : {}) };
    });

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
    history: (opts.history ?? all).map(convert).sort(newestFirst),
    bankTxns: [...bank.txns].sort(newestFirst),
    ...(Object.keys(rates).length ? { fxRates: rates } : {}),
  };
}

export const newestFirst = (a: Txn, b: Txn) => b.date.localeCompare(a.date);

// Max reports pending purchases with a charged amount of 0 until they are
// processed; the real amount is the original one.
function withPendingAmount(txn: Txn): Txn {
  if (txn.status !== 'pending' || txn.chargedAmount !== 0 || !txn.originalAmount) return txn;
  return { ...txn, chargedAmount: txn.originalAmount, chargedCurrency: txn.originalCurrency ?? txn.chargedCurrency };
}

// ILS estimate of a foreign-currency charge, keeping the original amount.
function converted(t: Txn, rate: number): Txn {
  return { ...t, originalAmount: t.chargedAmount, originalCurrency: t.chargedCurrency, chargedAmount: round(t.chargedAmount * rate), chargedCurrency: 'ILS' };
}

export function round(n: number): number {
  return Math.round(n * 100) / 100;
}

/** Whole days from today (Israel) to a YYYY-MM-DD day; 0 on the day itself. */
export function daysUntil(day: string, now = new Date()): number {
  const ms = Date.parse(`${day}T00:00:00Z`) - Date.parse(`${israelDay(now)}T00:00:00Z`);
  return Math.max(0, Math.round(ms / 86_400_000));
}

/** What can be spent per day until the next debit without going below zero once it's taken. */
export function dailyBudget(s: TrueBalance, now = new Date()): number | null {
  if (!s.nextCharge || s.trueBalance <= 0) return null;
  const days = daysUntil(s.nextCharge.chargeDate, now);
  return days > 0 ? round(s.trueBalance / days) : null;
}
