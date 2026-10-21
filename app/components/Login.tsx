'use client';

import { useEffect, useRef, useState, type FormEvent } from 'react';
import { LANGS, type Lang } from '@/lib/i18n.ts';
import type { Data } from './App.tsx';
import { useI18n } from './I18n.tsx';
import { Icon } from './icons.tsx';

type Provider = 'leumi' | 'max';
type Errors = Partial<Record<Provider | 'general', string>>;

const PROVIDERS: { id: Provider; title: string; hint: string; short: string }[] = [
  { id: 'leumi', title: 'Bank Leumi', hint: 'The username and password you use on leumi.co.il.', short: 'Leumi' },
  { id: 'max', title: 'Max', hint: 'The username and password you use on max.co.il.', short: 'Max' },
];

/** Sign in to Leumi and Max, like the iPhone's LoginView. */
export function Login({ onConnected }: { onConnected: (snapshot: Data) => void }) {
  const i = useI18n();
  const { t } = i;
  const [values, setValues] = useState({ leumi: { username: '', password: '' }, max: { username: '', password: '' } });
  const [reveal, setReveal] = useState<Provider | null>(null);
  const [pending, setPending] = useState<'live' | 'demo' | null>(null);
  const [errors, setErrors] = useState<Errors>({});
  const fields = useRef<Partial<Record<Provider, HTMLInputElement | null>>>({});
  const focusError = useRef(false);

  const complete = PROVIDERS.every(({ id }) => values[id].username.trim() && values[id].password);

  const set = (id: Provider, field: 'username' | 'password', value: string) => {
    setValues((v) => ({ ...v, [id]: { ...v[id], [field]: value } }));
    if (errors[id]) setErrors(({ [id]: _, ...rest }) => rest); // clear the error as soon as they fix it
  };

  async function connect(body: object, mode: 'live' | 'demo') {
    setPending(mode);
    setErrors({});
    try {
      const res = await fetch('/api/session', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
      const json = await res.json();
      if (!res.ok) {
        setErrors(json.errors ?? { general: 'UNKNOWN' });
        navigator.vibrate?.([20, 40, 20]);
        focusError.current = true;
        return;
      }
      onConnected(json.snapshot);
    } catch {
      setErrors({ general: 'SERVER_DOWN' });
    } finally {
      setPending(null);
    }
  }

  // Once the form is enabled again, put the cursor on the first account in error.
  useEffect(() => {
    if (pending || !focusError.current) return;
    focusError.current = false;
    const first = PROVIDERS.find(({ id }) => errors[id]);
    if (first) fields.current[first.id]?.focus();
  }, [errors, pending]);

  const submit = (e: FormEvent) => {
    e.preventDefault();
    if (complete && !pending) connect(values, 'live');
  };

  return (
    <main className="login">
      <div className="login-head">
        <img src="/icon.png" alt="" />
        <h1>{t('True Balance')}</h1>
        <p>{t('See what you can really spend: your Leumi balance minus the Max charges still to come.')}</p>
      </div>

      {errors.general && (
        <div className="banner" role="alert">
          <Icon name="warn" />
          <div>{i.error(errors.general)}</div>
        </div>
      )}

      <form onSubmit={submit} noValidate>
        <fieldset disabled={!!pending}>
          {PROVIDERS.map(({ id, title, hint, short }) => (
            <section key={id} className="section" style={{ marginTop: id === 'leumi' ? 0 : 22 }}>
              <h2 className="section-header small"><span>{t(title)}</span></h2>
              <div className={`group plain ${errors[id] ? 'invalid' : ''}`}>
                <div className="row">
                  <label htmlFor={`${id}-user`}>{t('Username')}</label>
                  <input
                    id={`${id}-user`}
                    ref={(el) => void (fields.current[id] = el)}
                    autoComplete={`section-${id} username`}
                    autoCapitalize="none"
                    autoCorrect="off"
                    spellCheck={false}
                    placeholder={t('Required')}
                    value={values[id].username}
                    onChange={(e) => set(id, 'username', e.target.value)}
                    aria-invalid={!!errors[id]}
                    aria-describedby={`${id}-note`}
                  />
                </div>
                <div className="row">
                  <label htmlFor={`${id}-pass`}>{t('Password')}</label>
                  <input
                    id={`${id}-pass`}
                    type={reveal === id ? 'text' : 'password'}
                    autoComplete={`section-${id} current-password`}
                    placeholder={t('Required')}
                    value={values[id].password}
                    onChange={(e) => set(id, 'password', e.target.value)}
                    aria-invalid={!!errors[id]}
                    aria-describedby={`${id}-note`}
                  />
                  <button
                    type="button"
                    className="reveal"
                    onClick={() => setReveal(reveal === id ? null : id)}
                    aria-label={reveal === id ? t('Hide password') : t('Show password')}
                    aria-pressed={reveal === id}
                  >
                    <svg viewBox="0 0 24 24" aria-hidden>
                      <path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12Z" fill="none" stroke="currentColor" strokeWidth="1.8" />
                      <circle cx="12" cy="12" r="3" fill="none" stroke="currentColor" strokeWidth="1.8" />
                      {reveal !== id && <path d="M4 20 20 4" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />}
                    </svg>
                  </button>
                </div>
              </div>
              <p id={`${id}-note`} className={`footer ${errors[id] ? 'neg' : ''}`} role={errors[id] ? 'alert' : undefined}>
                {errors[id] ? i.error(errors[id], t(short)) : t(hint)}
              </p>
            </section>
          ))}

          <button type="submit" className="primary" disabled={!complete || !!pending}>
            {pending === 'live' && <Icon name="refresh" className="spin" />}
            {pending === 'live' ? t('Connecting to Leumi and Max…') : t('Connect')}
          </button>
          <p className="footer" style={{ textAlign: 'center' }} aria-live="polite">
            {pending === 'live' ? t('connectingNote') : t('privacyNote')}
          </p>

          <button type="button" className="link" onClick={() => connect({ demo: true }, 'demo')}>
            {pending === 'demo' ? t('Updating…') : t('Try with sample data')}
          </button>
          <div className="lang-select">
            <select value={i.lang} onChange={(e) => i.setLang(e.target.value as Lang)} aria-label={t('Language')}>
              {LANGS.map((l) => <option key={l.id} value={l.id} lang={l.id}>{l.name}</option>)}
            </select>
          </div>
        </fieldset>
      </form>
    </main>
  );
}
