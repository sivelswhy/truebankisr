'use client';

import { useState, type CSSProperties } from 'react';
import { categoryColor, COLORS, totalsByCategory } from '@/lib/categories.ts';
import { budgetProgress, compareMonths, forecast, monthlyTotal, subscriptions, wealth, type BudgetProgress } from '@/lib/insights.ts';
import { useNav, useStore } from '../App.tsx';
import { useI18n } from '../I18n.tsx';
import { Icon, type IconName } from '../icons.tsx';
import { Amt, CategoryTile, ChangeBadge, HeroCard, Labeled, LinkRow, Page, Section, Sheet, useTitle, Money } from '../ui.tsx';
import { NoData, RecurringRow } from './Home.tsx';

/** Month to month, budgets, subscriptions, regular bank movements, net worth. */
export function Insights() {
  const { data, prefs } = useStore();
  const { push } = useNav();
  const { t, ilsWhole } = useI18n();
  const [editing, setEditing] = useState(false);
  useTitle(t('Insights'));
  if (!data) return <Page title={t('Insights')}><NoData /></Page>;

  const c = compareMonths(data.history);
  const progress = budgetProgress(prefs.budgets, data.history);
  const subs = subscriptions(data.history);
  const f = forecast(data);
  const w = data.savings || data.foreignAccounts ? wealth(data) : null;

  return (
    <Page title={t('Insights')}>
      <HeroCard tint={(c.change ?? 0) > 0.1 ? 'var(--orange)' : undefined} onClick={() => push({ s: 'month' })}>
        <div className="caption">
          <span>{t('This month on Max')}</span>
          <Icon name="chevron" className="chev" />
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 12 }}>
          <div className="amount medium"><Money n={c.thisMonth} whole /></div>
          {c.change != null && <ChangeBadge change={c.change} />}
        </div>
        <div className="meta"><Amt>{t('Last month at the same date: %@', ilsWhole(c.lastMonthSamePeriod))}</Amt></div>
      </HeroCard>

      <section className="section">
        <h2 className="section-header">
          <span>{t('Budgets')}</span>
          {progress.length > 0 && <button type="button" className="see-all" onClick={() => setEditing(true)}>{t('Edit')}</button>}
        </h2>
        <div className="group">
          {progress.length === 0 ? (
            <button type="button" className="row link-row" onClick={() => setEditing(true)}>
              <Icon name="plus" className="row-icon" />
              <span className="main">{t('Set a monthly budget per category')}</span>
            </button>
          ) : progress.map((p) => <BudgetRow key={p.category} p={p} />)}
        </div>
        <p className="footer">{t('You’ll get a notification at 80% and 100%.')}</p>
      </section>

      {subs.length > 0 && (
        <Section header={t('Subscriptions')} side={<Amt>{t('%@/month', ilsWhole(monthlyTotal(subs)))}</Amt>}>
          {subs.slice(0, 4).map((s) => (
            <RecurringRow key={s.name} name={s.name} next={s.nextDate} amount={s.amount} onClick={() => push({ s: 'merchant', key: s.name.toLowerCase(), name: s.name })} />
          ))}
          {subs.length > 4 && <LinkRow onClick={() => push({ s: 'subscriptions' })}><span className="main link-row">{t('See all %lld', subs.length)}</span></LinkRow>}
        </Section>
      )}

      {f && (
        <Section header={t('Leumi')} inset={50}>
          <LinkRow onClick={() => push({ s: 'forecast' })}>
            <Icon name="repeat" className="row-icon" />
            <span className="main">{t('Salary and regular debits')}</span>
          </LinkRow>
        </Section>
      )}

      {w && (
        <Section header={t('Net worth')} inset={50}>
          <LinkRow onClick={() => push({ s: 'wealth' })}>
            <Icon name="bank" className="row-icon" />
            <span className="main">{t('Current account, savings and foreign currency')}</span>
            <span className="end" style={{ fontWeight: 600 }}><Money n={w.total} whole /></span>
          </LinkRow>
        </Section>
      )}

      {editing && <BudgetEditor onClose={() => setEditing(false)} />}
    </Page>
  );
}

function BudgetRow({ p }: { p: BudgetProgress }) {
  const { t, category, percent, ilsWhole } = useI18n();
  const color = p.ratio >= 1 ? 'var(--red)' : p.ratio >= 0.8 ? 'var(--orange)' : categoryColor(p.category);
  return (
    <div className="row" style={{ display: 'block' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <CategoryTile k={p.category} />
        <span className="main">{category(p.category)}</span>
        <span className="num" style={{ color }}>{percent(p.ratio)}</span>
      </div>
      <div className="meter" style={{ '--c': color } as CSSProperties}><i style={{ width: `${Math.min(p.ratio, 1) * 100}%` }} /></div>
      <div className="row-foot" style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13, color: 'var(--secondary)' }}>
        <Amt>{t('%@ spent', ilsWhole(p.spent))}</Amt>
        <Amt>{p.spent <= p.limit ? t('%@ left', ilsWhole(p.limit - p.spent)) : t('%@ over', ilsWhole(p.spent - p.limit))}</Amt>
      </div>
    </div>
  );
}

/** A monthly amount per category; empty for no budget. Categories seen on the card first. */
function BudgetEditor({ onClose }: { onClose: () => void }) {
  const { data, prefs, setPrefs } = useStore();
  const { t, category } = useI18n();
  const seen = totalsByCategory(data?.history ?? []).map((c) => c.key);
  const keys = [...seen, ...Object.keys(COLORS).filter((k) => !seen.includes(k)).sort()];
  const set = (key: string, value: string) => {
    const n = Number(value.replace(/[^\d.]/g, ''));
    const budgets = { ...prefs.budgets };
    if (n > 0) budgets[key] = n;
    else delete budgets[key];
    setPrefs({ budgets });
  };
  return (
    <Sheet title={t('Budgets')} onClose={onClose}>
      <Section footer={t('Monthly amount. Leave empty for no budget.')}>
        {keys.map((k) => (
          <label className="row" key={k}>
            <CategoryTile k={k} />
            <span className="main">{category(k)}</span>
            <input
              className="field num"
              style={{ flex: '0 0 6em' }}
              inputMode="decimal"
              placeholder="₪"
              defaultValue={prefs.budgets[k] ? String(prefs.budgets[k]) : ''}
              onChange={(e) => set(k, e.target.value)}
              aria-label={category(k)}
            />
          </label>
        ))}
      </Section>
    </Sheet>
  );
}

// ---------- Month to month ----------

export function MonthComparison() {
  const { data } = useStore();
  const { t, ils, ilsWhole, category } = useI18n();
  useTitle(t('Month to month'));
  if (!data) return <Page title={t('Month to month')}><NoData /></Page>;
  const c = compareMonths(data.history);
  const rows = Object.entries(c.byCategory).filter(([, v]) => Math.abs(v) >= 1).sort((a, b) => Math.abs(b[1]) - Math.abs(a[1]));
  return (
    <Page title={t('Month to month')}>
      <Section plain>
        <Labeled label={t('This month')}><Money n={c.thisMonth} /></Labeled>
        <Labeled label={t('Last month, same days')}><Money n={c.lastMonthSamePeriod} /></Labeled>
        <Labeled label={<span className="secondary">{t('Last month, whole')}</span>}><Money n={c.lastMonthTotal} /></Labeled>
        {c.change != null && <Labeled label={t('Change')}><ChangeBadge change={c.change} /></Labeled>}
      </Section>
      {rows.length > 0 && (
        <Section header={t('By category')} footer={t('Compared with the same days of last month.')}>
          {rows.map(([k, delta]) => (
            <div className="row" key={k}>
              <CategoryTile k={k} />
              <span className="main">{category(k)}</span>
              <span className="end" style={{ flexDirection: 'row', gap: 4, alignItems: 'center', color: delta > 0 ? 'var(--red)' : 'var(--green)' }}>
                <Icon name={delta > 0 ? 'out' : 'in'} className="row-icon flip" />
                <Money n={delta} plus whole />
              </span>
            </div>
          ))}
        </Section>
      )}
    </Page>
  );
}

// ---------- Subscriptions ----------

export function Subscriptions() {
  const { data } = useStore();
  const { push } = useNav();
  const { t, ils, ilsWhole } = useI18n();
  useTitle(t('Subscriptions'));
  const subs = subscriptions(data?.history ?? []);
  const perMonth = monthlyTotal(subs);
  return (
    <Page title={t('Subscriptions')}>
      <Section plain>
        <div className="row labeled">
          <span className="label">
            {t('Per month')}
            <br />
            <small className="secondary amt">{t('%@ a year', ilsWhole(perMonth * 12))}</small>
          </span>
          <Money n={perMonth} className="change" />
        </div>
      </Section>
      <Section footer={t('Max charges from the same merchant, for the same amount, every month. Installment plans aren’t included.')}>
        {subs.map((s) => (
          <RecurringRow key={s.name} name={s.name} next={s.nextDate} amount={s.amount} onClick={() => push({ s: 'merchant', key: s.name.toLowerCase(), name: s.name })} />
        ))}
      </Section>
    </Page>
  );
}

// ---------- Net worth ----------

const WEALTH_ICON: Record<string, IconName> = { current: 'bank', card: 'card', savings: 'cash', foreign: 'fx' };

export function Wealth() {
  const { data } = useStore();
  const { t, ils, money } = useI18n();
  useTitle(t('Net worth'));
  if (!data) return <Page title={t('Net worth')}><NoData /></Page>;
  const w = wealth(data);
  const title = (l: (typeof w.lines)[number]) =>
    l.kind === 'current' ? t('Leumi current account') : l.kind === 'card' ? t('Max charges to come') : l.kind === 'savings' ? l.name || t('Savings') : t('%@ account', l.name);
  return (
    <Page title={t('Net worth')}>
      <Section small header={t('Total')} plain footer={t('Current account after the Max debits already known, savings and foreign-currency accounts at today’s Bank of Israel rate.')}>
        <div className="row"><span className="amount medium" style={{ font: '700 34px var(--rounded)' }}><Money n={w.total} /></span></div>
      </Section>
      <Section inset={50}>
        {w.lines.map((l) => (
          <div className="row" key={l.kind + l.name}>
            <Icon name={WEALTH_ICON[l.kind]} className="row-icon" />
            <span className="main">{title(l)}</span>
            <span className="end">
              {l.original != null ? <Amt>{ils(l.amount)}</Amt> : <Money n={l.amount} />}
              {l.original != null && l.currency && <small className="amt">{money(l.original, l.currency)}</small>}
            </span>
          </div>
        ))}
        {w.unconverted.map((f) => (
          <div className="row" key={f.currency}>
            <Icon name="fx" className="row-icon" />
            <span className="main">{t('%@ account (not counted, no rate)', f.currency)}</span>
            <span className="end"><Amt>{money(f.balance, f.currency)}</Amt></span>
          </div>
        ))}
      </Section>
    </Page>
  );
}

