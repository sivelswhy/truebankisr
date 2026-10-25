import { test } from 'node:test';
import assert from 'node:assert/strict';
import { computeTrueBalance, dailyBudget, daysUntil, type Txn } from './compute.ts';

let n = 0;
const card = (processedDate: string, amount: number, extra: Partial<Txn> = {}): Txn => ({
  id: `t${n++}`,
  date: '2026-10-05T10:00:00.000Z',
  processedDate,
  chargedAmount: -amount,
  chargedCurrency: 'ILS',
  description: 'shop',
  status: 'completed',
  ...extra,
});

const now = new Date('2026-10-19T09:00:00Z');

test('subtracts card charges not yet debited', () => {
  const r = computeTrueBalance(
    { accountNumber: 'b', balance: 163, txns: [] },
    [{
      accountNumber: 'c',
      txns: [
        card('2026-10-01T21:00:00.000Z', 500), // Oct 2 Israel time: already debited
        card('2026-11-01T22:00:00.000Z', 120), // Nov 2
        card('2026-11-01T22:00:00.000Z', 80.5),
        card('2026-12-01T22:00:00.000Z', 40, { installments: { number: 2, total: 3 } }),
      ],
    }],
    { now },
  );
  assert.equal(r.nextCharge?.chargeDate, '2026-11-02');
  assert.equal(r.nextCharge?.total, 200.5);
  assert.equal(r.trueBalance, -37.5);
  assert.equal(r.trueBalanceAllKnown, -77.5);
  assert.equal(r.upcoming.length, 2);
});

test('pending txns go to the next billing day', () => {
  const r = computeTrueBalance(
    { accountNumber: 'b', balance: 1000, txns: [] },
    [{ accountNumber: 'c', txns: [card('2026-10-18T10:00:00.000Z', 30, { status: 'pending' })] }],
    { now },
  );
  assert.equal(r.nextCharge?.chargeDate, '2026-11-02');
  assert.equal(r.trueBalance, 970);
});

test('on billing day, charge counts until the bank shows the debit', () => {
  const billingNow = new Date('2026-11-02T08:00:00Z');
  const cards = [{ accountNumber: 'c', txns: [card('2026-11-01T22:00:00.000Z', 300)] }];

  const before = computeTrueBalance({ accountNumber: 'b', balance: 500, txns: [] }, cards, { now: billingNow });
  assert.equal(before.trueBalance, 200);

  const debit: Txn = { ...card('2026-11-02T05:00:00.000Z', 300), date: '2026-11-02T05:00:00.000Z', description: 'מקס איט פיננ' };
  const after = computeTrueBalance({ accountNumber: 'b', balance: 200, txns: [debit] }, cards, { now: billingNow });
  assert.equal(after.trueBalance, 200);
  assert.equal(after.nextCharge, null);
});

test('foreign-currency charges are reported, not subtracted', () => {
  const r = computeTrueBalance(
    { accountNumber: 'b', balance: 100, txns: [] },
    [{ accountNumber: 'c', txns: [card('2026-11-01T22:00:00.000Z', 10, { chargedCurrency: 'USD' })] }],
    { now },
  );
  assert.equal(r.trueBalance, 100);
  assert.equal(r.ignoredForeign.length, 1);
});

test('pending Max txns with no charged amount yet use the original amount', () => {
  const r = computeTrueBalance(
    { accountNumber: 'b', balance: 100, txns: [] },
    [{ accountNumber: 'c', txns: [card('2026-10-19T08:00:00.000Z', 0, { status: 'pending', originalAmount: -42, originalCurrency: 'ILS' })] }],
    { now },
  );
  assert.equal(r.nextCharge?.total, 42);
  assert.equal(r.trueBalance, 58);
});

test('foreign charges with a known rate become ILS estimates', () => {
  const r = computeTrueBalance(
    { accountNumber: 'b', balance: 100, txns: [] },
    [{ accountNumber: 'c', txns: [card('2026-11-01T22:00:00.000Z', 10, { chargedCurrency: 'USD' })] }],
    { now, fxRates: { USD: 3.5 } },
  );
  assert.equal(r.trueBalance, 65);
  assert.equal(r.ignoredForeign.length, 0);
  assert.equal(r.nextCharge?.txns[0].originalCurrency, 'USD');
  assert.equal(r.nextCharge?.txns[0].originalAmount, -10);
});

test('a statement in credit debits nothing and carries the credit to the next one', () => {
  const r = computeTrueBalance(
    { accountNumber: 'b', balance: 500, txns: [] },
    [{
      accountNumber: 'c',
      txns: [
        card('2026-11-01T22:00:00.000Z', 156.9),
        card('2026-11-01T22:00:00.000Z', -200, { category: 'transfer' }), // money sent to the card from Revolut
        card('2026-12-01T22:00:00.000Z', 100),
      ],
    }],
    { now },
  );
  assert.equal(r.nextCharge?.total, 0);
  assert.equal(r.nextCharge?.credit, 43.1);
  assert.equal(r.trueBalance, 500);
  assert.equal(r.upcoming[1].total, 56.9);
  assert.equal(r.upcoming[1].credit, undefined);
  assert.equal(r.trueBalanceAllKnown, 443.1);
});

test('daily budget spreads the true balance until the debit', () => {
  const r = computeTrueBalance(
    { accountNumber: 'b', balance: 1300, txns: [] },
    [{ accountNumber: 'c', txns: [card('2026-11-01T22:00:00.000Z', 100)] }],
    { now },
  );
  assert.equal(daysUntil('2026-11-02', now), 14);
  assert.equal(dailyBudget(r, now), 85.71);
});
