'use client';

import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { detectLang, dictionaries, format, formatters, type ErrorCode, type Lang } from '@/lib/i18n.ts';

function build(lang: Lang, setLang: (l: Lang) => void) {
  const d = dictionaries[lang];
  return {
    lang,
    setLang,
    d,
    t: (template: string, params?: Record<string, string | number>) => format(template, params),
    error: (code: string | undefined, name = '') => format(d.err[(code as ErrorCode) in d.err ? (code as ErrorCode) : 'UNKNOWN'], { name }),
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
    document.title = dictionaries[lang].appName;
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
