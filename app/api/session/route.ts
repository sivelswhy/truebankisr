import { clearSnapshot, errorResponse, readSnapshot, refresh } from '@/lib/service.ts';
import { clearSession, loadSession, saveSession, type Login, type Session } from '@/lib/vault.ts';

export const dynamic = 'force-dynamic';

// Whether accounts are connected, plus the last known balance.
export async function GET() {
  const session = await loadSession();
  return Response.json({ connected: !!session, snapshot: session ? await readSnapshot() : null });
}

const isLogin = (v: unknown): v is Login =>
  typeof v === 'object' && v !== null &&
  typeof (v as Login).username === 'string' && (v as Login).username.trim() !== '' &&
  typeof (v as Login).password === 'string' && (v as Login).password !== '';

// Sign in: credentials are only saved once both sites accepted them.
export async function POST(req: Request) {
  const body = await req.json().catch(() => null);
  let session: Session;
  if (body?.demo === true) {
    session = { mode: 'demo' };
  } else if (isLogin(body?.leumi) && isLogin(body?.max)) {
    session = {
      mode: 'live',
      leumi: { username: body.leumi.username.trim(), password: body.leumi.password },
      max: { username: body.max.username.trim(), password: body.max.password },
    };
  } else {
    return Response.json({ errors: { general: 'FILL_BOTH' } }, { status: 400 });
  }

  try {
    const snapshot = await refresh(session);
    await saveSession(session);
    return Response.json({ connected: true, snapshot });
  } catch (e) {
    return errorResponse(e);
  }
}

// Sign out: forget the credentials and the cached balance.
export async function DELETE() {
  await Promise.all([clearSession(), clearSnapshot()]);
  return Response.json({ connected: false, snapshot: null });
}
