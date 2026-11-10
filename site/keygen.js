// Makes the relay's key pair. Put the private part in Vercel:
//   node keygen.js | vercel env add RELAY_PRIVATE_KEY production
// The public part is derived from it and served by GET /api/max.
import { generateKeyPairSync } from "node:crypto";

const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
process.stdout.write(Buffer.from(privateKey.export({ type: "pkcs8", format: "pem" })).toString("base64"));
