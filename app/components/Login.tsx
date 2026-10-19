'use client';

import { useEffect, useRef, useState, type FormEvent } from 'react';
import type { Data } from './Dashboard.tsx';
import { useI18n } from './I18n.tsx';

type Provider = 'leumi' | 'max';
type Errors = Partial<Record<Provider | 'general', string>>;

const PROVIDERS: { id: Provider; name: 'bankLeumi' | 'max'; hint: 'leumiHint' | 'maxHint'; short: string }[] = [
  { id: 'leumi', name: 'bankLeumi', hint: 'leumiHint', short: 'Leumi' },
  { id: 'max', name: 'max', hint: 'maxHint', short: 'Max' },
];

export function Login({ onConnected }: { onConnected: (snapshot: Data) => void }) {
  const i = useI18n();
  const { d } = i;
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
      const res = await fetch('/api/session', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(body),
      });
      const json = await res.json();
      if (!res.ok) {
        const errs: Errors = json.errors ?? { general: 'UNKNOWN' };
        setErrors(errs);
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
        <img className="app-icon" src="/icon.png" alt="" aria-hidden />
        <h1 className="large-title">{d.appName}</h1>
        <p className="lede">{d.lede}</p>
      </div>

      {errors.general && (
        <div className="banner" role="alert">
          {i.error(errors.general)}
        </div>
      )}

      <form onSubmit={submit} noValidate>
        <fieldset disabled={!!pending}>
          {PROVIDERS.map(({ id, name, hint, short }) => (
            <section key={id}>
              <h2 className="group-header">
                <span>{d[name]}</span>
              </h2>
              <ul className={`group form ${errors[id] ? 'invalid' : ''}`}>
                <li>
                  <label htmlFor={`${id}-user`}>{d.username}</label>
                  <input
                    id={`${id}-user`}
                    ref={(el) => void (fields.current[id] = el)}
                    autoComplete={`section-${id} username`}
                    autoCapitalize="none"
                    autoCorrect="off"
                    spellCheck={false}
                    placeholder={d.required}
                    value={values[id].username}
                    onChange={(e) => set(id, 'username', e.target.value)}
                    aria-invalid={!!errors[id]}
                    aria-describedby={`${id}-note`}
                  />
                </li>
                <li>
                  <label htmlFor={`${id}-pass`}>{d.password}</label>
                  <input
                    id={`${id}-pass`}
                    type={reveal === id ? 'text' : 'password'}
                    autoComplete={`section-${id} current-password`}
                    placeholder={d.required}
                    value={values[id].password}
                    onChange={(e) => set(id, 'password', e.target.value)}
                    aria-invalid={!!errors[id]}
                    aria-describedby={`${id}-note`}
                  />
                  <button
                    type="button"
                    className="reveal"
                    onClick={() => setReveal(reveal === id ? null : id)}
                    aria-label={reveal === id ? d.hidePassword : d.showPassword}
                    aria-pressed={reveal === id}
                  >
                    <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden>
                      <path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12Z" fill="none" stroke="currentColor" strokeWidth="1.8" />
                      <circle cx="12" cy="12" r="3" fill="none" stroke="currentColor" strokeWidth="1.8" />
                      {reveal !== id && <path d="M4 20 20 4" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />}
                    </svg>
                  </button>
                </li>
              </ul>
              <p id={`${id}-note`} className={`footnote ${errors[id] ? 'neg' : ''}`} role={errors[id] ? 'alert' : undefined}>
                {errors[id] ? i.error(errors[id], short) : d[hint]}
              </p>
            </section>
          ))}

          <button type="submit" className="primary" disabled={!complete || !!pending}>
            {pending === 'live' ? (
              <>
                <svg viewBox="0 0 24 24" width="18" height="18" className="spin" aria-hidden>
                  <path d="M12 3a9 9 0 1 0 9 9" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" />
                </svg>
                {d.connecting}
              </>
            ) : (
              d.connect
            )}
          </button>
          <p className="footnote center tight" aria-live="polite">
            {pending === 'live'
              ? d.connectingNote
              : d.privacyNote}
          </p>

          <button type="button" className="link" onClick={() => connect({ demo: true }, 'demo')}>
            {pending === 'demo' ? d.loading : d.tryDemo}
          </button>
          <button type="button" className="link small" onClick={() => i.setLang(i.lang === 'fr' ? 'en' : 'fr')} lang={i.lang === 'fr' ? 'en' : 'fr'}>
            {d.language}
          </button>
        </fieldset>
      </form>
    </main>
  );
}
