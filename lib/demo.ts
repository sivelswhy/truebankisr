import type { Account } from './compute.ts';

// Sample data so the app can be tried without bank credentials (DEMO=1).
export function demoData(now = new Date()): { bank: Account; cards: Account[] } {
  const y = now.getFullYear();
  const m = now.getMonth();
  const billing = (offset: number) => new Date(Date.UTC(y, m + offset, 1, 22)).toISOString();
  const purchase = (daysAgo: number) => new Date(now.getTime() - daysAgo * 86_400_000).toISOString();
  const t = (daysAgo: number, amount: number, description: string, offset = 1, extra: object = {}) => ({
    date: purchase(daysAgo),
    processedDate: billing(offset),
    chargedAmount: -amount,
    chargedCurrency: 'ILS',
    description,
    status: 'completed' as const,
    ...extra,
  });

  return {
    bank: { accountNumber: '812-123456/78', balance: 163, txns: [] },
    cards: [{
      accountNumber: '4580',
      txns: [
        t(14, 412.9, 'Shufersal Deal', 1, { category: 'מזון וצריכה' }),
        t(11, 89, 'Paz Yellow', 1, { category: 'דלק, חשמל וגז' }),
        t(9, 249.9, 'IKEA Rishon', 1, { category: 'עיצוב הבית', installments: { number: 1, total: 3 } }),
        t(9, 249.9, 'IKEA Rishon', 2, { category: 'עיצוב הבית', installments: { number: 2, total: 3 } }),
        t(9, 249.9, 'IKEA Rishon', 3, { category: 'עיצוב הבית', installments: { number: 3, total: 3 } }),
        t(6, 54, 'Aroma Espresso Bar', 1, { category: 'מסעדות, קפה וברים' }),
        t(3, 119.9, 'Partner Communications', 1, { category: 'שירותי תקשורת' }),
        { ...t(0, 38.5, 'Rami Levy', 1, { category: 'מזון וצריכה' }), status: 'pending' as const, processedDate: purchase(0) },
      ],
    }],
  };
}
