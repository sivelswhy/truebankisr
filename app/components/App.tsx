'use client';

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import type { Prefs } from '@/lib/prefs.ts';
import type { Snapshot } from '@/lib/service.ts';
import { CurrencyProvider, useI18n } from './I18n.tsx';
import { Icon, type IconName } from './icons.tsx';

export type Data = Snapshot;

// Same as DEFAULT_PREFS in lib/prefs.ts (that module reads files, so it stays on the server).
const DEFAULT_PREFS: Prefs = { firstName: '', hideAmounts: false, alertThreshold: 0, budgets: {}, notes: {}, currency: '', currencyFirst: false };

// ---------- Data: snapshot, refresh, preferences ----------

// Opening the app (or coming back to it) refreshes data older than this.
const STALE_MS = 15 * 60_000;

interface Store {
  data: Data | null;
  loading: boolean;
  errors: Record<string, string> | null;
  refresh: () => void;
  prefs: Prefs;
  setPrefs: (patch: Partial<Prefs>) => void;
  signOut: () => Promise<void>;
}

const StoreCtx = createContext<Store | null>(null);
export const useStore = () => useContext(StoreCtx)!;

export function StoreProvider({ initial, onSignOut, children }: { initial: Data | null; onSignOut: () => void; children: ReactNode }) {
  const { t, ilsWhole, day } = useI18n();
  const [data, setData] = useState<Data | null>(initial);
  const [loading, setLoading] = useState(false);
  const [errors, setErrors] = useState<Record<string, string> | null>(null);
  const [prefs, setPrefsState] = useState<Prefs>(DEFAULT_PREFS);
  const loadingRef = useRef(false);
  const prefsRef = useRef(prefs);
  prefsRef.current = prefs;

  useEffect(() => {
    fetch('/api/prefs').then((r) => r.json()).then(setPrefsState).catch(() => {});
  }, []);

  const setPrefs = useCallback((patch: Partial<Prefs>) => {
    setPrefsState((p) => ({ ...p, ...patch }));
    fetch('/api/prefs', { method: 'PUT', headers: { 'content-type': 'application/json' }, body: JSON.stringify(patch) }).catch(() => {});
  }, []);

  // Like the iPhone's alert: below the threshold (or below zero) after a refresh.
  const notify = useCallback(
    (s: Data) => {
      const threshold = prefsRef.current.alertThreshold;
      const low = s.trueBalance < 0 || (threshold > 0 && s.trueBalance < threshold);
      if (!low || typeof Notification === 'undefined' || Notification.permission !== 'granted') return;
      const body = s.nextCharge
        ? t('After Max is debited on %@, your balance will be %@.', day(s.nextCharge.chargeDate), ilsWhole(s.trueBalance))
        : ilsWhole(s.trueBalance);
      new Notification(t('Really available'), { body, icon: '/icon.png', tag: 'balance' });
    },
    [t, ilsWhole, day],
  );

  const refresh = useCallback(async () => {
    if (loadingRef.current) return;
    loadingRef.current = true;
    setLoading(true);
    setErrors(null);
    try {
      const res = await fetch('/api/balance', { method: 'POST' });
      const body = await res.json();
      if (!res.ok) {
        setErrors(body.errors ?? { general: 'UNKNOWN' });
        navigator.vibrate?.([20, 40, 20]);
        return;
      }
      setData(body);
      notify(body);
    } catch {
      setErrors({ general: 'SERVER_DOWN' });
    } finally {
      loadingRef.current = false;
      setLoading(false);
    }
  }, [notify]);

  // Stay up to date without asking: refresh on open and on return when the data is old.
  const dataRef = useRef(data);
  dataRef.current = data;
  useEffect(() => {
    const check = () => {
      const d = dataRef.current;
      if (document.visibilityState === 'visible' && (!d || Date.now() - new Date(d.computedAt).getTime() > STALE_MS)) refresh();
    };
    check();
    document.addEventListener('visibilitychange', check);
    return () => document.removeEventListener('visibilitychange', check);
  }, [refresh]);

  // R refreshes, like ⌘R would reload.
  useEffect(() => {
    const key = (e: KeyboardEvent) => {
      const typing = (e.target as HTMLElement)?.closest?.('input, textarea, select, [contenteditable]');
      if (!typing && !e.metaKey && !e.ctrlKey && !e.altKey && e.key.toLowerCase() === 'r') refresh();
    };
    window.addEventListener('keydown', key);
    return () => window.removeEventListener('keydown', key);
  }, [refresh]);

  const signOut = useCallback(async () => {
    await fetch('/api/session', { method: 'DELETE' }).catch(() => {});
    onSignOut();
  }, [onSignOut]);

  const value = useMemo(() => ({ data, loading, errors, refresh, prefs, setPrefs, signOut }), [data, loading, errors, refresh, prefs, setPrefs, signOut]);
  const rate = prefs.currency ? data?.fxRates?.[prefs.currency] : undefined;
  return (
    <StoreCtx.Provider value={value}>
      <CurrencyProvider fx={rate ? { code: prefs.currency, rate, first: prefs.currencyFirst } : undefined}>{children}</CurrencyProvider>
    </StoreCtx.Provider>
  );
}

// ---------- Navigation: a stack per tab, like a NavigationStack in each Tab ----------

export type TabID = 'home' | 'charges' | 'spending' | 'insights';

export type Route =
  | { s: 'tab' }
  | { s: 'calc' }
  | { s: 'forecast' }
  | { s: 'recent' }
  | { s: 'movements' }
  | { s: 'movement'; id: string }
  | { s: 'txn'; id: string }
  | { s: 'merchant'; key: string; name: string }
  | { s: 'category'; key: string; ids: string[]; caption: string }
  | { s: 'month' }
  | { s: 'subscriptions' }
  | { s: 'wealth' };

interface Nav {
  tab: TabID;
  stack: Route[];
  motion: 'push' | 'pop' | 'tab' | null;
  setTab: (t: TabID) => void;
  push: (r: Route) => void;
  back: () => void;
  profile: boolean;
  setProfile: (open: boolean) => void;
}

const NavCtx = createContext<Nav | null>(null);
export const useNav = () => useContext(NavCtx)!;

export const TABS: { id: TabID; label: string; icon: IconName }[] = [
  { id: 'home', label: 'Home', icon: 'house' },
  { id: 'charges', label: 'Charges', icon: 'card' },
  { id: 'spending', label: 'Spending', icon: 'chart' },
  { id: 'insights', label: 'Insights', icon: 'bulb' },
];

export function NavProvider({ children }: { children: ReactNode }) {
  const [tab, setTabState] = useState<TabID>('home');
  const [stacks, setStacks] = useState<Record<TabID, Route[]>>({ home: [{ s: 'tab' }], charges: [{ s: 'tab' }], spending: [{ s: 'tab' }], insights: [{ s: 'tab' }] });
  const [motion, setMotion] = useState<Nav['motion']>(null);
  const [profile, setProfile] = useState(false);
  const tabRef = useRef(tab);
  tabRef.current = tab;

  // The browser's Back button pops the current page, like the iOS back swipe.
  useEffect(() => {
    const pop = () => {
      setMotion('pop');
      setStacks((s) => (s[tabRef.current].length > 1 ? { ...s, [tabRef.current]: s[tabRef.current].slice(0, -1) } : s));
    };
    window.addEventListener('popstate', pop);
    return () => window.removeEventListener('popstate', pop);
  }, []);

  const push = useCallback((r: Route) => {
    setMotion('push');
    setStacks((s) => ({ ...s, [tabRef.current]: [...s[tabRef.current], r] }));
    history.pushState({ page: true }, '');
    window.scrollTo(0, 0);
  }, []);

  const back = useCallback(() => history.back(), []);

  // Tapping the current tab goes back to its first screen, like iOS.
  const setTab = useCallback((t: TabID) => {
    setMotion('tab');
    if (t === tabRef.current) setStacks((s) => ({ ...s, [t]: [{ s: 'tab' }] }));
    setTabState(t);
    window.scrollTo(0, 0);
  }, []);

  const value = useMemo(
    () => ({ tab, stack: stacks[tab], motion, setTab, push, back, profile, setProfile }),
    [tab, stacks, motion, setTab, push, back, profile],
  );
  return <NavCtx.Provider value={value}>{children}</NavCtx.Provider>;
}

export function TabBar() {
  const { t } = useI18n();
  const { tab, setTab } = useNav();
  return (
    <nav className="tabbar">
      {TABS.map((x) => (
        <button key={x.id} type="button" onClick={() => setTab(x.id)} aria-current={tab === x.id ? 'page' : undefined}>
          <Icon name={x.icon} />
          <span>{t(x.label)}</span>
        </button>
      ))}
    </nav>
  );
}
