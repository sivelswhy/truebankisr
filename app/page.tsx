'use client';

import { useEffect, useState } from 'react';
import type { Data } from './components/App.tsx';
import { I18nProvider } from './components/I18n.tsx';
import { Login } from './components/Login.tsx';
import { Shell } from './components/Shell.tsx';

type State = { status: 'loading' } | { status: 'signedOut' } | { status: 'signedIn'; snapshot: Data | null };

export default function Home() {
  const [state, setState] = useState<State>({ status: 'loading' });

  useEffect(() => {
    fetch('/api/session')
      .then((r) => r.json())
      .then((s) => setState(s.connected ? { status: 'signedIn', snapshot: s.snapshot } : { status: 'signedOut' }))
      .catch(() => setState({ status: 'signedOut' }));
  }, []);

  if (state.status === 'loading') return null;

  return (
    <I18nProvider>
      {state.status === 'signedIn' ? (
        <Shell initial={state.snapshot} onSignOut={() => setState({ status: 'signedOut' })} />
      ) : (
        <Login onConnected={(snapshot) => setState({ status: 'signedIn', snapshot })} />
      )}
    </I18nProvider>
  );
}
