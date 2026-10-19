// Max category names (Hebrew, as returned by Max's API) → translations + colour.
// Source: https://onlinelcapi.max.co.il/api/contents/getCategories

export type Lang = 'en' | 'fr';

interface Category {
  key: string;
  color: string;
  en: string;
  fr: string;
}

const CATEGORIES: Record<string, Category> = {
  'ביטוח': { key: 'insurance', color: '#2550ff', en: 'Insurance', fr: 'Assurance' },
  'דלק, חשמל וגז': { key: 'energy', color: '#3dc0e9', en: 'Fuel, power & gas', fr: 'Carburant, électricité et gaz' },
  'אופנה': { key: 'fashion', color: '#00a3ad', en: 'Fashion', fr: 'Mode' },
  'עיצוב הבית': { key: 'home', color: '#c20017', en: 'Home & DIY', fr: 'Maison et bricolage' },
  'טיסות ותיירות': { key: 'travel', color: '#b200df', en: 'Flights & travel', fr: 'Vols et voyages' },
  'חשמל ומחשבים': { key: 'electronics', color: '#7800f7', en: 'Electronics', fr: 'Électronique et informatique' },
  'מזון וצריכה': { key: 'groceries', color: '#ff3f9b', en: 'Groceries', fr: 'Courses' },
  'ספרים ודפוס': { key: 'books', color: '#ff2a11', en: 'Books & print', fr: 'Livres et papeterie' },
  'פנאי, בידור וספורט': { key: 'leisure', color: '#ff7121', en: 'Leisure & sport', fr: 'Loisirs et sport' },
  'תחבורה ורכבים': { key: 'transport', color: '#009950', en: 'Transport & cars', fr: 'Transport et voiture' },
  'עירייה וממשלה': { key: 'government', color: '#f9b300', en: 'City & government', fr: 'Mairie et administration' },
  'רפואה ובתי מרקחת': { key: 'health', color: '#879aff', en: 'Health & pharmacy', fr: 'Santé et pharmacie' },
  'שירותי תקשורת': { key: 'telecom', color: '#b6c700', en: 'Phone & internet', fr: 'Téléphone et internet' },
  'שונות': { key: 'other', color: '#a1a1a6', en: 'Other', fr: 'Divers' },
  'מוצרי אשראי m_a_x': { key: 'max', color: '#002aa9', en: 'Max products', fr: 'Produits Max' },
  'מוצרי m_a_x': { key: 'max', color: '#002aa9', en: 'Max products', fr: 'Produits Max' },
  'משיכת מזומן': { key: 'cash', color: '#1bc200', en: 'Cash withdrawal', fr: 'Retrait d’espèces' },
  'העברת כספים': { key: 'transfer', color: '#aa82ff', en: 'Money transfer', fr: 'Virement' },
  'חיות מחמד': { key: 'pets', color: '#922108', en: 'Pets', fr: 'Animaux' },
  'קוסמטיקה וטיפוח': { key: 'beauty', color: '#ff8dab', en: 'Beauty & care', fr: 'Beauté et soins' },
  'מסעדות, קפה וברים': { key: 'restaurants', color: '#13e2bf', en: 'Restaurants & bars', fr: 'Restaurants, cafés et bars' },
  'מט"ח': { key: 'fx', color: '#d9a364', en: 'Foreign currency', fr: 'Devises' },
};

const UNKNOWN: Category = { key: 'uncategorized', color: '#a1a1a6', en: 'Uncategorized', fr: 'Sans catégorie' };

export function category(name: string | undefined, lang: Lang): { key: string; color: string; label: string } {
  const c = (name && CATEGORIES[name.trim()]) || null;
  if (c) return { key: c.key, color: c.color, label: c[lang] };
  // Unknown category: show Max's own name rather than hide it.
  return { key: name ? `raw:${name}` : UNKNOWN.key, color: UNKNOWN.color, label: name || UNKNOWN[lang] };
}

export interface CategoryTotal {
  key: string;
  label: string;
  color: string;
  total: number;
  count: number;
}

// Totals per category, biggest first. Amounts are positive spend.
export function totalsByCategory(txns: { category?: string; chargedAmount: number }[], lang: Lang): CategoryTotal[] {
  const map = new Map<string, CategoryTotal>();
  for (const t of txns) {
    const c = category(t.category, lang);
    const entry = map.get(c.key) ?? { ...c, total: 0, count: 0 };
    entry.total += -t.chargedAmount;
    entry.count += 1;
    map.set(c.key, entry);
  }
  return [...map.values()]
    .map((e) => ({ ...e, total: Math.round(e.total * 100) / 100 }))
    .sort((a, b) => b.total - a.total);
}
