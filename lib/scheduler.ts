import { refresh } from './service.ts';
import { loadSession } from './vault.ts';

const EVERY_MS = Number(process.env.REFRESH_MINUTES ?? 60) * 60_000;

// Banks don't love logins at 3 a.m.; only refresh during the day in Israel.
function daytimeInIsrael(now = new Date()): boolean {
  const hour = Number(new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Jerusalem', hour: '2-digit', hour12: false }).format(now));
  return hour >= 7 && hour < 23;
}

export function startBackgroundRefresh(): void {
  if (EVERY_MS <= 0) return;
  setInterval(async () => {
    const session = await loadSession();
    if (session?.mode !== 'live' || !daytimeInIsrael()) return;
    try {
      await refresh(session);
      console.log('[scheduler] balance refreshed');
    } catch (e) {
      console.error('[scheduler] refresh failed:', (e as Error).message);
    }
  }, EVERY_MS).unref();
}
