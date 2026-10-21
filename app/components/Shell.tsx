'use client';

import { useEffect } from 'react';
import { NavProvider, StoreProvider, TabBar, useNav, useStore, type Data, type Route } from './App.tsx';
import { PullToRefresh } from './PullToRefresh.tsx';
import { Charges, CategoryDetail } from './screens/Charges.tsx';
import { Calculation, ForecastScreen, Home, mood, MovementDetail, Movements, RecentPurchases } from './screens/Home.tsx';
import { Insights, MonthComparison, Subscriptions, Wealth } from './screens/Insights.tsx';
import { Profile } from './screens/Profile.tsx';
import { Merchant, PurchaseDetail } from './screens/Purchase.tsx';
import { Spending } from './screens/Spending.tsx';

/** Signed in: one tab per question, pages pushed on top, profile as a sheet. */
export function Shell({ initial, onSignOut }: { initial: Data | null; onSignOut: () => void }) {
  return (
    <StoreProvider initial={initial} onSignOut={onSignOut}>
      <NavProvider>
        <Screens />
      </NavProvider>
    </StoreProvider>
  );
}

function screen(tab: string, r: Route) {
  switch (r.s) {
    case 'tab':
      return tab === 'home' ? <Home /> : tab === 'charges' ? <Charges /> : tab === 'spending' ? <Spending /> : <Insights />;
    case 'calc': return <Calculation />;
    case 'forecast': return <ForecastScreen />;
    case 'recent': return <RecentPurchases />;
    case 'movements': return <Movements />;
    case 'movement': return <MovementDetail id={r.id} />;
    case 'txn': return <PurchaseDetail id={r.id} />;
    case 'merchant': return <Merchant k={r.key} name={r.name} />;
    case 'category': return <CategoryDetail k={r.key} ids={r.ids} caption={r.caption} />;
    case 'month': return <MonthComparison />;
    case 'subscriptions': return <Subscriptions />;
    case 'wealth': return <Wealth />;
  }
}

function Screens() {
  const { tab, stack, profile } = useNav();
  const { data, prefs, loading, refresh } = useStore();
  const route = stack[stack.length - 1];

  // "Hide amounts" blurs every amount; the glow behind the screen follows the balance.
  useEffect(() => {
    document.body.classList.toggle('private', prefs.hideAmounts);
    document.body.style.setProperty('--page-tint', data && tab === 'home' ? mood(data, prefs.alertThreshold) : 'var(--accent)');
  }, [prefs.hideAmounts, prefs.alertThreshold, data, tab]);

  const content = screen(tab, route);
  return (
    <>
      {route.s === 'tab' ? <PullToRefresh refreshing={loading} onRefresh={refresh}>{content}</PullToRefresh> : content}
      <TabBar />
      {profile && <Profile />}
    </>
  );
}
