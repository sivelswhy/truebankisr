import { readPrefs, updatePrefs } from '@/lib/prefs.ts';

export const dynamic = 'force-dynamic';

// First name, hidden amounts, alert threshold, budgets and purchase notes.
export async function GET() {
  return Response.json(await readPrefs());
}

// Merges the fields sent into the saved ones.
export async function PUT(req: Request) {
  const body = await req.json().catch(() => null);
  if (!body || typeof body !== 'object') return Response.json({ errors: { general: 'UNKNOWN' } }, { status: 400 });
  return Response.json(await updatePrefs(body));
}
