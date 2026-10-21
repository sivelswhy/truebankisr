'use client';

import { useState } from 'react';
import { israelDay } from '@/lib/compute.ts';
import { addDays, addMonths, buckets, csv, monthStart, purchases, total } from '@/lib/insights.ts';
import { useStore } from '../App.tsx';
import { useI18n } from '../I18n.tsx';
import { Icon } from '../icons.tsx';
import { Amt, Chips, Curve, Empty, HeroCard, Labeled, Page, Section, TxnRow, useTitle } from '../ui.tsx';
import { CategoryBreakdown } from './Charges.tsx';
import { NoData } from './Home.tsx';

type Preset = 'week' | 'month30' | 'thisMonth' | 'lastMonth' | 'custom';

function range(p: Exclude<Preset, 'custom'>, today = israelDay(new Date())): [string, string] {
  switch (p) {
    case 'week': return [addDays(today, -6), today];
    case 'month30': return [addDays(today, -29), today];
    case 'thisMonth': return [monthStart(today), today];
    case 'lastMonth': {
      const start = addMonths(monthStart(today), -1);
      return [start, addDays(monthStart(today), -1)];
    }
  }
}

/** Card spending over any period: total, running curve, categories, purchases, CSV. */
export function Spending() {
  const { data, prefs } = useStore();
  const { t, ils, ilsWhole, day, longDay } = useI18n();
  const [preset, setPreset] = useState<Preset>('thisMonth');
  const [[from, to], setRange] = useState(() => range('thisMonth'));
  useTitle(t('Spending'));
  if (!data) return <Page title={t('Spending')}><NoData /></Page>;

  const txns = purchases(data.history, from, to);
  const sum = total(txns);
  const days = Math.max(1, Math.round((Date.parse(to) - Date.parse(from)) / 86_400_000) + 1);
  let running = 0;
  const curve = buckets(txns, from, to, 'day').map((b) => (running += b.total));
  const labels = buckets(txns, from, to, 'day').map((b) => day(b.start));
  const oldest = data.history[data.history.length - 1]?.date;
  const caption = `${day(from)} – ${longDay(to)}`;

  const pick = (p: Preset) => {
    setPreset(p);
    if (p !== 'custom') setRange(range(p));
  };

  const download = () => {
    // BOM so Excel opens the Hebrew merchant names as UTF-8.
    const blob = new Blob(['﻿' + csv(txns, prefs.notes)], { type: 'text/csv;charset=utf-8' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `truebalance-${from}_${to}.csv`;
    a.click();
    URL.revokeObjectURL(a.href);
  };

  return (
    <Page title={t('Spending')}>
      <Chips<Preset>
        value={preset}
        onChange={pick}
        options={[
          { id: 'week', label: t('7 days') },
          { id: 'month30', label: t('30 days') },
          { id: 'thisMonth', label: t('This month') },
          { id: 'lastMonth', label: t('Last month') },
          { id: 'custom', label: t('Custom'), icon: 'calendar' },
        ]}
      />
      {preset === 'custom' && (
        <Section plain>
          <Labeled label={t('From')}>
            <input className="field" type="date" value={from} max={to} onChange={(e) => e.target.value && setRange([e.target.value, to])} />
          </Labeled>
          <Labeled label={t('To')}>
            <input className="field" type="date" value={to} min={from} max={israelDay(new Date())} onChange={(e) => e.target.value && setRange([from, e.target.value])} />
          </Labeled>
        </Section>
      )}

      <section className="section" style={{ marginTop: 16 }}>
        <HeroCard>
          <div className="caption"><span>{t('Card spending')}</span></div>
          <div className="amount medium"><Amt>{ils(sum)}</Amt></div>
          <div className="meta">
            <span>{t('%lld purchase(s)', txns.length)}</span>
            <span>·</span>
            <Amt>{t('about %@/day', ilsWhole(sum / days))}</Amt>
          </div>
          {txns.length > 0 && <Curve points={curve} labels={labels} />}
        </HeroCard>
        {oldest && <p className="footer">{t('Max purchases since %@.', longDay(oldest))}</p>}
      </section>

      {txns.length > 0 ? (
        <>
          <CategoryBreakdown txns={txns} caption={caption} />
          <Section header={t('Purchases')}>
            {[...txns].sort((a, b) => b.date.localeCompare(a.date)).map((x) => <TxnRow key={x.id} txn={x} />)}
          </Section>
        </>
      ) : (
        <Empty icon="groceries" title={t('No purchases')} text={t('Nothing on your Max card in this period.')} />
      )}

      <section className="section">
        <div className="group">
          <button type="button" className="row link-row" onClick={download} disabled={!txns.length}>
            <Icon name="share" className="row-icon" />
            <span className="main">{t('Export %lld purchase(s) as CSV', txns.length)}</span>
          </button>
        </div>
      </section>
    </Page>
  );
}
