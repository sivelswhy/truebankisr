// Copies the iPhone app's translations (Localizable.xcstrings) into
// lib/strings.json, so the web app uses the same wording in every language.
// Run `npm run strings` after changing the iOS strings.
import { readFileSync, writeFileSync } from 'node:fs';

const source = new URL('../ios/TrueBalance/Resources/Localizable.xcstrings', import.meta.url);
const target = new URL('../lib/strings.json', import.meta.url);
const langs = ['en', 'fr', 'he', 'ru', 'ar'];

const catalog = JSON.parse(readFileSync(source, 'utf8')).strings;

function value(unit) {
  if (unit?.stringUnit) return unit.stringUnit.value;
  const plural = unit?.variations?.plural;
  if (plural) return Object.fromEntries(Object.entries(plural).map(([k, v]) => [k, v.stringUnit.value]));
  return undefined;
}

const out = {};
for (const [key, entry] of Object.entries(catalog)) {
  const row = {};
  for (const lang of langs) {
    const v = value(entry.localizations?.[lang]);
    // English is the key itself unless it's a plural or the catalog says otherwise.
    if (v !== undefined && !(lang === 'en' && v === key)) row[lang] = v;
  }
  if (Object.keys(row).length) out[key] = row;
}

writeFileSync(target, JSON.stringify(out, null, 1) + '\n');
console.log(`${Object.keys(out).length} strings → lib/strings.json`);
