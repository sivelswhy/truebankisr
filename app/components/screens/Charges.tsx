'use client';

import { useState } from 'react';
import { totalsByCategory } from '@/lib/categories.ts';
import { daysUntil, type Txn } from '@/lib/compute.ts';
import { useNav, useStore } from '../App.tsx';
import { useI18n } from '../I18n.tsx';
import { Icon } from '../icons.tsx';
import { Amt, CategoryTile, Donut, Empty, HeroCard, LinkRow, Page, Section, TxnRow, useTitle, Money } from '../ui.tsx';
import { NoData } from './Home.tsx';

export function Charges() {
  const { data } = useStore();
  const { t, day, ils, ilsWhole, weekday, category } = useI18n();
  const [query, setQuery] = useState('');
  useTitle(t('Charges'));
  if (!data) return <Page title={t('Charges')}><NoData /></Page>;

  const q = query.trim().toLowerCase();
  const matches = q
    ? data.upcoming.flatMap((c) => c.txns.map((x) => [c.chargeDate, x] as const))
      .filter(([, x]) => x.description.toLowerCase().includes(q) || category(x.category).toLowerCase().includes(q))
    : [];
  const next = data.nextCharge;
  const max = Math.max(...data.upcoming.map((u) => u.total), 1);

  return (
    <Page title={t('Charges')}>
      <label className="search">
        <Icon name="search" />
        <span className="visually-hidden">{t('Search charges')}</span>
        <input type="search" placeholder={t('Search charges')} value={query} onChange={(e) => setQuery(e.target.value)} />
      </label>

      {q ? (
        matches.length === 0 ? <Empty icon="search" title={t('No results')} /> : (
          <Section header={t('%lld result(s)', matches.length)} footer={<Amt>{t('Total: %@', ils(matches.reduce((s, [, x]) => s - x.chargedAmount, 0)))}</Amt>}>
            {matches.map(([d, x]) => <TxnRow key={x.id} txn={x} debitDay={d} />)}
          </Section>
        )
      ) : data.upcoming.length === 0 ? (
        <Empty icon="checkCircle" title={t('Nothing to debit')} text={t('No Max charge is waiting to be debited.')} />
      ) : (
        <>
          {next && (
            <HeroCard tint="var(--indigo)">
              <div className="caption"><span>{t('Next Max debit')}</span></div>
              <div className="amount medium"><Money n={next.total} /></div>
              <div className="meta">
                <Icon name="calendar" />
                <span>{weekday(next.chargeDate)}</span>
                <span>·</span>
                <span>{daysUntil(next.chargeDate) === 0 ? t('Max is debited today') : t('%lld day(s) until the debit', daysUntil(next.chargeDate))}</span>
              </div>
              <div className="meta" style={{ marginTop: 2 }}>{t('%lld purchase(s)', next.txns.length)}</div>
            </HeroCard>
          )}

          {data.upcoming.length > 1 && (
            <Section header={t('Upcoming debits')}>
              <div className="chart-cell">
                <div className="bars">
                  {data.upcoming.map((u, i) => (
                    <div className="bar" key={u.chargeDate}>
                      <small className="amt">{ilsWhole(u.total)}</small>
                      <i className={i === 0 ? 'on' : ''} style={{ height: `${Math.max(4, (u.total / max) * 100)}%` }} />
                      <small>{day(u.chargeDate)}</small>
                    </div>
                  ))}
                </div>
              </div>
            </Section>
          )}

          {next && <CategoryBreakdown txns={next.txns} caption={t('Debited %@', day(next.chargeDate))} />}

          {data.upcoming.map((c) => (
            <Section key={c.chargeDate} header={t('Debited %@', day(c.chargeDate))} side={<Money n={c.total} />}>
              {c.txns.map((x) => <TxnRow key={x.id} txn={x} />)}
            </Section>
          ))}
        </>
      )}
    </Page>
  );
}

/** Where the money goes: a donut (tap a slice) and its legend, each row opening the category. */
export function CategoryBreakdown({ txns, caption }: { txns: Txn[]; caption: string }) {
  const { push } = useNav();
  const { t, category, ils, percent } = useI18n();
  const totals = totalsByCategory(txns).filter((c) => c.total > 0);
  const sum = totals.reduce((s, c) => s + c.total, 0);
  if (!totals.length) return null;
  const open = (key: string) => push({ s: 'category', key, ids: txns.map((x) => x.id), caption });
  return (
    <Section header={t('By category')} footer={caption}>
      <Donut totals={totals} onPick={open} />
      {totals.map((c) => (
        <LinkRow key={c.key} onClick={() => open(c.key)}>
          <CategoryTile k={c.key} />
          <span className="main"><span className="title">{category(c.key)}</span></span>
          <span className="end">
            <Money n={c.total} />
            <small>{percent(c.total / sum)}</small>
          </span>
        </LinkRow>
      ))}
    </Section>
  );
}

export function CategoryDetail({ k, ids, caption }: { k: string; ids: string[]; caption: string }) {
  const { data } = useStore();
  const { category, ils } = useI18n();
  useTitle(category(k));
  const wanted = new Set(ids);
  const all = [...(data?.upcoming.flatMap((u) => u.txns) ?? []), ...(data?.history ?? [])];
  const seen = new Set<string>();
  const txns = all.filter((x) => wanted.has(x.id) && (x.category ?? 'uncategorized') === k && !seen.has(x.id) && (seen.add(x.id), true));
  return (
    <Page title={category(k)}>
      <Section footer={caption} header={category(k)} side={<Money n={txns.reduce((s, x) => s - x.chargedAmount, 0)} />}>
        {txns.map((x) => <TxnRow key={x.id} txn={x} />)}
      </Section>
    </Page>
  );
}
