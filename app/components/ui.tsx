'use client';

import { useEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { categoryColor } from '@/lib/categories.ts';
import type { Txn } from '@/lib/compute.ts';
import { movementKind, transferParty, type MovementKind } from '@/lib/insights.ts';
import { useNav, useStore } from './App.tsx';
import { useI18n } from './I18n.tsx';
import { categoryIcon, Icon, type IconName } from './icons.tsx';

// ---------- Page: navigation bar + content ----------

/** First letter of the first name, like ProfileAvatar. */
export function Avatar({ big, onClick }: { big?: boolean; onClick?: () => void }) {
  const { prefs } = useStore();
  const { t } = useI18n();
  const letter = prefs.firstName.trim().charAt(0).toUpperCase();
  const content = letter || <svg viewBox="0 0 24 24" width="60%" height="60%" fill="currentColor" aria-hidden><path d="M12 12a4.5 4.5 0 1 0 0-9 4.5 4.5 0 0 0 0 9Zm0 2c-4.4 0-8 2.2-8 5v2h16v-2c0-2.8-3.6-5-8-5Z" /></svg>;
  return onClick ? (
    <button type="button" className="avatar" onClick={onClick} aria-label={t('Profile and settings')}>{content}</button>
  ) : (
    <span className={`avatar${big ? ' big' : ''}`} aria-hidden>{content}</span>
  );
}

/** Spinner while updating, warning sign after a failed update (RefreshStatusButton). */
function StatusButton() {
  const { loading, errors, refresh } = useStore();
  const { t } = useI18n();
  if (loading) {
    return (
      <span className="icon-button" role="status" aria-label={t('Updating…')}>
        <Icon name="refresh" className="spin" />
      </span>
    );
  }
  return (
    <button type="button" className={`icon-button${errors ? ' warn' : ''}`} onClick={refresh} aria-label={errors ? t('Update failed') : t('Refresh now')}>
      <Icon name={errors ? 'warn' : 'refresh'} />
    </button>
  );
}

export function Page({ title, children, trailing }: { title: string; children: ReactNode; trailing?: ReactNode }) {
  const { stack, motion, back, setProfile } = useNav();
  const { t } = useI18n();
  const isRoot = stack.length === 1;
  const titleRef = useRef<HTMLHeadingElement>(null);
  const [scrolled, setScrolled] = useState(false);
  const backTitle = useBackTitle();

  // The large title collapses into the bar once it scrolls under it.
  useEffect(() => {
    if (!isRoot || !titleRef.current) return;
    const io = new IntersectionObserver(([e]) => setScrolled(!e.isIntersecting), { rootMargin: '-56px 0px 0px 0px' });
    io.observe(titleRef.current);
    return () => io.disconnect();
  }, [isRoot]);

  return (
    <div className={`page${motion === 'pop' ? ' back-in' : motion === 'tab' ? ' tab-in' : ''}`} key={stack.length}>
      <header className={`navbar${isRoot ? (scrolled ? ' scrolled' : '') : ' inline'}`}>
        {isRoot ? <span /> : (
          <button type="button" className="back" onClick={back}>
            <Icon name="back" />
            <span>{backTitle || t('Back')}</span>
          </button>
        )}
        <span className="bar-title">{title}</span>
        <div className="end">
          {trailing}
          {isRoot && <StatusButton />}
          {isRoot && <Avatar onClick={() => setProfile(true)} />}
        </div>
      </header>
      {isRoot && <h1 ref={titleRef} className="large-title">{title}</h1>}
      {!isRoot && <h1 className="visually-hidden">{title}</h1>}
      <ErrorBanner />
      {children}
    </div>
  );
}

// The title of the page under this one, for the Back button. Set by each screen.
const titles = new Map<string, string>();
function useBackTitle() {
  const { tab, stack } = useNav();
  return titles.get(`${tab}:${stack.length - 2}`) ?? '';
}
export function useTitle(title: string) {
  const { tab, stack } = useNav();
  titles.set(`${tab}:${stack.length - 1}`, title);
}

/** What went wrong in the last update, with Try again. */
function ErrorBanner() {
  const { errors, refresh, loading } = useStore();
  const { stack } = useNav();
  const i = useI18n();
  if (!errors || stack.length > 1) return null;
  const text = Object.entries(errors).map(([who, code]) => i.error(code, who === 'leumi' ? i.t('Leumi') : who === 'max' ? i.t('Max') : '')).join(' ');
  return (
    <div className="banner" role="alert">
      <Icon name="warn" />
      <div>
        <strong>{i.t('Update failed')}</strong>
        <div>{text}</div>
        <div className="actions">
          <button type="button" className="pill-button secondary" onClick={refresh} disabled={loading}>{i.t('Try again')}</button>
        </div>
      </div>
    </div>
  );
}

// ---------- Sections and rows ----------

export function Section({
  header, side, small, onSeeAll, footer, children, plain, inset,
}: {
  header?: ReactNode; side?: ReactNode; small?: boolean; onSeeAll?: () => void; footer?: ReactNode; children: ReactNode; plain?: boolean; inset?: number;
}) {
  const { t } = useI18n();
  return (
    <section className="section">
      {header && (
        <h2 className={`section-header${small ? ' small' : ''}`}>
          <span>{header}</span>
          {onSeeAll ? <button type="button" className="see-all" onClick={onSeeAll}>{t('See all')}</button> : side != null && <span className="side num">{side}</span>}
        </h2>
      )}
      <div className={`group${plain ? ' plain' : ''}`} style={inset != null ? ({ '--inset': `${inset}px` } as CSSProperties) : undefined}>{children}</div>
      {footer && <p className="footer">{footer}</p>}
    </section>
  );
}

export const Chevron = () => <Icon name="chevron" className="chev" />;

export function LinkRow({ onClick, children, className = '' }: { onClick: () => void; children: ReactNode; className?: string }) {
  return (
    <button type="button" className={`row ${className}`} onClick={onClick}>
      {children}
      <Chevron />
    </button>
  );
}

/** "Label ......... value", like LabeledContent. */
export function Labeled({ label, children, icon }: { label: ReactNode; children: ReactNode; icon?: IconName }) {
  return (
    <div className="row labeled">
      {icon && <Icon name={icon} className="row-icon" />}
      <span className="label">{label}</span>
      <span className="value">{children}</span>
    </div>
  );
}

/** An amount that "Hide amounts" blurs. */
export const Amt = ({ children, className = '' }: { children: ReactNode; className?: string }) => (
  <span className={`amt num ${className}`}>{children}</span>
);

// ---------- Icons ----------

export function CategoryTile({ k, big }: { k: string | undefined; big?: boolean }) {
  return (
    <span className={`tile${big ? ' big' : ''}`} style={{ '--c': categoryColor(k) } as CSSProperties}>
      <Icon name={categoryIcon(k)} />
    </span>
  );
}

const KIND: Record<MovementKind, { icon: IconName; color: string; label: string }> = {
  transferIn: { icon: 'in', color: 'var(--green)', label: 'Transfer received' },
  transferOut: { icon: 'out', color: 'var(--orange)', label: 'Transfer sent' },
  cardDebit: { icon: 'card', color: '#002AA9', label: 'Max debit' },
  income: { icon: 'plus', color: 'var(--green)', label: 'Money in' },
  expense: { icon: 'minus', color: '#8E8E93', label: 'Debit' },
};
export const kindInfo = (t: Txn) => KIND[movementKind(t)];

export function KindTile({ txn, big }: { txn: Txn; big?: boolean }) {
  const k = kindInfo(txn);
  return (
    <span className={`tile${big ? ' big' : ''}`} style={{ '--c': k.color } as CSSProperties}>
      <Icon name={k.icon} />
    </span>
  );
}

// ---------- Purchase and movement rows ----------

export function TxnRow({ txn, debitDay }: { txn: Txn; debitDay?: string }) {
  const { push } = useNav();
  const { prefs } = useStore();
  const { t, category, dayTime, day, ils, money } = useI18n();
  const parts = [dayTime(txn.date), category(txn.category)];
  if (txn.installments) parts.push(t('%lld of %lld', txn.installments.number, txn.installments.total));
  if (debitDay) parts.push(t('Debited %@', day(debitDay)));
  const converted = txn.originalCurrency && txn.originalCurrency !== (txn.chargedCurrency ?? 'ILS') && txn.originalAmount != null;
  return (
    <LinkRow onClick={() => push({ s: 'txn', id: txn.id })}>
      <CategoryTile k={txn.category} />
      <span className="main">
        <span className="title">
          {txn.description}
          {prefs.notes[txn.id] && <Icon name="tag" className="row-icon" />}
        </span>
        <span className="sub">{parts.join(' · ')}</span>
      </span>
      <span className="end">
        <Amt>{(converted ? '≈ ' : '') + ils(-txn.chargedAmount)}</Amt>
        {converted ? <small className="amt">{money(-txn.originalAmount!, txn.originalCurrency!)}</small>
          : txn.status === 'pending' && <span className="pending">{t('Pending')}</span>}
      </span>
    </LinkRow>
  );
}

export function MovementRow({ txn }: { txn: Txn }) {
  const { push } = useNav();
  const { t, day, ils } = useI18n();
  const name = transferParty(txn)?.name ?? txn.description;
  return (
    <LinkRow onClick={() => push({ s: 'movement', id: txn.id })}>
      <KindTile txn={txn} />
      <span className="main">
        <span className="title">{name}</span>
        <span className="sub">{[day(txn.date), t(kindInfo(txn).label)].join(' · ')}</span>
      </span>
      <span className="end">
        <Amt className={txn.chargedAmount > 0 ? 'pos' : ''}>{(txn.chargedAmount > 0 ? '+' : '') + ils(txn.chargedAmount)}</Amt>
        {txn.runningBalance != null && <small className="amt">{t('Balance %@', ils(txn.runningBalance))}</small>}
      </span>
    </LinkRow>
  );
}

// ---------- Hero card ----------

export function HeroCard({ tint, onClick, label, children }: { tint?: string; onClick?: () => void; label?: string; children: ReactNode }) {
  const style = tint ? ({ '--tint': tint } as CSSProperties) : undefined;
  return onClick ? (
    <button type="button" className="hero" style={style} onClick={onClick} aria-label={label}>{children}</button>
  ) : (
    <div className="hero" style={style}>{children}</div>
  );
}

export function ChangeBadge({ change }: { change: number }) {
  const { percent } = useI18n();
  return <span className="change amt" style={{ color: change > 0 ? 'var(--red)' : 'var(--green)' }}>{(change > 0 ? '+' : '') + percent(change)}</span>;
}

// ---------- Controls ----------

export function Chips<T extends string>({ options, value, onChange }: { options: { id: T; label: string; icon?: IconName }[]; value: T | null; onChange: (v: T) => void }) {
  return (
    <div className="chips" role="group">
      {options.map((o) => (
        <button key={o.id} type="button" className="chip" aria-pressed={value === o.id} onClick={() => onChange(o.id)}>
          {o.icon && <Icon name={o.icon} />}
          {o.label}
        </button>
      ))}
    </div>
  );
}

export function Segmented<T extends string>({ options, value, onChange, label }: { options: { id: T; label: string }[]; value: T; onChange: (v: T) => void; label: string }) {
  return (
    <div className="segmented" role="group" aria-label={label}>
      {options.map((o) => (
        <button key={o.id} type="button" aria-pressed={value === o.id} onClick={() => onChange(o.id)}>{o.label}</button>
      ))}
    </div>
  );
}

export function Switch({ checked, onChange, label }: { checked: boolean; onChange: (v: boolean) => void; label: string }) {
  return <button type="button" role="switch" className="switch" aria-checked={checked} aria-label={label} onClick={() => onChange(!checked)} />;
}

export function Sheet({ title, onClose, done, children }: { title: string; onClose: () => void; done?: string; children: ReactNode }) {
  const { t } = useI18n();
  const ref = useRef<HTMLDivElement>(null);
  const closeRef = useRef(onClose);
  closeRef.current = onClose;
  // Once, on open: focus moves into the sheet and comes back on close.
  useEffect(() => {
    const prev = document.activeElement as HTMLElement | null;
    ref.current?.focus();
    const key = (e: KeyboardEvent) => e.key === 'Escape' && closeRef.current();
    window.addEventListener('keydown', key);
    document.body.style.overflow = 'hidden';
    return () => {
      window.removeEventListener('keydown', key);
      document.body.style.overflow = '';
      prev?.focus();
    };
  }, []);
  // On <body>: the pull-to-refresh layer would otherwise hold it under the tab bar.
  return createPortal(
    <>
      <div className="scrim" onClick={onClose} />
      <div className="sheet" role="dialog" aria-modal="true" aria-label={title} ref={ref} tabIndex={-1}>
        <header className="navbar inline">
          <span />
          <span className="bar-title">{title}</span>
          <div className="end">
            <button type="button" className="text-button bold" onClick={onClose}>{done ?? t('Done')}</button>
          </div>
        </header>
        {children}
      </div>
    </>,
    document.body,
  );
}

export function Empty({ icon, title, text }: { icon: IconName; title: string; text?: string }) {
  return (
    <div className="empty">
      <Icon name={icon} />
      <h3>{title}</h3>
      {text && <p>{text}</p>}
    </div>
  );
}

// ---------- Charts ----------

/** Donut by category: tap a slice to see its total in the middle. */
export function Donut({ totals, onPick }: { totals: { key: string; total: number }[]; onPick?: (key: string) => void }) {
  const { t, category, ils } = useI18n();
  const [selected, setSelected] = useState<string | null>(null);
  const sum = totals.reduce((s, c) => s + c.total, 0);
  const arcs = useMemo(() => {
    let start = -Math.PI / 2;
    const gap = totals.length > 1 ? 0.025 : 0;
    return totals.map((c) => {
      const sweep = (c.total / sum) * Math.PI * 2;
      const a0 = start + gap / 2, a1 = start + sweep - gap / 2;
      start += sweep;
      const R = 100, r = 62;
      const p = (a: number, rad: number) => `${110 + rad * Math.cos(a)} ${110 + rad * Math.sin(a)}`;
      const large = a1 - a0 > Math.PI ? 1 : 0;
      const d = sweep >= Math.PI * 2 - 0.001
        ? `M ${p(0, R)} A ${R} ${R} 0 1 1 ${p(Math.PI, R)} A ${R} ${R} 0 1 1 ${p(0, R)} M ${p(0, r)} A ${r} ${r} 0 1 0 ${p(Math.PI, r)} A ${r} ${r} 0 1 0 ${p(0, r)} Z`
        : `M ${p(a0, R)} A ${R} ${R} 0 ${large} 1 ${p(a1, R)} L ${p(a1, r)} A ${r} ${r} 0 ${large} 0 ${p(a0, r)} Z`;
      return { key: c.key, d };
    });
  }, [totals, sum]);
  const pick = totals.find((c) => c.key === selected);
  return (
    <div className="donut-wrap">
      <svg className="donut" viewBox="0 0 220 220" role="img" aria-label={t('By category')}>
        {arcs.map((a) => (
          <path
            key={a.key}
            d={a.d}
            fill={categoryColor(a.key)}
            fillRule="evenodd"
            opacity={!selected || selected === a.key ? 1 : 0.35}
            onClick={() => (selected === a.key && onPick ? onPick(a.key) : setSelected(selected === a.key ? null : a.key))}
          >
            <title>{category(a.key)}</title>
          </path>
        ))}
      </svg>
      <div className="donut-center">
        <small>{pick ? category(pick.key) : t('Total')}</small>
        <b className="amt">{ils(pick?.total ?? sum)}</b>
      </div>
    </div>
  );
}

/** Running total over a period; touch or hover to read a day. */
export function Curve({ points, labels }: { points: number[]; labels: string[] }) {
  const { ils } = useI18n();
  const [hover, setHover] = useState<number | null>(null);
  const ref = useRef<SVGSVGElement>(null);
  const max = Math.max(...points, 1);
  const W = 300, H = 110;
  const x = (i: number) => (points.length > 1 ? (i / (points.length - 1)) * W : W / 2);
  const y = (v: number) => H - 6 - (v / max) * (H - 14);
  const line = points.map((v, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)} ${y(v).toFixed(1)}`).join('');
  const pick = (clientX: number) => {
    const r = ref.current!.getBoundingClientRect();
    let f = (clientX - r.left) / r.width;
    if (document.documentElement.dir === 'rtl') f = 1 - f;
    setHover(Math.max(0, Math.min(points.length - 1, Math.round(f * (points.length - 1)))));
  };
  const rtl = typeof document !== 'undefined' && document.documentElement.dir === 'rtl';
  return (
    <>
      <svg
        ref={ref}
        className="curve"
        viewBox={`0 0 ${W} ${H}`}
        preserveAspectRatio="none"
        onPointerMove={(e) => pick(e.clientX)}
        onPointerDown={(e) => pick(e.clientX)}
        onPointerLeave={() => setHover(null)}
        aria-hidden
      >
        <defs>
          <linearGradient id="curve-fill" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0" stopColor="var(--accent)" stopOpacity="0.35" />
            <stop offset="1" stopColor="var(--accent)" stopOpacity="0" />
          </linearGradient>
        </defs>
        <g transform={rtl ? `translate(${W},0) scale(-1,1)` : undefined}>
          <path d={`${line}L${W} ${H}L0 ${H}Z`} fill="url(#curve-fill)" />
          <path d={line} fill="none" stroke="var(--accent)" strokeWidth="2.5" vectorEffect="non-scaling-stroke" strokeLinejoin="round" />
          {hover != null && <line x1={x(hover)} x2={x(hover)} y1={0} y2={H} stroke="var(--secondary)" strokeWidth="1" vectorEffect="non-scaling-stroke" />}
        </g>
      </svg>
      <div className="curve-label amt">{hover != null ? `${labels[hover]} · ${ils(points[hover])}` : ' '}</div>
    </>
  );
}
