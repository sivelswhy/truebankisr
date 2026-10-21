'use client';

import { useEffect, useState } from 'react';
import { LANGS, type Lang } from '@/lib/i18n.ts';
import { useNav, useStore } from '../App.tsx';
import { useI18n } from '../I18n.tsx';
import { Avatar, Labeled, Section, Sheet, Switch } from '../ui.tsx';

/** Profile and settings, as a sheet over the tabs (SettingsView). */
export function Profile() {
  const { setProfile } = useNav();
  const { data, prefs, setPrefs, signOut } = useStore();
  const i = useI18n();
  const { t, ilsWhole } = i;
  const [name, setName] = useState(prefs.firstName);
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [permission, setPermission] = useState<NotificationPermission | 'unsupported'>('default');

  useEffect(() => setPermission(typeof Notification === 'undefined' ? 'unsupported' : Notification.permission), []);

  const close = () => {
    if (name !== prefs.firstName) setPrefs({ firstName: name.trim() });
    setProfile(false);
  };

  // Ask the browser once a threshold is set, so the alert can show.
  const step = async (delta: number) => {
    const alertThreshold = Math.min(20_000, Math.max(0, prefs.alertThreshold + delta));
    setPrefs({ alertThreshold });
    if (permission === 'default' && typeof Notification !== 'undefined') setPermission(await Notification.requestPermission());
  };

  return (
    <Sheet title={t('Profile')} onClose={close}>
      <div className="me">
        <Avatar big />
        <input
          value={name}
          placeholder={t('Your first name')}
          onChange={(e) => setName(e.target.value)}
          onBlur={() => name !== prefs.firstName && setPrefs({ firstName: name.trim() })}
          autoComplete="given-name"
          aria-label={t('Your first name')}
        />
      </div>
      <p className="footer" style={{ textAlign: 'center' }}>{t('Used to greet you on the home screen.')}</p>

      <Section header={t('Accounts')} small plain footer={data?.demo ? t('You’re using sample data.') : t('signedIn')}>
        <Labeled label={t('Bank')}>{t('Leumi')}</Labeled>
        <Labeled label={t('Card')}>{t('Max')}</Labeled>
      </Section>

      <Section plain footer={t('autoRefreshNote')}>
        <Labeled label={t('Automatic refresh')}>{t('autoRefresh')}</Labeled>
      </Section>

      <Section
        header={t('Notifications')}
        small
        plain
        footer={
          <>
            {prefs.alertThreshold === 0 ? t('You’ll be notified if your true balance goes below zero.') : t('You’ll be notified when your true balance goes below this amount.')}{' '}
            {t('notifyNote')}
          </>
        }
      >
        <div className="row labeled">
          <span className="label">{t('Alert me below')}</span>
          <span className="value tight num">{ilsWhole(prefs.alertThreshold)}</span>
          <span className="stepper">
            <button type="button" onClick={() => step(-100)} disabled={prefs.alertThreshold === 0} aria-label="−100">−</button>
            <button type="button" onClick={() => step(100)} aria-label="+100">+</button>
          </span>
        </div>
      </Section>

      <Section header={t('Privacy')} small plain>
        <div className="row labeled">
          <span className="label">{t('Hide amounts')}</span>
          <Switch checked={prefs.hideAmounts} onChange={(hideAmounts) => setPrefs({ hideAmounts })} label={t('Hide amounts')} />
        </div>
      </Section>

      <Section plain>
        <label className="row labeled">
          <span className="label">{t('Language')}</span>
          <select value={i.lang} onChange={(e) => i.setLang(e.target.value as Lang)}>
            {LANGS.map((l) => <option key={l.id} value={l.id} lang={l.id}>{l.name}</option>)}
          </select>
        </label>
      </Section>

      <Section plain footer={confirming ? t('forgetNote') : undefined}>
        {confirming ? (
          <>
            <button type="button" className="row destructive" disabled={busy} onClick={() => (setBusy(true), signOut())}>
              {t('Disconnect and forget credentials')}
            </button>
            <button type="button" className="row" style={{ justifyContent: 'center' }} onClick={() => setConfirming(false)}>{t('Cancel')}</button>
          </>
        ) : (
          <button type="button" className="row destructive" onClick={() => setConfirming(true)}>
            {data?.demo ? t('Exit demo') : t('Disconnect')}
          </button>
        )}
      </Section>
    </Sheet>
  );
}
