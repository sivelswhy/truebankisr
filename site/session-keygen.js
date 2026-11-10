// Makes the relay's session secret (AES-256), used to seal session tokens so
// the bank password isn't needed on every refresh. Put it in Vercel:
//   node session-keygen.js | vercel env add SESSION_SECRET production
// Separate from RELAY_PRIVATE_KEY (keygen.js), which only wraps the one-time
// request key. Every warm instance needs the same SESSION_SECRET, or a token
// sealed by one instance can't be opened by another.
import { randomBytes } from "node:crypto";

process.stdout.write(randomBytes(32).toString("base64"));
