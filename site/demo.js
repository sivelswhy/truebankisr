// Made-up Max answer (same shape as the real one) for trying the page without signing in.
import { israelDay } from "./lib.js";

const shops = [
  ["שופרסל דיל", 7, 90, 420], ["רמי לוי", 7, 60, 380], ["Aroma Espresso", 20, 18, 55], ["וולט", 20, 45, 130],
  ["Netflix", 9, 55, 55], ["Spotify", 9, 20, 20], ["פז", 2, 150, 320], ["סונול", 2, 140, 300],
  ["רב-קו", 10, 30, 100], ["Gett", 10, 25, 70], ["סלקום", 13, 120, 120], ["סופר פארם", 12, 35, 160],
  ["Castro", 3, 120, 380], ["Zara", 3, 150, 450], ["KSP", 6, 250, 1800], ["IKEA", 4, 120, 900],
  ["הפניקס ביטוח", 1, 210, 210], ["Booking.com", 5, 600, 2400], ["Cinema City", 9, 40, 110], ["מכבי שירותי בריאות", 12, 28, 90],
];

export function demoAnswer(now = new Date()) {
  let seed = 7;
  const rand = () => (seed = (seed * 48271) % 2147483647) / 2147483647;
  const today = israelDay(now);
  const [y, m, d] = today.split("-").map(Number);
  const iso = (date) => `${date.toISOString().slice(0, 10)}T00:00:00`;
  const secondAfter = (date) => {
    const next = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + (date.getUTCDate() < 2 ? 0 : 1), 2));
    return next;
  };
  const rows = [];
  for (let i = 0; i < 90; i++) {
    const [name, category, low, high] = shops[Math.floor(rand() * shops.length)];
    const when = new Date(Date.UTC(y, m - 1, d - Math.floor(rand() * 75)));
    const amount = Math.round((low + rand() * (high - low)) * 100) / 100;
    const payment = secondAfter(when);
    const pending = when > new Date(Date.UTC(y, m - 1, d - 2));
    const abroad = name === "Booking.com";
    rows.push({
      planName: "רגילה", merchantName: name, categoryId: category, shortCardNumber: i % 4 === 0 ? "5521" : "1234",
      purchaseDate: iso(when), paymentDate: pending ? null : iso(payment),
      actualPaymentAmount: pending ? 0 : amount, originalAmount: abroad ? Math.round(amount / 4) : amount,
      originalCurrency: abroad ? "EUR" : "ILS", paymentCurrency: 376, comments: "", dealData: { arn: `demo-${i}` },
    });
  }
  return { months: [{ result: { transactions: rows } }] };
}

/** Made-up Leumi account, same shape as `parseLeumi` returns. */
export function demoLeumi(now = new Date()) {
  const today = israelDay(now);
  const [y, m, d] = today.split("-").map(Number);
  const day = (back) => new Date(Date.UTC(y, m - 1, d - back)).toISOString().slice(0, 10);
  const rows = [
    [0, "העברה ל: דנה כהן", -250, true], [1, "משכורת", 12400, false], [3, "הוראת קבע - ארנונה", -640, false],
    [5, "ביט - העברה", -80, false], [8, "כספומט", -300, false], [9, "מקס - חיוב", -3120.4, false],
    [12, "הוראת קבע - חשמל", -410.2, false], [15, "העברה מ: יוסי לוי", 500, false], [20, "שכר דירה", -4800, false],
  ];
  let balance = 4280.55;
  return {
    number: "123_45_678",
    balance,
    movements: rows.map(([back, description, amount, pending], i) => {
      const row = { id: `demo-l${i}`, day: day(back), amount, description, memo: null, balanceAfter: Math.round(balance * 100) / 100, pending };
      balance -= amount;
      return row;
    }),
  };
}
