// Keeps the balance fresh in the background while the server runs, so the
// app opens on recent data without signing in again.
export async function register() {
  if (process.env.NEXT_RUNTIME !== 'nodejs') return;
  const { startBackgroundRefresh } = await import('./lib/scheduler.ts');
  startBackgroundRefresh();
}
