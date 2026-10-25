import { test } from 'node:test';
import assert from 'node:assert/strict';
import { computeTrueBalance, type Txn } from './compute.ts';
import {
  addMonths, budgetProgress, purchases, compareMonths, csv, detectRecurring, forecast, mergeHistory, movementKind, subscriptions, transferParty,
} from './insights.ts';

const now = new Date('2026-10-19T09:00:00Z');
let n = 0;
const txn = (date: string, amount: number, description: string, extra: Partial<Txn> = {}): Txn => ({
  id: `t${n++}`, date, processedDate: date, chargedAmount: amount, chargedCurrency: 'ILS', description, status: 'completed', ...extra,
});

test('months roll over and clamp to the month length', () => {
  assert.equal(addMonths('2026-01-31', 1), '2026-02-28');
  assert.equal(addMonths('2026-12-15', 1), '2027-01-15');
  assert.equal(addMonths('2026-03-01', -3), '2025-12-01');
});

test('subscriptions: same merchant and amount every month', () => {
  const history = [
    txn('2026-08-05T10:00:00Z', -19.9, 'Spotify'), txn('2026-09-05T10:00:00Z', -19.9, 'Spotify'), txn('2026-10-05T10:00:00Z', -19.9, 'Spotify'),
    txn('2026-09-10T10:00:00Z', -40, 'Wolt'), txn('2026-10-10T10:00:00Z', -95, 'Wolt'), // amounts too different
    txn('2026-06-01T10:00:00Z', -30, 'Old gym'), txn('2026-07-01T10:00:00Z', -30, 'Old gym'), // stopped
  ];
  const subs = subscriptions(history, now);
  assert.deepEqual(subs.map((s) => s.name), ['Spotify']);
  assert.equal(subs[0].nextDate, '2026-11-05');
});

test('forecast adds the salary expected before the debit', () => {
  const bank = [
    txn('2026-08-25T08:00:00Z', 10000, 'משכורת'), txn('2026-09-25T08:00:00Z', 10000, 'משכורת'),
    txn('2026-09-02T08:00:00Z', -900, 'מקס איט פיננ'), txn('2026-10-02T08:00:00Z', -950, 'מקס איט פיננ'), // card debit: not a forecast
  ];
  const s = computeTrueBalance(
    { accountNumber: 'b', balance: 1000, txns: bank },
    [{ accountNumber: 'c', txns: [{ ...txn('2026-10-10T10:00:00Z', -300, 'shop'), processedDate: '2026-11-01T22:00:00Z' }] }],
    { now },
  );
  const f = forecast(s, now)!;
  assert.equal(f.until, '2026-11-02');
  assert.equal(f.income.length, 1);
  assert.equal(f.debits.length, 0);
  assert.equal(f.projectedBalance, 10700);
});

test('budgets count this month only, per category', () => {
  const history = [
    txn('2026-10-03T10:00:00Z', -600, 'Shufersal', { category: 'groceries' }),
    txn('2026-10-12T10:00:00Z', -650, 'Rami Levy', { category: 'groceries' }),
    txn('2026-09-28T10:00:00Z', -999, 'Shufersal', { category: 'groceries' }),
  ];
  const [g] = budgetProgress({ groceries: 1500, fuel: 0 }, history, now);
  assert.equal(g.spent, 1250);
  assert.ok(Math.abs(g.ratio - 0.8333) < 0.001);
});

test('money sent to the card is not a refund of spending', () => {
  const history = [
    txn('2026-10-16T10:00:00Z', -45, 'Bakery', { category: 'groceries' }),
    txn('2026-10-22T10:00:00Z', 200, 'REVOLUT*NEHEMIE ISAAC', { category: 'transfer' }),
    txn('2026-10-23T10:00:00Z', 30, 'Bakery', { category: 'groceries' }), // a real refund still counts
  ];
  assert.deepEqual(purchases(history, '2026-10-01', '2026-10-31').map((t) => t.chargedAmount), [-45, 30]);
});

test('month to month compares the same number of days', () => {
  const history = [
    txn('2026-10-05T10:00:00Z', -100, 'a', { category: 'groceries' }),
    txn('2026-09-05T10:00:00Z', -50, 'b', { category: 'groceries' }),
    txn('2026-09-25T10:00:00Z', -500, 'c', { category: 'groceries' }), // after the 19th: whole month only
  ];
  const c = compareMonths(history, now);
  assert.equal(c.thisMonth, 100);
  assert.equal(c.lastMonthSamePeriod, 50);
  assert.equal(c.lastMonthTotal, 550);
  assert.equal(c.change, 1);
  assert.equal(c.byCategory.groceries, 50);
});

test("transfers: kind and the other side from Leumi's detail line", () => {
  const t = txn('2026-10-14T21:00:00Z', 163.53, 'סכום פקת"ש', { memo: 'העברה מאת: BNP PARIBAS - PARIS 10-800-02' });
  assert.equal(movementKind(t), 'transferIn');
  assert.deepEqual(transferParty(t), { name: 'BNP PARIBAS - PARIS', bankCode: 10, branch: '800', account: '02' });
  assert.equal(movementKind(txn('2026-10-02T08:00:00Z', -950, 'מקס איט פיננ')), 'cardDebit');
  assert.equal(movementKind(txn('2026-10-02T08:00:00Z', -50, 'עמלה')), 'expense');
});

test('history keeps older cached purchases and replaces the refetched months', () => {
  const old = txn('2026-05-01T10:00:00Z', -10, 'old');
  const stale = { ...txn('2026-10-01T10:00:00Z', -20, 'pending'), status: 'pending' as const };
  const fresh = { ...stale, status: 'completed' as const };
  const merged = mergeHistory([stale, old], [fresh], '2026-09-01');
  assert.deepEqual(merged.map((t) => t.status), ['completed', 'completed']);
  assert.equal(merged.length, 2);
});

test('CSV escapes commas and quotes, and includes notes', () => {
  const t = txn('2026-10-05T10:00:00Z', -12.5, 'Café "Joe", TLV', { category: 'restaurants' });
  const out = csv([t], { [t.id]: { text: 'lunch', tags: ['work'] } });
  assert.match(out, /^date,merchant/);
  assert.match(out, /"Café ""Joe"", TLV",restaurants,12\.50,ILS/);
  assert.match(out, /,work,lunch\n$/);
});

test('recurring needs about one charge per month', () => {
  const many = ['01', '03', '05', '07'].map((d) => txn(`2026-10-${d}T10:00:00Z`, -10, 'coffee'));
  assert.equal(detectRecurring([...many, txn('2026-09-01T10:00:00Z', -10, 'coffee')], { now }).length, 0);
});
