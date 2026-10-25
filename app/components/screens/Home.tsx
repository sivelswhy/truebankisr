'use client';

import { useState } from 'react';
import { dailyBudget, daysUntil, israelDay, type Txn } from '@/lib/compute.ts';
import { detectRecurring, forecast, isTransfer, ISRAELI_BANKS, movementTotals, onePerPurchase, total, transferParty } from '@/lib/insights.ts';
import { isCardDebit } from '@/lib/compute.ts';
import { useNav, useStore, type Data } from '../App.tsx';
import { useI18n } from '../I18n.tsx';
import { Icon } from '../icons.tsx';
import { Amt, Empty, HeroCard, kindInfo, KindTile, Labeled, LinkRow, MovementRow, Page, Section, Segmented, TxnRow, useTitle } from '../ui.tsx';

/** Calm blue, orange under the alert threshold, red when overdrawn. */
export function mood(s: Data, threshold: number): string {
  if (s.trueBalance < 0) return 'var(--red)';
  return threshold > 0 && s.trueBalance < threshold ? 'var(--orange)' : 'var(--accent)';
}

export function NoData() {
  const { loading, refresh } = useStore();
  const { t } = useI18n();
  return (
    <div className="empty">
      <Icon name="refresh" className={loading ? 'spin' : ''} />
      <h3>{t('No data yet')}</h3>
      <p>{loading ? t('Signing in to Leumi…') : t('Pull down to sign in to Leumi and Max.')}</p>
      {!loading && <button type="button" className="pill-button" onClick={refresh}>{t('Refresh now')}</button>}
    </div>
  );
}

// ---------- Home ----------

export function Home() {
  const { data, prefs } = useStore();
  const { push } = useNav();
  const { t } = useI18n();
  const title = prefs.firstName.trim() ? t('Hello, %@', prefs.firstName.trim()) : t('Hello');
  useTitle(title);
  if (!data) return <Page title={title}><NoData /></Page>;
  const recent = onePerPurchase(data.history);
  const f = forecast(data);
  return (
    <Page title={title}>
      <Hero s={data} />
      {f && (f.income.length > 0 || f.debits.length > 0) && <ForecastRow />}
      <Section header={t('Latest payments')} onSeeAll={recent.length > 5 ? () => push({ s: 'recent' }) : undefined}>
        {recent.length === 0 && <div className="row secondary">{t('No purchases yet.')}</div>}
        {recent.slice(0, 5).map((x) => <TxnRow key={x.id} txn={x} />)}
      </Section>
      {data.bankTxns.length > 0 && (
        <Section header={t('Leumi account')} onSeeAll={data.bankTxns.length > 5 ? () => push({ s: 'movements' }) : undefined}>
          {data.bankTxns.slice(0, 5).map((x) => <MovementRow key={x.id} txn={x} />)}
        </Section>
      )}
    </Page>
  );
}

/** The true balance, time left until the debit and what that leaves per day. Tap for the calculation. */
function Hero({ s }: { s: Data }) {
  const { prefs } = useStore();
  const { push } = useNav();
  const { t, ils, ilsWhole, ago } = useI18n();
  const next = s.nextCharge;
  const days = next ? daysUntil(next.chargeDate) : 0;
  const budget = dailyBudget(s);
  // How far into the billing month we are.
  let progress = 1;
  if (next) {
    const end = Date.parse(`${next.chargeDate}T00:00:00Z`);
    const start = new Date(end);
    start.setUTCMonth(start.getUTCMonth() - 1);
    const today = Date.parse(`${israelDay(new Date())}T00:00:00Z`);
    progress = Math.min(1, Math.max(0, (today - start.getTime()) / (end - start.getTime())));
  }
  const stale = Date.now() - new Date(s.computedAt).getTime() > 3_600_000;
  return (
    <HeroCard tint={mood(s, prefs.alertThreshold)} onClick={() => push({ s: 'calc' })}>
      <div className="caption">
        <span>
          {t('Really available')} {s.demo && <span className="badge">{t('DEMO')}</span>}
        </span>
        <Icon name="chevron" className="chev" />
      </div>
      <div className={`amount${s.trueBalance < 0 ? ' neg' : ''}`}><Amt>{ils(s.trueBalance)}</Amt></div>
      {s.trueBalance < 0 && <p className="warning">{t('You’ll be overdrawn on the debit date unless money comes in first.')}</p>}
      {next && (
        <>
          <div className="gauge"><i style={{ width: `${progress * 100}%` }} /></div>
          <div className="runway">
            <span><Icon name="calendar" />{days === 0 ? t('Max is debited today') : t('%lld day(s) until the debit', days)}</span>
            {budget != null && <Amt>{t('about %@/day', ilsWhole(budget))}</Amt>}
          </div>
        </>
      )}
      <div className={`updated${stale ? ' stale' : ''}`}>
        <Icon name="clock" />
        {t('Updated %@', ago(s.computedAt))}
      </div>
    </HeroCard>
  );
}

/** "Expected on 2 Nov, salary included", under the hero. */
function ForecastRow() {
  const { data } = useStore();
  const { push } = useNav();
  const { t, ils, day } = useI18n();
  const f = forecast(data!)!;
  return (
    <section className="section" style={{ marginTop: 14 }}>
      <div className="group">
        <LinkRow onClick={() => push({ s: 'forecast' })}>
          <Icon name="trend" className="row-icon" />
          <span className="main">
            <span className="title">{t('Expected on %@', day(f.until))}</span>
            <span className="sub">{f.income.length ? t('Salary and regular debits included') : t('Including regular debits')}</span>
          </span>
          <span className="end"><Amt className={f.projectedBalance < 0 ? 'neg' : ''}>{ils(f.projectedBalance)}</Amt></span>
        </LinkRow>
      </div>
    </section>
  );
}

// ---------- Calculation ----------

export function Calculation() {
  const { data } = useStore();
  const { t, ils, day } = useI18n();
  useTitle(t('Calculation'));
  if (!data) return <Page title={t('Calculation')}><NoData /></Page>;
  const converted = data.upcoming.flatMap((u) => u.txns).filter((x) => x.originalCurrency && x.originalCurrency !== 'ILS' && x.chargedCurrency === 'ILS').length;
  return (
    <Page title={t('Calculation')}>
      <Section
        inset={50}
        footer={
          <>
            {data.upcoming.length > 1 && <>{t('With later installments already committed: %@', ils(data.trueBalanceAllKnown))} </>}
            {converted > 0 && <>{t('Includes %lld foreign-currency charge(s) converted at the Bank of Israel rate (estimate).', converted)} </>}
            {data.ignoredForeign.length > 0 && <>{t('%lld foreign-currency charge(s) not included.', data.ignoredForeign.length)} </>}
            {data.nextCharge?.credit && t('Max owes you %@: it comes off the next statement.', ils(data.nextCharge.credit))}
          </>
        }
      >
        <Labeled icon="bank" label={t('Leumi balance')}><Amt>{ils(data.bankBalance)}</Amt></Labeled>
        <Labeled icon="card" label={data.nextCharge ? t('Max · %@', day(data.nextCharge.chargeDate)) : t('Max')}>
          <Amt>{ils(-(data.nextCharge?.total ?? 0))}</Amt>
        </Labeled>
        <div className="row labeled emphasis">
          <Icon name="equal" className="row-icon" />
          <span className="label">{t('Available')}</span>
          <Amt className={data.trueBalance < 0 ? 'neg' : ''}>{ils(data.trueBalance)}</Amt>
        </div>
      </Section>
    </Page>
  );
}

// ---------- Forecast ----------

export function ForecastScreen() {
  const { data } = useStore();
  const { t, ils, day } = useI18n();
  useTitle(t('Forecast'));
  const f = data && forecast(data);
  if (!data || !f) return <Page title={t('Forecast')}><NoData /></Page>;
  const all = detectRecurring(data.bankTxns.filter((x) => !isCardDebit(x)));
  return (
    <Page title={t('Forecast')}>
      <Section plain footer={t('Regular Leumi movements expected before the debit, detected from the last months: same payer or payee, about the same amount, every month.')}>
        <Labeled label={t('Available after Max')}><Amt>{ils(data.trueBalance)}</Amt></Labeled>
        {f.income.map((r) => <Labeled key={r.name} label={r.name}><Amt className="pos">{'+' + ils(r.amount)}</Amt></Labeled>)}
        {f.debits.map((r) => <Labeled key={r.name} label={r.name}><Amt>{ils(r.amount)}</Amt></Labeled>)}
        <div className="row labeled emphasis">
          <span className="label">{t('Expected on %@', day(f.until))}</span>
          <Amt className={f.projectedBalance < 0 ? 'neg' : ''}>{ils(f.projectedBalance)}</Amt>
        </div>
      </Section>
      {all.length > 0 && (
        <Section header={t('Every month on Leumi')}>
          {all.map((r) => <RecurringRow key={r.name + r.amount} name={r.name} next={r.nextDate} amount={r.amount} />)}
        </Section>
      )}
    </Page>
  );
}

/** A recurring movement: name, next date, amount. */
export function RecurringRow({ name, next, amount, onClick }: { name: string; next: string; amount: number; onClick?: () => void }) {
  const { t, ils, day } = useI18n();
  const body = (
    <>
      <span className="tile" style={{ '--c': amount > 0 ? 'var(--green)' : 'var(--indigo)' } as React.CSSProperties}>
        <Icon name={amount > 0 ? 'in' : 'repeat'} />
      </span>
      <span className="main">
        <span className="title">{name}</span>
        <span className="sub">{t('Next around %@', day(next))}</span>
      </span>
      <span className="end"><Amt className={amount > 0 ? 'pos' : ''}>{amount > 0 ? '+' + ils(amount) : ils(-amount)}</Amt></span>
    </>
  );
  return onClick ? <LinkRow onClick={onClick}>{body}</LinkRow> : <div className="row">{body}</div>;
}

// ---------- Every purchase, grouped by day ----------

export function RecentPurchases() {
  const { data } = useStore();
  const { t, ils, weekday } = useI18n();
  useTitle(t('Latest payments'));
  const days = groupByDay(onePerPurchase(data?.history ?? []).slice(0, 300));
  return (
    <Page title={t('Latest payments')}>
      {days.map(([d, list]) => (
        <Section key={d} small header={weekday(d)} side={<Amt>{ils(total(list))}</Amt>}>
          {list.map((x) => <TxnRow key={x.id} txn={x} />)}
        </Section>
      ))}
    </Page>
  );
}

export function groupByDay(txns: Txn[]): [string, Txn[]][] {
  const map = new Map<string, Txn[]>();
  for (const x of txns) {
    const d = israelDay(x.date);
    map.set(d, [...(map.get(d) ?? []), x]);
  }
  return [...map.entries()].sort(([a], [b]) => b.localeCompare(a));
}

// ---------- Leumi movements ----------

type Filter = 'all' | 'in' | 'out' | 'transfers';
const keeps: Record<Filter, (x: Txn) => boolean> = {
  all: () => true,
  in: (x) => x.chargedAmount > 0,
  out: (x) => x.chargedAmount < 0,
  transfers: isTransfer,
};

export function Movements() {
  const { data } = useStore();
  const { t, ils, weekday, day } = useI18n();
  const [filter, setFilter] = useState<Filter>('all');
  const [query, setQuery] = useState('');
  useTitle(t('Leumi account'));
  const all = data?.bankTxns ?? [];
  const q = query.trim().toLowerCase();
  const txns = all.filter((x) => keeps[filter](x) && (!q || [x.description, x.memo ?? ''].some((s) => s.toLowerCase().includes(q))));
  const totals = movementTotals(txns);
  const oldest = all[all.length - 1]?.date;
  return (
    <Page title={t('Leumi account')}>
      <label className="search">
        <Icon name="search" />
        <span className="visually-hidden">{t('Search movements')}</span>
        <input type="search" placeholder={t('Search movements')} value={query} onChange={(e) => setQuery(e.target.value)} />
      </label>
      <Segmented
        label={t('Show')}
        value={filter}
        onChange={setFilter}
        options={[{ id: 'all', label: t('All') }, { id: 'in', label: t('In') }, { id: 'out', label: t('Out') }, { id: 'transfers', label: t('Transfers') }]}
      />
      <section className="section" style={{ marginTop: 14 }}>
        <div className="group">
          <div className="row" style={{ fontWeight: 600, fontSize: 18 }}>
            <span className="main"><span className="sub">{t('In')}</span><Amt className="pos">{'+' + ils(totals.in)}</Amt></span>
            <span className="end"><small>{t('Out')}</small><Amt>{ils(-totals.out)}</Amt></span>
          </div>
        </div>
        {oldest && <p className="footer">{t('Leumi movements since %@.', day(oldest))}</p>}
      </section>
      {txns.length === 0 && <Empty icon="tray" title={t('No movements')} />}
      {groupByDay(txns).map(([d, list]) => (
        <Section key={d} small header={weekday(d)}>
          {list.map((x) => <MovementRow key={x.id} txn={x} />)}
        </Section>
      ))}
    </Page>
  );
}

export function MovementDetail({ id }: { id: string }) {
  const { data } = useStore();
  const { t, ils, fullDate, longDay } = useI18n();
  const txn = data?.bankTxns.find((x) => x.id === id);
  const party = txn && transferParty(txn);
  const title = party?.name ?? txn?.description ?? '';
  useTitle(title);
  if (!txn) return <Page title={t('Leumi account')}><NoData /></Page>;
  const bank = party?.bankCode != null ? ISRAELI_BANKS[party.bankCode] : undefined;
  return (
    <Page title={title}>
      <div className="detail-head">
        <KindTile txn={txn} big />
        <h2>{title}</h2>
        <div className={`big-amount${txn.chargedAmount > 0 ? ' pos' : ''}`}><Amt>{(txn.chargedAmount > 0 ? '+' : '') + ils(txn.chargedAmount)}</Amt></div>
        <div className="when">{t(kindInfo(txn).label)}</div>
      </div>
      {party && (
        <Section
          plain
          small
          header={txn.chargedAmount >= 0 ? t('Sender') : t('Recipient')}
          footer={t('This is everything Leumi gives about the other side, also on its website.')}
        >
          <Labeled label={t('Name')}>{party.name}</Labeled>
          {party.bankCode != null && <Labeled label={t('Bank')}>{bank ? `${bank} (${party.bankCode})` : party.bankCode}</Labeled>}
          {party.branch && <Labeled label={t('Branch')}><span className="num">{party.branch}</span></Labeled>}
          {party.account && <Labeled label={t('Account')}><span className="num">{party.account}</span></Labeled>}
        </Section>
      )}
      <Section plain footer={txn.status === 'pending' ? t('Today’s movement: Leumi may still adjust it.') : undefined}>
        <Labeled label={t('Date')}>{fullDate(txn.date)}</Labeled>
        {txn.valueDate && <Labeled label={t('Value date')}>{longDay(txn.valueDate)}</Labeled>}
        <Labeled label={t('Description')}>{txn.description}</Labeled>
        {txn.memo && <Labeled label={t('Details')}>{txn.memo}</Labeled>}
        {txn.runningBalance != null && <Labeled label={t('Balance after')}><Amt>{ils(txn.runningBalance)}</Amt></Labeled>}
        <Labeled label={t('Reference')}><span className="num">{txn.id}</span></Labeled>
      </Section>
    </Page>
  );
}
