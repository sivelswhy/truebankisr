'use client';

import { useEffect, useState } from 'react';
import { Dashboard, type Data } from './components/Dashboard.tsx';
import { I18nProvider } from './components/I18n.tsx';
import { Login } from './components/Login.tsx';

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
      <div className="screen" key={state.status}>
        {state.status === 'signedIn' ? (
          <Dashboard initial={state.snapshot} onSignOut={() => setState({ status: 'signedOut' })} />
        ) : (
          <Login onConnected={(snapshot) => setState({ status: 'signedIn', snapshot })} />
        )}
      </div>
    </I18nProvider>
  );
}
