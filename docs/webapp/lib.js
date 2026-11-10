// Pure logic, no DOM: Max's JSON → purchases → next debit, latest, categories.
// A port of MaxParser and the Max half of TrueBalance.compute in the iPhone app.

export const CATEGORIES = {
  1: "insurance", 2: "energy", 3: "fashion", 4: "home", 5: "travel", 6: "electronics",
  7: "groceries", 8: "books", 9: "leisure", 10: "transport", 11: "government", 12: "health",
  13: "telecom", 14: "other", 15: "max", 16: "cash", 17: "transfer", 18: "pets",
  19: "beauty", 20: "restaurants", 21: "fx", 22: "max",
};

export const CATEGORY_COLORS = {
  insurance: "#2550FF", energy: "#3DC0E9", fashion: "#00A3AD", home: "#C20017", travel: "#B200DF",
  electronics: "#7800F7", groceries: "#FF3F9B", books: "#FF2A11", leisure: "#FF7121", transport: "#009950",
  government: "#F9B300", health: "#879AFF", telecom: "#B6C700", other: "#A1A1A6", max: "#002AA9",
  cash: "#1BC200", transfer: "#AA82FF", pets: "#922108", beauty: "#FF8DAB", restaurants: "#13E2BF",
  fx: "#D9A364", uncategorized: "#A1A1A6",
};

const CURRENCIES = {
  840: "USD", 978: "EUR", 826: "GBP", 756: "CHF", 392: "JPY", 124: "CAD", 36: "AUD",
  752: "SEK", 578: "NOK", 208: "DKK", 710: "ZAR", 400: "JOD", 818: "EGP", 422: "LBP",
};

/** A number sent either as a JSON number or as text ("1,234.50"). */
export function num(v) {
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  if (typeof v === "string") {
    const n = Number(v.replace(/,/g, "").trim());
    return v.trim() !== "" && Number.isFinite(n) ? n : null;
  }
  return null;
}

const dayFormat = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Jerusalem", year: "numeric", month: "2-digit", day: "2-digit" });

/** Today (or any instant) as "YYYY-MM-DD" in Israel. */
export const israelDay = (date = new Date()) => dayFormat.format(date);

/** "2026-10-05T00:00:00" is already Israel local time; anything with an offset or Z is converted. */
export function dayOf(text) {
  const s = typeof text === "string" ? text.trim() : "";
  if (!s) return null;
  if (/(z|[+-]\d\d:?\d\d)$/i.test(s) && s.length > 10) {
    const d = new Date(s);
    return Number.isNaN(d.getTime()) ? null : israelDay(d);
  }
  return /^\d{4}-\d{2}-\d{2}/.test(s) ? s.slice(0, 10) : null;
}

/** "תשלום 2 מתוך 3" → { number: 2, total: 3 }. */
export function installments(comments) {
  if (typeof comments !== "string") return null;
  const numbers = (comments.match(/\d+/g) ?? []).map(Number);
  return numbers.length >= 2 ? { number: numbers[0], total: numbers[1] } : null;
}

function currencyOf(id) {
  const n = num(id);
  if (n === null || n === 376) return "ILS";
  return CURRENCIES[n] ?? String(n);
}

/** One `getTransactionsAndGraphs` response → purchases. Rows without a plan are summary rows. */
export function parseMonth(body) {
  const rows = body?.result?.transactions ?? [];
  const out = [];
  for (const raw of rows) {
    if (!raw.planName) continue;
    const day = dayOf(raw.purchaseDate);
    if (!day) continue;
    const paymentDay = dayOf(raw.paymentDate);
    const inst = installments(raw.comments);
    const actual = num(raw.actualPaymentAmount) ?? 0;
    const original = num(raw.originalAmount);
    // Pending purchases have no charged amount until Max processes them.
    const pendingWithoutAmount = paymentDay === null && actual === 0 && original !== null;
    const amount = pendingWithoutAmount ? original : actual;
    const currency = pendingWithoutAmount ? (raw.originalCurrency || "ILS") : currencyOf(raw.paymentCurrency);
    const arn = raw.dealData?.arn || `${raw.merchantName ?? ""}-${raw.purchaseDate ?? ""}-${actual}`;
    const txn = {
      id: inst ? `${arn}_${inst.number}` : arn,
      day,
      paymentDay,
      amount: -amount, // negative = expense, like the iPhone app
      currency,
      description: String(raw.merchantName ?? "").trim(),
      pending: paymentDay === null,
      installments: inst,
      category: CATEGORIES[num(raw.categoryId)] ?? null,
      card: raw.shortCardNumber ? String(raw.shortCardNumber).slice(-4) : null,
    };
    const shop = raw.originalCurrency;
    if (!pendingWithoutAmount && original && shop && shop.length === 3 && shop !== "ILS" && shop !== currency) {
      txn.original = { amount: original, currency: shop };
    }
    out.push(txn);
  }
  return out;
}

/** Every month of a relay answer, each purchase once, newest first. */
export function parseAll(answer) {
  const seen = new Map();
  for (const body of answer?.months ?? []) {
    for (const t of parseMonth(body)) seen.set(t.id, t);
  }
  return [...seen.values()].sort((a, b) => b.day.localeCompare(a.day));
}

const pad = (n) => String(n).padStart(2, "0");

/** The next `billingDay` strictly after `today` ("YYYY-MM-DD"). Max debits on the 2nd. */
export function nextBillingDay(today, billingDay = 2) {
  const [y, m, d] = today.split("-").map(Number);
  if (d < billingDay) return `${y}-${pad(m)}-${pad(billingDay)}`;
  const index = y * 12 + (m - 1) + 1;
  return `${Math.floor(index / 12)}-${pad((index % 12) + 1)}-${pad(billingDay)}`;
}

const round2 = (n) => Math.round(n * 100) / 100;

/** Shekel charges still to be debited, per debit day, soonest first. Pending ones go to the next cycle. */
export function upcoming(txns, today = israelDay()) {
  const byDay = new Map();
  const foreign = [];
  for (const t of txns) {
    if (t.currency !== "ILS") { foreign.push(t); continue; }
    const day = t.pending ? nextBillingDay(today) : t.paymentDay;
    if (day <= today) continue;
    if (!byDay.has(day)) byDay.set(day, []);
    byDay.get(day).push(t);
  }
  const charges = [...byDay.keys()].sort().map((day) => {
    const list = byDay.get(day).sort((a, b) => b.day.localeCompare(a.day));
    return { day, total: Math.max(0, round2(-list.reduce((s, t) => s + t.amount, 0))), txns: list };
  });
  return { charges, foreign };
}

/** One row per purchase: later installments of the same purchase are left out. */
export const purchases = (txns) => txns.filter((t) => (t.installments?.number ?? 1) <= 1);

/** Spending of a calendar month ("YYYY-MM") per category, biggest first. */
export function spendingByCategory(txns, month) {
  const totals = new Map();
  for (const t of purchases(txns)) {
    if (t.currency !== "ILS" || t.amount >= 0 || !t.day.startsWith(month)) continue;
    const key = t.category ?? "uncategorized";
    totals.set(key, (totals.get(key) ?? 0) - t.amount);
  }
  return [...totals].map(([key, total]) => ({ key, total: round2(total) })).sort((a, b) => b.total - a.total);
}

export function daysUntil(day, today = israelDay()) {
  const ms = (s) => Date.UTC(...s.split("-").map((v, i) => (i === 1 ? Number(v) - 1 : Number(v))));
  return Math.round((ms(day) - ms(today)) / 86_400_000);
}

/** What was spent each calendar month ("YYYY-MM"), oldest first. Shekel purchases only. */
export function monthlyTotals(txns) {
  const totals = new Map();
  for (const t of purchases(txns)) {
    if (t.currency !== "ILS" || t.amount >= 0) continue;
    const month = t.day.slice(0, 7);
    totals.set(month, (totals.get(month) ?? 0) - t.amount);
  }
  return [...totals].map(([month, total]) => ({ month, total: round2(total) })).sort((a, b) => a.month.localeCompare(b.month));
}

const median = (values) => {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = sorted.length >> 1;
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};

/** Same merchant, in at least two different months, about the same amount: subscriptions and standing orders. */
export function recurring(txns, today = israelDay()) {
  const groups = new Map();
  for (const t of txns) {
    if (t.currency !== "ILS" || t.amount >= 0 || t.installments) continue;
    const key = t.description.toLowerCase();
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(t);
  }
  const out = [];
  for (const list of groups.values()) {
    const months = new Set(list.map((t) => t.day.slice(0, 7)));
    if (months.size < 2) continue;
    const amount = median(list.map((t) => -t.amount));
    if (!list.every((t) => Math.abs(-t.amount - amount) <= amount * 0.1)) continue;
    const last = list.map((t) => t.day).sort().at(-1);
    const [y, m, d] = last.split("-").map(Number);
    let index = y * 12 + (m - 1) + 1;
    let next = `${Math.floor(index / 12)}-${pad((index % 12) + 1)}-${pad(d)}`;
    while (next < today) { index += 1; next = `${Math.floor(index / 12)}-${pad((index % 12) + 1)}-${pad(d)}`; }
    out.push({ name: list[0].description, amount: round2(amount), months: months.size, next, category: list[0].category });
  }
  return out.sort((a, b) => b.amount - a.amount);
}

/**
 * Leumi `UC_SO_27_GetBusinessAccountTrx` answer (the raw text) → balance and movements.
 * Same mapping as the iPhone app's LeumiParser. Negative amounts are money out.
 */
export function parseLeumi(bodyText, number = "") {
  const outer = typeof bodyText === "string" ? JSON.parse(bodyText) : bodyText;
  const inner = typeof outer.jsonResp === "string" ? JSON.parse(outer.jsonResp) : outer.jsonResp;
  const balance = num(inner?.BalanceDisplay);
  if (balance === null) throw new Error("Leumi answer has no balance");
  const map = (pending) => (r, i) => {
    const day = dayOf(r.DateUTC);
    if (!day) return null;
    const description = String(r.Description ?? "").trim();
    const amount = num(r.Amount) ?? 0;
    return {
      id: r.FITID || (num(r.ReferenceNumberLong) !== null ? String(num(r.ReferenceNumberLong)) : `${day}-${description}-${amount}-${pending ? "t" : "h"}${i}`),
      day,
      amount,
      description,
      memo: String(r.AdditionalData ?? "").trim() || null,
      balanceAfter: num(r.RunningBalance),
      pending,
    };
  };
  const movements = [
    ...(inner.TodayTransactionsItems ?? []).map(map(true)),
    ...(inner.HistoryTransactionsItems ?? []).map(map(false)),
  ].filter(Boolean).sort((a, b) => b.day.localeCompare(a.day));
  return { number, balance, movements };
}

/** What is really available: the Leumi balance minus the next Max debit. */
export const trueBalance = (balance, charges) => round2(balance - (charges[0]?.total ?? 0));
