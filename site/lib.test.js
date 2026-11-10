import test from "node:test";
import assert from "node:assert/strict";
import { parseLeumi, trueBalance, monthlyTotals, recurring, parseMonth, parseAll, upcoming, nextBillingDay, spendingByCategory, installments, dayOf, daysUntil } from "./lib.js";

const row = (o) => ({ planName: "רגילה", purchaseDate: "2026-11-03T00:00:00", paymentDate: "2026-12-02T00:00:00",
  actualPaymentAmount: 50, paymentCurrency: 376, merchantName: " Aroma ", categoryId: 20, shortCardNumber: "1234", ...o });

test("parses a purchase, trims the name, maps category and card", () => {
  const [t] = parseMonth({ result: { transactions: [row({})] } });
  assert.equal(t.description, "Aroma");
  assert.equal(t.amount, -50);
  assert.equal(t.category, "restaurants");
  assert.equal(t.card, "1234");
  assert.equal(t.paymentDay, "2026-12-02");
  assert.equal(t.pending, false);
});

test("skips summary rows without a plan", () => {
  assert.equal(parseMonth({ result: { transactions: [row({ planName: "" })] } }).length, 0);
});

test("pending purchase takes the original amount", () => {
  const [t] = parseMonth({ result: { transactions: [row({ paymentDate: null, actualPaymentAmount: 0, originalAmount: "1,200.50", originalCurrency: "ILS" })] } });
  assert.equal(t.pending, true);
  assert.equal(t.amount, -1200.5);
});

test("foreign purchase keeps what it cost at the shop", () => {
  const [t] = parseMonth({ result: { transactions: [row({ originalAmount: 10, originalCurrency: "EUR", actualPaymentAmount: 40 })] } });
  assert.deepEqual(t.original, { amount: 10, currency: "EUR" });
  assert.equal(t.currency, "ILS");
});

test("installments and ids", () => {
  assert.deepEqual(installments("תשלום 2 מתוך 3"), { number: 2, total: 3 });
  const [t] = parseMonth({ result: { transactions: [row({ comments: "תשלום 2 מתוך 3", dealData: { arn: "A1" } })] } });
  assert.equal(t.id, "A1_2");
});

test("dates: local stays, offset converts to Israel", () => {
  assert.equal(dayOf("2026-10-05T00:00:00"), "2026-10-05");
  assert.equal(dayOf("2026-10-05T22:30:00Z"), "2026-10-06");
  assert.equal(dayOf(""), null);
});

test("next billing day is strictly after today", () => {
  assert.equal(nextBillingDay("2026-11-01"), "2026-11-02");
  assert.equal(nextBillingDay("2026-11-02"), "2026-12-02");
  assert.equal(nextBillingDay("2026-12-15"), "2027-01-02");
});

test("upcoming groups by debit day, pending go to the next cycle, past debits are dropped", () => {
  const all = parseAll({ months: [{ result: { transactions: [
    row({ dealData: { arn: "a" }, actualPaymentAmount: 100 }),
    row({ dealData: { arn: "b" }, actualPaymentAmount: 20 }),
    row({ dealData: { arn: "c" }, paymentDate: null, actualPaymentAmount: 0, originalAmount: 30, originalCurrency: "ILS" }),
    row({ dealData: { arn: "d" }, paymentDate: "2026-11-02T00:00:00", actualPaymentAmount: 999 }),
  ] } }] });
  const { charges } = upcoming(all, "2026-11-10");
  assert.deepEqual(charges.map((c) => [c.day, c.total]), [["2026-12-02", 150]]);
});

test("spending by category counts the month's purchases only", () => {
  const all = parseAll({ months: [{ result: { transactions: [
    row({ dealData: { arn: "a" }, actualPaymentAmount: 60 }),
    row({ dealData: { arn: "b" }, categoryId: 7, actualPaymentAmount: 90 }),
    row({ dealData: { arn: "c" }, purchaseDate: "2026-10-30T00:00:00", actualPaymentAmount: 500 }),
  ] } }] });
  assert.deepEqual(spendingByCategory(all, "2026-11"), [{ key: "groceries", total: 90 }, { key: "restaurants", total: 60 }]);
});

test("days until", () => {
  assert.equal(daysUntil("2026-12-02", "2026-11-10"), 22);
});

test("monthly totals add up each month's shekel purchases", () => {
  const all = parseAll({ months: [{ result: { transactions: [
    row({ dealData: { arn: "a" }, actualPaymentAmount: 60 }),
    row({ dealData: { arn: "b" }, actualPaymentAmount: 40 }),
    row({ dealData: { arn: "c" }, purchaseDate: "2026-10-30T00:00:00", actualPaymentAmount: 500 }),
  ] } }] });
  assert.deepEqual(monthlyTotals(all), [{ month: "2026-10", total: 500 }, { month: "2026-11", total: 100 }]);
});

test("recurring: same merchant over two months at a steady amount, not one-offs or varying amounts", () => {
  const r = (arn, name, day, amount) => row({ dealData: { arn }, merchantName: name, purchaseDate: `${day}T00:00:00`, actualPaymentAmount: amount });
  const all = parseAll({ months: [{ result: { transactions: [
    r("1", "Netflix", "2026-10-05", 55), r("2", "Netflix", "2026-11-05", 55),
    r("3", "Aroma", "2026-10-05", 20), r("4", "Aroma", "2026-11-09", 90),
    r("5", "Once", "2026-11-01", 300),
  ] } }] });
  const found = recurring(all, "2026-11-10");
  assert.deepEqual(found.map((x) => [x.name, x.amount, x.next]), [["Netflix", 55, "2026-12-05"]]);
});

test("Leumi: balance, today's movements pending, history completed, newest first", () => {
  const inner = {
    BalanceDisplay: "1,234.50",
    TodayTransactionsItems: [{ DateUTC: "2026-11-10T00:00:00", Description: " Bit ", Amount: -30, FITID: "t1" }],
    HistoryTransactionsItems: [
      { DateUTC: "2026-11-02T00:00:00", Description: "מקס", Amount: -964.2, RunningBalance: 1264.5, AdditionalData: " חיוב ", ReferenceNumberLong: 77 },
      { DateUTC: "", Description: "no date", Amount: 1 },
    ],
  };
  const r = parseLeumi(JSON.stringify({ jsonResp: JSON.stringify(inner) }), "123_45");
  assert.equal(r.balance, 1234.5);
  assert.equal(r.number, "123_45");
  assert.deepEqual(r.movements.map((m) => [m.id, m.day, m.amount, m.pending]), [["t1", "2026-11-10", -30, true], ["77", "2026-11-02", -964.2, false]]);
  assert.equal(r.movements[1].memo, "חיוב");
  assert.equal(r.movements[1].balanceAfter, 1264.5);
});

test("Leumi: an answer without a balance is refused", () => {
  assert.throws(() => parseLeumi(JSON.stringify({ jsonResp: JSON.stringify({}) })));
});

test("really available = Leumi balance minus the next Max debit", () => {
  assert.equal(trueBalance(1000, [{ total: 250.5 }]), 749.5);
  assert.equal(trueBalance(1000, []), 1000);
});
