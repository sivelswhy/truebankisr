// Local test server: serves this folder and routes /api/max and /api/leumi
// to their relays. Listens on 127.0.0.1 only. Run: node dev-server.js
import http from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import * as max from "./api/max.js";
import * as leumi from "./api/leumi.js";

const root = fileURLToPath(new URL(".", import.meta.url));
const port = Number(process.env.PORT ?? 3100);
const types = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css", ".png": "image/png" };
const relays = { "/api/max": max, "/api/leumi": leumi };

http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const relay = relays[url.pathname];
  if (relay) {
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const request = new Request(url, { method: req.method, headers: req.headers, body: req.method === "POST" ? Buffer.concat(chunks) : undefined });
    const handler = { POST: relay.POST, GET: relay.GET, OPTIONS: relay.OPTIONS }[req.method];
    if (!handler) { res.writeHead(405).end(); return; }
    const answer = await handler(request);
    res.writeHead(answer.status, Object.fromEntries(answer.headers));
    res.end(Buffer.from(await answer.arrayBuffer()));
    return;
  }
  const file = normalize(join(root, url.pathname === "/" ? "index.html" : url.pathname));
  if (!file.startsWith(root) || file.includes("/api/") || /test|dev-server|package|vercel/.test(file.slice(root.length))) {
    res.writeHead(404).end("not found");
    return;
  }
  try {
    const body = await readFile(file);
    res.writeHead(200, { "Content-Type": types[extname(file)] ?? "application/octet-stream", "Cache-Control": "no-store" });
    res.end(body);
  } catch {
    res.writeHead(404).end("not found");
  }
}).listen(port, "127.0.0.1", () => console.log(`http://127.0.0.1:${port}`));
