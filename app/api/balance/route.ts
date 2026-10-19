import { errorResponse, refresh } from '@/lib/service.ts';
import { loadSession } from '@/lib/vault.ts';

export const dynamic = 'force-dynamic';

// Logs into Leumi + Max with the saved credentials and recomputes (30–90 s).
export async function POST() {
  const session = await loadSession();
  if (!session) return Response.json({ errors: { general: 'NOT_SIGNED_IN' } }, { status: 401 });
  try {
    return Response.json(await refresh(session));
  } catch (e) {
    return errorResponse(e);
  }
}
