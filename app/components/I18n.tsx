'use client';

import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { categoryColor } from '@/lib/categories.ts';
import { detectLang, errorText, formatters, isRTL, L, type Lang } from '@/lib/i18n.ts';

function build(lang: Lang, setLang: (l: Lang) => void) {
  return {
    lang,
    setLang,
    rtl: isRTL(lang),
    /** The iPhone app's string for `key`, in the current language. */
    t: (key: string, ...args: (string | number)[]) => L(lang, key, ...args),
    error: (code: string | undefined, name = '') => errorText(lang, code, name),
    category: (key: string | undefined) => L(lang, `category.${key ?? 'uncategorized'}`),
    categoryColor,
    ...formatters(lang),
  };
}

type I18n = ReturnType<typeof build>;

const Ctx = createContext<I18n | null>(null);

export function I18nProvider({ children }: { children: ReactNode }) {
  const [lang, setLangState] = useState<Lang>('en');

  useEffect(() => setLangState(detectLang()), []);
  useEffect(() => {
    document.documentElement.lang = lang;
    document.documentElement.dir = isRTL(lang) ? 'rtl' : 'ltr';
  }, [lang]);

  const value = useMemo(
    () =>
      build(lang, (l) => {
        setLangState(l);
        try {
          localStorage.setItem('lang', l);
        } catch {}
      }),
    [lang],
  );
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useI18n(): I18n {
  const v = useContext(Ctx);
  if (!v) throw new Error('useI18n outside I18nProvider');
  return v;
}
