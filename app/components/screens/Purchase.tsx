'use client';

import { useState, type CSSProperties } from 'react';
import { categoryColor } from '@/lib/categories.ts';
import { atMerchant, buckets, merchantKey, total, type PurchaseNote } from '@/lib/insights.ts';
import { israelDay } from '@/lib/compute.ts';
import { useNav, useStore } from '../App.tsx';
import { useI18n } from '../I18n.tsx';
import { Icon } from '../icons.tsx';
import { Amt, CategoryTile, Labeled, LinkRow, Page, Section, TxnRow, useTitle } from '../ui.tsx';
import { NoData } from './Home.tsx';

export function PurchaseDetail({ id }: { id: string }) {
  const { data } = useStore();
  const { push } = useNav();
  const { t, ils, money, fullDate, longDay, category } = useI18n();
  const txn = data?.upcoming.flatMap((u) => u.txns).find((x) => x.id === id) ?? data?.history.find((x) => x.id === id);
  useTitle(txn?.description ?? '');
  if (!txn) return <Page title=""><NoData /></Page>;
  const others = atMerchant(merchantKey(txn), data!.history);
  const converted = txn.originalCurrency && txn.originalCurrency !== (txn.chargedCurrency ?? 'ILS') && txn.originalAmount != null;
  return (
    <Page title={txn.description}>
      <div className="detail-head">
        <CategoryTile k={txn.category} big />
        <h2>{txn.description}</h2>
        <div className="big-amount"><Amt>{(converted ? '≈ ' : '') + ils(-txn.chargedAmount)}</Amt></div>
        {converted && <div className="secondary"><Amt>{t('%@ at the Bank of Israel rate', money(-txn.originalAmount!, txn.originalCurrency!))}</Amt></div>}
        <div className="when">
          {fullDate(txn.date)}
          {txn.status === 'pending' && <span className="badge pending">{t('Pending')}</span>}
        </div>
      </div>

      <Section plain>
        <Labeled label={t('Card')}>
          <span className="num" aria-label={txn.cardLast4 ? t('Card ending in %@', txn.cardLast4) : undefined}>•• {txn.cardLast4 ?? '––––'}</span>
        </Labeled>
        <Labeled label={t('Category')}>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>{category(txn.category)}<CategoryTile k={txn.category} /></span>
        </Labeled>
        {txn.installments && <Labeled label={t('Installment')}>{t('%lld of %lld', txn.installments.number, txn.installments.total)}</Labeled>}
        <Labeled label={t('Debited')}>{txn.status === 'pending' ? t('Next debit') : longDay(israelDay(txn.processedDate))}</Labeled>
      </Section>

      <NoteSection id={txn.id} />

      {others.length > 1 && (
        <Section inset={50}>
          <LinkRow onClick={() => push({ s: 'merchant', key: merchantKey(txn), name: txn.description })}>
            <Icon name="list" className="row-icon" />
            <span className="main"><span className="title">{t('All purchases at %@', txn.description)}</span></span>
            <span className="end secondary">{t('%lld purchase(s)', others.length)}</span>
          </LinkRow>
        </Section>
      )}
    </Page>
  );
}

/** Free text and tags on a purchase ("work", "reimbursed"), kept with the preferences. */
function NoteSection({ id }: { id: string }) {
  const { prefs, setPrefs } = useStore();
  const { t } = useI18n();
  const note: PurchaseNote = prefs.notes[id] ?? { text: '', tags: [] };
  const [text, setText] = useState(note.text);
  const [adding, setAdding] = useState(false);
  const [newTag, setNewTag] = useState('');
  const known = Object.values(prefs.notes).flatMap((n) => n.tags);
  const tags = [...new Set([t('Work'), t('Reimbursed'), t('Shared'), ...known, ...note.tags])];

  const save = (n: PurchaseNote) => {
    const notes = { ...prefs.notes };
    if (n.text.trim() || n.tags.length) notes[id] = n;
    else delete notes[id];
    setPrefs({ notes });
  };
  const toggle = (tag: string) => save({ ...note, text, tags: note.tags.includes(tag) ? note.tags.filter((x) => x !== tag) : [...note.tags, tag] });
  const add = () => {
    const tag = newTag.trim();
    setNewTag('');
    setAdding(false);
    if (tag && !note.tags.includes(tag)) save({ ...note, text, tags: [...note.tags, tag] });
  };

  return (
    <section className="section">
      <h2 className="section-header small"><span>{t('Note and tags')}</span></h2>
      <div className="group">
        <textarea
          className="note"
          placeholder={t('Add a note (e.g. reimbursed by Dana)')}
          value={text}
          onChange={(e) => setText(e.target.value)}
          onBlur={() => text !== note.text && save({ ...note, text })}
          aria-label={t('Note and tags')}
        />
        <div className="tags">
          {tags.map((tag) => {
            const on = note.tags.includes(tag);
            return (
              <button key={tag} type="button" className="chip" aria-pressed={on} onClick={() => toggle(tag)}>
                <Icon name={on ? 'check' : 'tag'} />
                {tag}
              </button>
            );
          })}
          <button type="button" className="chip" onClick={() => setAdding(true)} aria-label={t('New tag')}><Icon name="plus" /></button>
        </div>
        {adding && (
          <form className="new-tag" onSubmit={(e) => (e.preventDefault(), add())}>
            <input autoFocus placeholder={t('Tag')} value={newTag} onChange={(e) => setNewTag(e.target.value)} aria-label={t('New tag')} />
            <button type="submit" className="pill-button">{t('Add')}</button>
            <button type="button" className="pill-button secondary" onClick={() => (setAdding(false), setNewTag(''))}>{t('Cancel')}</button>
          </form>
        )}
      </div>
      <p className="footer">{t('notesNote')}</p>
    </section>
  );
}

/** Everything bought from one merchant: total, average, per month. */
export function Merchant({ k, name }: { k: string; name: string }) {
  const { data } = useStore();
  const { t, ils, ilsWhole, monthShort } = useI18n();
  useTitle(name);
  const txns = atMerchant(k, data?.history ?? []).filter((x) => (x.chargedCurrency ?? 'ILS') === 'ILS');
  const sum = total(txns);
  const months = txns.length ? buckets(txns, israelDay(txns[txns.length - 1].date), israelDay(txns[0].date), 'month') : [];
  const max = Math.max(...months.map((m) => m.total), 1);
  return (
    <Page title={name}>
      <Section plain>
        <div className="row" style={{ display: 'block' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 12 }}>
            <div>
              <div className="secondary" style={{ fontSize: 15 }}>{t('Total')}</div>
              <Amt className="change" >{ils(sum)}</Amt>
            </div>
            <div style={{ textAlign: 'end', fontSize: 15 }}>
              <div className="secondary">{t('%lld purchase(s)', txns.length)}</div>
              {txns.length > 0 && <Amt>{t('about %@ each', ilsWhole(sum / txns.length))}</Amt>}
            </div>
          </div>
          {months.length > 1 && (
            <div className="month-bars" style={{ '--c': categoryColor(txns[0]?.category) } as CSSProperties}>
              {months.map((m) => (
                <div key={m.start}>
                  <i style={{ height: `${Math.max(3, (m.total / max) * 100)}%` }} title={ils(m.total)} />
                  <small>{monthShort(m.start)}</small>
                </div>
              ))}
            </div>
          )}
        </div>
      </Section>
      <Section footer={t('savedHere')}>
        {txns.map((x) => <TxnRow key={x.id} txn={x} />)}
      </Section>
    </Page>
  );
}
