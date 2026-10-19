'use client';

import { useEffect, useRef, useState } from 'react';
import { category, totalsByCategory } from '@/lib/categories.ts';
import type { TrueBalance, Txn, UpcomingCharge } from '@/lib/compute.ts';
import { useI18n } from './I18n.tsx';
import { PullToRefresh } from './PullToRefresh.tsx';

export type Data = TrueBalance & { demo?: boolean };

// Opening the dashboard refreshes data older than this.
const STALE_MS = 15 * 60_000;

export function Dashboard({ initial, onSignOut }: { initial: Data | null; onSignOut: () => void }) {
  const i = useI18n();
  const { d, t, ils, day } = i;
  const [data, setData] = useState<Data | null>(initial);
  const [loading, setLoading] = useState(false);
  const [errors, setErrors] = useState<Record<string, string> | null>(null);
  const [scrolled, setScrolled] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [signingOut, setSigningOut] = useState(false);
  const titleRef = useRef<HTMLHeadingElement>(null);

  // Large title collapses into the bar once it scrolls under it.
  useEffect(() => {
    const io = new IntersectionObserver(([e]) => setScrolled(!e.isIntersecting), { rootMargin: '-52px 0px 0px 0px' });
    if (titleRef.current) io.observe(titleRef.current);
    return () => io.disconnect();
  }, []);

  // Stay up to date without asking: refresh on open when the data is old.
  useEffect(() => {
    if (!initial || Date.now() - new Date(initial.computedAt).getTime() > STALE_MS) refresh();
  }, []);

  async function refresh() {
    if (loading) return;
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
    } catch {
      setErrors({ general: 'SERVER_DOWN' });
    } finally {
      setLoading(false);
    }
  }

  async function signOut() {
    setSigningOut(true);
    await fetch('/api/session', { method: 'DELETE' }).catch(() => {});
    onSignOut();
  }

  const negative = data ? data.trueBalance < 0 : false;
  const errorText =
    errors &&
    Object.entries(errors)
      .map(([who, code]) => i.error(code, who === 'leumi' ? 'Leumi' : who === 'max' ? 'Max' : ''))
      .join(' ');

  return (
    <>
      <header className={`bar ${scrolled ? 'scrolled' : ''}`}>
        <button className="text-button" onClick={() => i.setLang(i.lang === 'fr' ? 'en' : 'fr')} lang={i.lang === 'fr' ? 'en' : 'fr'}>
          {d.language}
        </button>
        <span className="bar-title">{d.appName}</span>
        <button className="icon-button" onClick={refresh} disabled={loading} aria-label={d.refresh}>
          <svg viewBox="0 0 24 24" width="20" height="20" className={loading ? 'spin' : ''} aria-hidden>
            <path d="M20 12a8 8 0 1 1-2.34-5.66M20 4v4h-4" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </button>
      </header>

      <PullToRefresh refreshing={loading} onRefresh={refresh}>
        <main>
          <h1 ref={titleRef} className="large-title">
            {d.appName}
            {data?.demo && <span className="badge">{d.demo}</span>}
          </h1>

          {errorText && (
            <div className="banner" role="alert">
              <strong>{d.couldntRefresh}</strong> {errorText}
            </div>
          )}

          {data ? (
            <>
              <section className="card hero-card" aria-live="polite">
                <p className="caption">
                  {data.nextCharge ? t(d.reallyAvailableAfter, { date: day(data.nextCharge.chargeDate) }) : d.reallyAvailable}
                </p>
                <p className={`hero ${negative ? 'neg' : ''}`}>{ils(data.trueBalance)}</p>
                {negative && <p className="hero-sub neg">{d.overdrawn}</p>}
              </section>

              <ul className="group">
                <li>
                  <span>{d.leumiBalance}</span>
                  <span className="value">{ils(data.bankBalance)}</span>
                </li>
                <li>
                  <span>
                    {d.max} {data.nextCharge && <span className="secondary">· {day(data.nextCharge.chargeDate)}</span>}
                  </span>
                  <span className="value">{ils(-(data.nextCharge?.total ?? 0))}</span>
                </li>
                <li className="emphasis">
                  <span>{d.available}</span>
                  <span className={`value ${negative ? 'neg' : ''}`}>{ils(data.trueBalance)}</span>
                </li>
              </ul>

              {(data.upcoming.length > 1 || data.ignoredForeign.length > 0) && (
                <p className="footnote">
                  {data.upcoming.length > 1 && <>{t(d.withLater, { amount: ils(data.trueBalanceAllKnown) })} </>}
                  {data.ignoredForeign.length > 0 && t(d.foreign, { count: data.ignoredForeign.length })}
                </p>
              )}

              {data.nextCharge && <CategoryBreakdown charge={data.nextCharge} />}

              {data.upcoming.map((c) => (
                <section key={c.chargeDate}>
                  <h2 className="group-header">
                    <span>{t(d.debited, { date: day(c.chargeDate) })}</span>
                    <span>{ils(c.total)}</span>
                  </h2>
                  <ul className="group">
                    {c.txns.map((txn, n) => (
                      <TxnRow key={n} txn={txn} />
                    ))}
                  </ul>
                </section>
              ))}

              <p className="footnote center">
                {loading ? d.fetching : `${t(d.updated, { time: i.ago(data.computedAt) })} · ${d.pullToRefresh}`}
              </p>
            </>
          ) : (
            <section className="card empty">
              <p>{d.noData}</p>
              <p className="secondary">{loading ? d.noDataLoading : d.noDataHint}</p>
            </section>
          )}

          <ul className="group actions">
            {confirming ? (
              <>
                <li>
                  <button className="row-button destructive" onClick={signOut} disabled={signingOut}>
                    {signingOut ? d.disconnecting : d.disconnectConfirm}
                  </button>
                </li>
                <li>
                  <button className="row-button" onClick={() => setConfirming(false)} disabled={signingOut}>
                    {d.cancel}
                  </button>
                </li>
              </>
            ) : (
              <li>
                <button className="row-button destructive" onClick={() => setConfirming(true)}>
                  {data?.demo ? d.exitDemo : d.disconnect}
                </button>
              </li>
            )}
          </ul>
        </main>
      </PullToRefresh>
    </>
  );
}

function TxnRow({ txn }: { txn: Txn }) {
  const { d, t, ils, day, lang } = useI18n();
  const c = category(txn.category, lang);
  return (
    <li>
      <span className="cat-dot" style={{ background: c.color }} aria-hidden />
      <div className="txn">
        <span className="txn-name">{txn.description}</span>
        <span className="secondary">
          {day(txn.date)} · {c.label}
          {txn.installments && ` · ${t(d.installment, { n: txn.installments.number, total: txn.installments.total })}`}
          {txn.status === 'pending' && ` · ${d.pending}`}
        </span>
      </div>
      <span className="value">{ils(-txn.chargedAmount)}</span>
    </li>
  );
}

// Where the next debit goes, by category, with proportional bars.
function CategoryBreakdown({ charge }: { charge: UpcomingCharge }) {
  const { d, ils, lang } = useI18n();
  const totals = totalsByCategory(charge.txns, lang);
  const biggest = totals[0]?.total || 1;
  return (
    <section>
      <h2 className="group-header">
        <span>{d.byCategory}</span>
      </h2>
      <ul className="group">
        {totals.map((c) => (
          <li key={c.key} className="cat-row">
            <span className="cat-dot" style={{ background: c.color }} aria-hidden />
            <div className="cat-main">
              <div className="cat-line">
                <span className="txn-name">{c.label}</span>
                <span className="value">{ils(c.total)}</span>
              </div>
              <div className="cat-bar" aria-hidden>
                <span style={{ width: `${Math.max(2, (c.total / biggest) * 100)}%`, background: c.color }} />
              </div>
            </div>
          </li>
        ))}
      </ul>
    </section>
  );
}
