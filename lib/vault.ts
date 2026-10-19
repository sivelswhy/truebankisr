import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';

export interface Login {
  username: string;
  password: string;
}

export type Session = { mode: 'demo' } | { mode: 'live'; leumi: Login; max: Login };

const DIR = path.join(process.cwd(), 'data');
const KEY_FILE = path.join(DIR, 'vault.key');
const VAULT_FILE = path.join(DIR, 'credentials.enc');

// Credentials are encrypted at rest with a random key that only this user can read.
async function key(): Promise<Buffer> {
  try {
    return await readFile(KEY_FILE);
  } catch {
    await mkdir(DIR, { recursive: true, mode: 0o700 });
    const k = randomBytes(32);
    await writeFile(KEY_FILE, k, { mode: 0o600 });
    return k;
  }
}

export async function saveSession(session: Session): Promise<void> {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', await key(), iv);
  const data = Buffer.concat([cipher.update(JSON.stringify(session), 'utf8'), cipher.final()]);
  await writeFile(VAULT_FILE, Buffer.concat([iv, cipher.getAuthTag(), data]), { mode: 0o600 });
}

export async function loadSession(): Promise<Session | null> {
  try {
    const blob = await readFile(VAULT_FILE);
    const decipher = createDecipheriv('aes-256-gcm', await key(), blob.subarray(0, 12));
    decipher.setAuthTag(blob.subarray(12, 28));
    return JSON.parse(Buffer.concat([decipher.update(blob.subarray(28)), decipher.final()]).toString('utf8'));
  } catch {
    return null;
  }
}

export async function clearSession(): Promise<void> {
  await rm(VAULT_FILE, { force: true });
}
