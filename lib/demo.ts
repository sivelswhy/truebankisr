import { israelDay, type Account, type Txn } from './compute.ts';

function israelMidnight(day: string): string {
  for (const offset of ['+03:00', '+02:00']) {
    const d = new Date(`${day}T00:00:00${offset}`);
    if (new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Jerusalem', hour: '2-digit', hourCycle: 'h23' }).format(d) === '00') return d.toISOString();
  }
  return new Date(`${day}T00:00:00Z`).toISOString();
}

// Sample data to try the app without bank credentials: the same as the
// iPhone app's DemoData, relative to today.
export function demoData(now = new Date()): { bank: Account; cards: Account[] } {
  const y = now.getFullYear();
  const m = now.getMonth();
  // The 2nd of a month, 06:00 UTC (morning in Israel).
  const billing = (offset: number) => new Date(Date.UTC(y, m + offset, 2, 6)).toISOString();
  // Banks only give the day for completed purchases and movements: midnight in Israel.
  const ago = (days: number) => israelMidnight(israelDay(new Date(now.getTime() - days * 86_400_000)));
  const main = '4580';
  const second = '1127';
  const t = (
    days: number, amount: number, name: string, category: string,
    { month = 1, installments, pending = false, card = main }: { month?: number; installments?: Txn['installments']; pending?: boolean; card?: string } = {},
  ): Txn => ({
    id: `${name}-${month}`,
    date: ago(days),
    processedDate: pending ? ago(days) : billing(month),
    chargedAmount: -amount,
    chargedCurrency: 'ILS',
    description: name,
    status: pending ? 'pending' : 'completed',
    category,
    cardLast4: card,
    ...(installments ? { installments } : {}),
  });

  const txns: Txn[] = [
    t(14, 412.9, 'Shufersal Deal', 'groceries'),
    t(11, 89, 'Paz Yellow', 'energy'),
    t(9, 249.9, 'IKEA Rishon', 'home', { installments: { number: 1, total: 3 } }),
    t(9, 249.9, 'IKEA Rishon', 'home', { month: 2, installments: { number: 2, total: 3 } }),
    t(9, 249.9, 'IKEA Rishon', 'home', { month: 3, installments: { number: 3, total: 3 } }),
    t(6, 54, 'Aroma Espresso Bar', 'restaurants', { card: second }),
    t(3, 119.9, 'Partner Communications', 'telecom'),
    t(2, 64, 'Super-Pharm', 'health', { card: second }),
    // Pending purchases carry the time of day, like Max gives it.
    { ...t(0, 38.5, 'Rami Levy', 'groceries', { pending: true }), date: new Date(now.getTime() - 2 * 3_600_000).toISOString() },
  ];
  // Subscriptions: same amount every month (Netflix is billed in dollars).
  for (let month = 0; month <= 5; month++) {
    txns.push(
      { id: `netflix-${month}`, date: ago(month * 30 + 5), processedDate: billing(-month + 1), chargedAmount: -15.49, chargedCurrency: 'USD',
        description: 'NETFLIX.COM', status: 'completed', category: 'leisure', cardLast4: main },
      { id: `spotify-${month}`, date: ago(month * 30 + 8), processedDate: billing(-month + 1), chargedAmount: -19.9, chargedCurrency: 'ILS',
        description: 'Spotify', status: 'completed', category: 'leisure', cardLast4: second },
    );
  }
  // Past months, already debited: history for the spending and merchant pages.
  const past: [string, string, number][] = [
    ['Shufersal Deal', 'groceries', 380], ['Aroma Espresso Bar', 'restaurants', 42], ['Paz Yellow', 'energy', 95],
    ['Rami Levy', 'groceries', 210], ['Partner Communications', 'telecom', 119.9], ['Wolt', 'restaurants', 86],
  ];
  for (let month = 1; month <= 5; month++) {
    past.forEach(([name, category, amount], i) => {
      txns.push({
        id: `${name}-past-${month}-${i}`, date: ago(month * 30 + i * 4 + 3), processedDate: billing(-month + 1),
        chargedAmount: -(amount + ((month * 7 + i * 3) % 25)), chargedCurrency: 'ILS', description: name, status: 'completed',
        category, cardLast4: i % 3 === 0 ? second : main,
      });
    });
  }

  // Leumi: salary and standing orders, for the forecast, and a few transfers.
  const move = (id: string, days: number, amount: number, description: string, memo?: string): Txn => ({
    id, date: ago(days), processedDate: ago(days), chargedAmount: amount, chargedCurrency: 'ILS', description, status: 'completed',
    ...(memo ? { memo } : {}),
  });
  const bank: Txn[] = [];
  for (let month = 1; month <= 3; month++) {
    const back = (month - 1) * 30;
    bank.push(
      move(`salary-${month}`, 24 + back, 11_800 + month * 50, 'משכורת'),
      move(`rent-${month}`, 18 + back, -4_900, 'שכר דירה'),
      move(`insurance-${month}`, 22 + back, -312.4, 'הראל ביטוח'),
    );
  }
  bank.push(
    move('tr-1', 1, -250, 'העברה בנקאית', 'העברה ל: דנה כהן 12-345-678'),
    move('tr-2', 4, 180, 'העברה מחשבון', 'העברה מאת: יוסי לוי 10-800-02'),
    move('tr-3', 12, -1_200, 'העברה בנקאית', 'העברה ל: ועד הבית 20-512-334'),
  );
  let running = 163;
  for (const txn of [...bank].sort((a, b) => b.date.localeCompare(a.date))) {
    txn.runningBalance = running;
    running -= txn.chargedAmount;
  }

  return {
    bank: { accountNumber: '812-123456', balance: 163, txns: bank },
    cards: [{ accountNumber: 'max', txns }],
  };
}

/** What the demo also shows on the iPhone: savings and a dollar account. */
export const DEMO_EXTRAS = {
  fxRates: { USD: 3.11, EUR: 3.49 },
  savings: [{ name: 'פיקדון קצר מועד', balance: 25_000 }],
  foreignAccounts: [{ currency: 'USD', balance: 1_250 }],
};
