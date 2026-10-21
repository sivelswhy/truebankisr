// Max category names (Hebrew, as returned by Max's API) → the iPhone app's
// category keys and colours. Labels are "category.<key>" in lib/strings.json.
// Source: https://onlinelcapi.max.co.il/api/contents/getCategories

export const UNCATEGORIZED = 'uncategorized';

const BY_NAME: Record<string, string> = {
  'ביטוח': 'insurance',
  'דלק, חשמל וגז': 'energy',
  'אופנה': 'fashion',
  'עיצוב הבית': 'home',
  'טיסות ותיירות': 'travel',
  'חשמל ומחשבים': 'electronics',
  'מזון וצריכה': 'groceries',
  'ספרים ודפוס': 'books',
  'פנאי, בידור וספורט': 'leisure',
  'תחבורה ורכבים': 'transport',
  'עירייה וממשלה': 'government',
  'רפואה ובתי מרקחת': 'health',
  'שירותי תקשורת': 'telecom',
  'שונות': 'other',
  'מוצרי אשראי m_a_x': 'max',
  'מוצרי m_a_x': 'max',
  'משיכת מזומן': 'cash',
  'העברת כספים': 'transfer',
  'חיות מחמד': 'pets',
  'קוסמטיקה וטיפוח': 'beauty',
  'מסעדות, קפה וברים': 'restaurants',
  'מט"ח': 'fx',
};

// Same colours as `Category.colors` in TrueBalanceCore.
export const COLORS: Record<string, string> = {
  insurance: '#2550FF', energy: '#3DC0E9', fashion: '#00A3AD', home: '#C20017',
  travel: '#B200DF', electronics: '#7800F7', groceries: '#FF3F9B', books: '#FF2A11',
  leisure: '#FF7121', transport: '#009950', government: '#F9B300', health: '#879AFF',
  telecom: '#B6C700', other: '#A1A1A6', max: '#002AA9', cash: '#1BC200',
  transfer: '#AA82FF', pets: '#922108', beauty: '#FF8DAB', restaurants: '#13E2BF',
  fx: '#D9A364', [UNCATEGORIZED]: '#A1A1A6',
};

/** Max's Hebrew category name → stable key. */
export function categoryKey(name: string | undefined): string {
  return (name && BY_NAME[name.trim()]) || UNCATEGORIZED;
}

export const categoryColor = (key: string | undefined) => COLORS[key ?? UNCATEGORIZED] ?? COLORS[UNCATEGORIZED];

export interface CategoryTotal {
  key: string;
  total: number;
  count: number;
}

/** Totals per category, biggest first. Amounts are positive spend. */
export function totalsByCategory(txns: { category?: string; chargedAmount: number }[]): CategoryTotal[] {
  const map = new Map<string, CategoryTotal>();
  for (const t of txns) {
    const key = t.category ?? UNCATEGORIZED;
    const entry = map.get(key) ?? { key, total: 0, count: 0 };
    entry.total -= t.chargedAmount;
    entry.count += 1;
    map.set(key, entry);
  }
  return [...map.values()]
    .map((e) => ({ ...e, total: Math.round(e.total * 100) / 100 }))
    .sort((a, b) => b.total - a.total);
}
