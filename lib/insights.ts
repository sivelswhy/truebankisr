// Spending, recurring money, budgets and bank movements. Ports of Spending.swift
// and Insights.swift in TrueBalanceCore, so both apps find the same things.
import { UNCATEGORIZED } from './categories.ts';
import { israelDay, isCardDebit, newestFirst, round, type TrueBalance, type Txn } from './compute.ts';

// ---------- Days (YYYY-MM-DD, Israel time) ----------

export function addDays(day: string, n: number): string {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

export function addMonths(day: string, n: number): string {
  const [y, m, d] = day.split('-').map(Number);
  const last = new Date(Date.UTC(y, m - 1 + n + 1, 0)).getUTCDate();
  return new Date(Date.UTC(y, m - 1 + n, Math.min(d, last))).toISOString().slice(0, 10);
}

export const monthStart = (day: string) => `${day.slice(0, 7)}-01`;

// ---------- Spending ----------

export const merchantKey = (t: Txn) => t.description.trim().toLowerCase();

/**
 * Purchases made between two days (inclusive, Israel time), in ILS. Later
 * installments share the purchase date: only the first one counts. Money sent
 * to the card (e.g. from Revolut) is a transfer, not a refund of spending.
 */
export function purchases(txns: Txn[], from: string, to: string): Txn[] {
  return txns.filter((t) => {
    const day = israelDay(t.date);
    return (t.chargedCurrency ?? 'ILS') === 'ILS' && day >= from && day <= to && (t.installments?.number ?? 1) <= 1 && !isTransferToCard(t);
  });
}

export const isTransferToCard = (t: Txn) => t.chargedAmount > 0 && t.category === 'transfer';

export const total = (txns: Txn[]) => round(txns.reduce((s, t) => s - t.chargedAmount, 0));

/** Totals per day or month, oldest first, empty ones included. */
export function buckets(txns: Txn[], from: string, to: string, unit: 'day' | 'month'): { start: string; total: number }[] {
  const floor = (day: string) => (unit === 'month' ? monthStart(day) : day);
  const totals = new Map<string, number>();
  for (const t of txns) {
    const k = floor(israelDay(t.date));
    totals.set(k, (totals.get(k) ?? 0) - t.chargedAmount);
  }
  const out = [];
  for (let c = floor(from); c <= floor(to); c = unit === 'month' ? addMonths(c, 1) : addDays(c, 1)) {
    out.push({ start: c, total: round(totals.get(c) ?? 0) });
  }
  return out;
}

/** Everything bought from the same merchant, newest first. */
export const atMerchant = (key: string, txns: Txn[]) => txns.filter((t) => merchantKey(t) === key).sort(newestFirst);

/** One row per purchase: later installments of the same purchase are left out. */
export const onePerPurchase = (txns: Txn[]) => txns.filter((t) => (t.installments?.number ?? 1) <= 1).sort(newestFirst);

/**
 * Past purchases kept on disk so history grows beyond one refresh: cached
 * purchases made before `refetchedFrom`, plus everything just fetched (which
 * replaces the cached copy of those months). Newest first.
 */
export function mergeHistory(cached: Txn[], fresh: Txn[], refetchedFrom: string): Txn[] {
  const seen = new Set<string>();
  return [...fresh, ...cached.filter((t) => israelDay(t.date) < refetchedFrom)]
    .filter((t) => !seen.has(t.id) && (seen.add(t.id), true))
    .sort(newestFirst);
}

// ---------- Recurring money: salary, standing orders, subscriptions ----------

export interface Recurring {
  name: string;
  amount: number; // typical amount, signed (positive = money in)
  lastDate: string;
  nextDate: string; // YYYY-MM-DD, one month after the last one
  occurrences: number;
  category?: string;
}

/**
 * Same counterparty, in at least `minMonths` different months, with amounts
 * within `tolerance` of each other: salary, rent, subscriptions…
 */
export function detectRecurring(txns: Txn[], { minMonths = 2, tolerance = 0.25, now = new Date() } = {}): Recurring[] {
  const groups = new Map<string, Txn[]>();
  for (const t of txns) {
    if ((t.chargedCurrency ?? 'ILS') !== 'ILS' || t.chargedAmount === 0 || t.installments) continue;
    const k = `${merchantKey(t)}|${t.chargedAmount > 0}`;
    groups.set(k, [...(groups.get(k) ?? []), t]);
  }
  const staleLimit = addDays(israelDay(now), -62);
  const out: Recurring[] = [];
  for (const items of groups.values()) {
    const sorted = [...items].sort((a, b) => a.date.localeCompare(b.date));
    const months = new Set(sorted.map((t) => israelDay(t.date).slice(0, 7)));
    if (months.size < minMonths || months.size < sorted.length - 1) continue; // about once a month
    const amounts = sorted.map((t) => t.chargedAmount);
    const mean = amounts.reduce((a, b) => a + b, 0) / amounts.length;
    if (!amounts.every((a) => Math.abs(a - mean) <= Math.abs(mean) * tolerance)) continue;
    const last = sorted[sorted.length - 1];
    // Stale: nothing for two months means it stopped.
    if (israelDay(last.date) < staleLimit) continue;
    const recent = amounts.slice(-2);
    out.push({
      name: last.description.trim(),
      amount: round(recent.reduce((a, b) => a + b, 0) / recent.length),
      lastDate: last.date,
      nextDate: addMonths(israelDay(last.date), 1),
      occurrences: sorted.length,
      category: last.category,
    });
  }
  return out.sort((a, b) => Math.abs(b.amount) - Math.abs(a.amount));
}

/** Card charges that come back every month at about the same amount. Installment plans don't count. */
export const subscriptions = (history: Txn[], now = new Date()) =>
  detectRecurring(history, { minMonths: 2, tolerance: 0.1, now }).filter((r) => r.amount < 0);

export const monthlyTotal = (subs: Recurring[]) => round(-subs.reduce((s, r) => s + r.amount, 0));

export interface Forecast {
  projectedBalance: number;
  income: Recurring[];
  debits: Recurring[];
  until: string;
}

/** What the account should hold right after the next card debit, counting recurring bank movements expected before then. */
export function forecast(s: TrueBalance, now = new Date()): Forecast | null {
  if (!s.nextCharge) return null;
  const today = israelDay(now);
  const recurring = detectRecurring(s.bankTxns.filter((t) => !isCardDebit(t)), { now });
  const due = recurring.filter((r) => r.nextDate >= today && r.nextDate <= s.nextCharge!.chargeDate);
  return {
    projectedBalance: round(s.trueBalance + due.reduce((sum, r) => sum + r.amount, 0)),
    income: due.filter((r) => r.amount > 0),
    debits: due.filter((r) => r.amount < 0),
    until: s.nextCharge.chargeDate,
  };
}

// ---------- Budgets and comparisons ----------

export interface BudgetProgress {
  category: string;
  limit: number;
  spent: number;
  ratio: number;
}

/** Card spending this calendar month (Israel) per budgeted category. */
export function budgetProgress(limits: Record<string, number>, history: Txn[], now = new Date()): BudgetProgress[] {
  const today = israelDay(now);
  const month = purchases(history, monthStart(today), today);
  return Object.entries(limits)
    .filter(([, limit]) => limit > 0)
    .map(([category, limit]) => {
      const spent = total(month.filter((t) => (t.category ?? UNCATEGORIZED) === category));
      return { category, limit, spent, ratio: spent / limit };
    })
    .sort((a, b) => b.ratio - a.ratio);
}

export interface MonthComparison {
  thisMonth: number;
  lastMonthSamePeriod: number; // last month over the same number of days
  lastMonthTotal: number;
  byCategory: Record<string, number>; // this month minus last month (same period)
  change: number | null;
}

export function compareMonths(history: Txn[], now = new Date()): MonthComparison {
  const today = israelDay(now);
  const thisStart = monthStart(today);
  const lastStart = addMonths(thisStart, -1);
  const lastEnd = addDays(thisStart, -1);
  const elapsed = Number(today.slice(8)) - 1;
  const sameEnd = addDays(lastStart, elapsed) < lastEnd ? addDays(lastStart, elapsed) : lastEnd;
  const thisM = purchases(history, thisStart, today);
  const lastSame = purchases(history, lastStart, sameEnd);
  const byCategory: Record<string, number> = {};
  for (const t of thisM) byCategory[t.category ?? UNCATEGORIZED] = (byCategory[t.category ?? UNCATEGORIZED] ?? 0) - t.chargedAmount;
  for (const t of lastSame) byCategory[t.category ?? UNCATEGORIZED] = (byCategory[t.category ?? UNCATEGORIZED] ?? 0) + t.chargedAmount;
  for (const k in byCategory) byCategory[k] = round(byCategory[k]);
  const thisMonth = total(thisM);
  const lastMonthSamePeriod = total(lastSame);
  return {
    thisMonth,
    lastMonthSamePeriod,
    lastMonthTotal: total(purchases(history, lastStart, lastEnd)),
    byCategory,
    change: lastMonthSamePeriod > 0 ? (thisMonth - lastMonthSamePeriod) / lastMonthSamePeriod : null,
  };
}

// ---------- Bank movements ----------

export type MovementKind = 'transferIn' | 'transferOut' | 'cardDebit' | 'income' | 'expense';

// "העברה מאת: BNP PARIBAS - PARIS 10-800-02" → "BNP PARIBAS - PARIS 10-800-02".
const COUNTERPARTY = /^\s*(?:העברה|העב['׳]?|זיכוי|חיוב)?\s*(?:מאת|מ-|אל|ל-|לטובת|עבור|מ|ל)\s*:\s*(.+)$/;
// "ביט" (Bit) but not "ביטוח" (insurance).
const TRANSFER = /העברה|העב['׳]|bit|ביט(?!וח)|paybox|פייבוקס|transfer/i;

export const isTransfer = (t: Txn) => TRANSFER.test(t.description) || TRANSFER.test(t.memo ?? '');

export function movementKind(t: Txn): MovementKind {
  if (isCardDebit(t)) return 'cardDebit';
  if (isTransfer(t)) return t.chargedAmount >= 0 ? 'transferIn' : 'transferOut';
  return t.chargedAmount >= 0 ? 'income' : 'expense';
}

export interface TransferParty {
  name: string;
  bankCode?: number;
  branch?: string;
  account?: string;
}

/** Who sent or received the money, from Leumi's detail line, split into its parts. */
export function transferParty(t: Txn): TransferParty | null {
  const name = t.memo?.match(COUNTERPARTY)?.[1]?.trim();
  if (!name) return null;
  const m = name.match(/^(.*?)[\s,]*(\d{1,3})-(\d{1,4})-(\d{1,13})\s*$/);
  if (!m) return { name };
  const clean = m[1].replace(/^[\s\-,]+|[\s\-,]+$/g, '');
  return { name: clean || name, bankCode: Number(m[2]), branch: m[3], account: m[4] };
}

/** Israeli bank codes (Leumi's own list, `UC_SO_160_GetBankList`). */
export const ISRAELI_BANKS: Record<number, string> = {
  1: 'Isracard', 3: 'Bank Esh Israel', 4: 'Bank Yahav', 6: 'Max It Finance', 7: 'Industrial Development Bank',
  8: 'Israel Shipping Bank', 9: 'Israel Postal Bank', 10: 'Bank Leumi', 11: 'Discount Bank', 12: 'Bank Hapoalim',
  13: 'Union Bank', 14: 'Otsar Ha-Hayal', 15: 'Ofek Credit Union', 17: 'Mercantile Discount', 18: 'One Zero',
  20: 'Mizrahi-Tefahot', 21: 'Nima Shefa Israel', 22: 'Citibank', 23: 'HSBC', 24: 'Israel American Bank', 26: 'UBank',
  31: 'First International Bank', 34: 'Arab Israel Bank', 35: 'Grow Payments', 39: 'State Bank of India',
  46: 'Bank Massad', 47: 'Global Remit', 52: 'Poalei Agudat Israel Bank', 54: 'Bank of Jerusalem',
  58: 'Rewire', 68: 'Municipal Bank', 69: 'GMT Tech Innovation', 79: 'Monox (019)', 94: 'Phoenix Gamma',
  99: 'Bank of Israel',
};

/** Money in and out over a list of movements (positive numbers). */
export function movementTotals(txns: Txn[]): { in: number; out: number } {
  return {
    in: round(txns.filter((t) => t.chargedAmount > 0).reduce((s, t) => s + t.chargedAmount, 0)),
    out: round(-txns.filter((t) => t.chargedAmount < 0).reduce((s, t) => s + t.chargedAmount, 0)),
  };
}

// ---------- Wealth ----------

export interface WealthLine {
  kind: 'current' | 'card' | 'savings' | 'foreign';
  name: string;
  amount: number; // ILS (an estimate for foreign accounts)
  original?: number;
  currency?: string;
}

/**
 * Current account after the card debits already known, plus savings and
 * foreign-currency accounts converted at the Bank of Israel rate.
 */
export function wealth(s: TrueBalance): { lines: WealthLine[]; total: number; unconverted: { currency: string; balance: number }[] } {
  const lines: WealthLine[] = [{ kind: 'current', name: 'Leumi', amount: s.bankBalance }];
  const cardsDue = round(s.bankBalance - s.trueBalanceAllKnown);
  if (cardsDue !== 0) lines.push({ kind: 'card', name: 'Max', amount: -cardsDue });
  for (const a of s.savings ?? []) lines.push({ kind: 'savings', name: a.name, amount: a.balance });
  const unconverted = [];
  for (const f of s.foreignAccounts ?? []) {
    const rate = s.fxRates?.[f.currency];
    if (rate) lines.push({ kind: 'foreign', name: f.currency, amount: round(f.balance * rate), original: f.balance, currency: f.currency });
    else unconverted.push(f);
  }
  return { lines, total: round(lines.reduce((sum, l) => sum + l.amount, 0)), unconverted };
}

// ---------- Notes and export ----------

export interface PurchaseNote {
  text: string;
  tags: string[];
}

const escape = (f: string) => (/[",\n]/.test(f) ? `"${f.replace(/"/g, '""')}"` : f);

/** One row per purchase; amounts as spent (positive), dot decimals. */
export function csv(txns: Txn[], notes: Record<string, PurchaseNote> = {}): string {
  const lines = ['date,merchant,category,amount,currency,card,status,installment,debit_date,original_amount,original_currency,tags,note'];
  for (const t of [...txns].sort(newestFirst)) {
    lines.push([
      israelDay(t.date), t.description, t.category ?? '', (-t.chargedAmount).toFixed(2), t.chargedCurrency ?? 'ILS',
      t.cardLast4 ?? '', t.status, t.installments ? `${t.installments.number}/${t.installments.total}` : '',
      israelDay(t.processedDate), t.originalAmount != null ? (-t.originalAmount).toFixed(2) : '', t.originalCurrency ?? '',
      notes[t.id]?.tags.join(' ') ?? '', notes[t.id]?.text ?? '',
    ].map(escape).join(','));
  }
  return lines.join('\n') + '\n';
}
