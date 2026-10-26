import { test } from 'node:test';
import assert from 'node:assert/strict';
import { errorText, formatters, L } from './i18n.ts';

test("uses the iPhone app's translations, plurals included", () => {
  assert.equal(L('fr', 'Calculation'), 'Calcul');
  assert.equal(L('en', '%lld purchase(s)', 1), '1 purchase');
  assert.equal(L('fr', '%lld purchase(s)', 3), '3 achats');
  assert.equal(L('he', '%lld day(s) until the debit', 2), 'יומיים עד החיוב');
  assert.equal(L('en', 'Left %@ of %@', '₪10', '₪50'), 'Left ₪10 of ₪50');
  assert.equal(L('en', '%@: 80%% of the budget used', 'Groceries'), 'Groceries: 80% of the budget used');
});

test('every scraper error has a sentence in every language', () => {
  for (const lang of ['en', 'fr', 'he', 'ru', 'ar'] as const) {
    for (const code of ['INVALID_PASSWORD', 'CHANGE_PASSWORD', 'ACCOUNT_BLOCKED', 'TIMEOUT', 'GENERIC', 'BROWSER', 'NO_ACCOUNT', 'SERVER_DOWN']) {
      const s = errorText(lang, code, 'Max');
      assert.ok(!/%@|[A-Z_]{6,}/.test(s), `${lang} ${code}: ${s}`);
    }
  }
});

test('a second currency: converted amounts marked ≈, an amount paid in it exact', () => {
  const plain = formatters('en');
  assert.equal(plain.ils(349), '₪349.00');
  assert.equal(plain.secondary(349), null);

  const below = formatters('en', { code: 'EUR', rate: 3.49, first: false });
  assert.equal(below.ils(349), '₪349.00');
  assert.equal(below.secondary(349), '≈ €100.00');
  assert.equal(below.secondary(152.7, false, { amount: 42.3, currency: 'EUR' }), '€42.30');

  const first = formatters('en', { code: 'EUR', rate: 3.49, first: true });
  assert.equal(first.ils(-349), '≈ −€100.00');
  assert.equal(first.ilsWhole(349), '≈ €100');
  assert.equal(first.secondary(349), '₪349.00');
  assert.equal(first.shekels(349), '₪349.00');
});
