import { demoAnswer, demoLeumi } from "./demo.js";
import { LEUMI_ORIGIN, LEUMI_URL, OPENER_NAME, bookmarkletHref } from "./leumi.js";
import { ICONS } from "./icons.js";

const NS = "http://www.w3.org/2000/svg"; // before anything that builds an icon at load time
import { parseAll, upcoming, purchases, spendingByCategory, monthlyTotals, recurring, parseLeumi, trueBalance, israelDay, daysUntil, CATEGORY_COLORS } from "./lib.js";

const fr = (navigator.language || "en").toLowerCase().startsWith("fr");
const lang = fr ? "fr" : "en";
document.documentElement.lang = lang;

const T = fr ? {
  lead: "Ton prochain débit Max et tes dépenses, lus depuis ton compte Max.",
  user: "Identifiant Max", pass: "Mot de passe Max", go: "Lire mon compte Max", busy: "Lecture en cours…",
  leumiTitle: "Leumi", leumiUser: "Identifiant Leumi", leumiPass: "Mot de passe Leumi", leumiGo: "Lire mon compte Leumi", leumiBusy: "Connexion à Leumi (jusqu’à une minute)…",
  leumiPrivacy: "Comme pour Max : ton mot de passe Leumi passe par un relais qui lance un vrai navigateur (Leumi ne se connecte pas avec un simple formulaire), chiffré dans les deux sens, jamais enregistré. Leumi vérifie que c’est un vrai navigateur, ce qui prend un peu de temps.",
  leumiRefused: "Leumi a refusé cette connexion. Vérifie ton identifiant et ton mot de passe.",
  leumiBlocked: "Cet abonnement Leumi est bloqué.", leumiChangePassword: "Leumi demande de changer le mot de passe : fais-le sur leumi.co.il, puis réessaie ici.",
  leumiDown: "Leumi n’a pas répondu comme prévu. Réessaie plus tard.", leumiSessionLost: "La session Leumi a expiré, reconnecte-toi.", refreshLeumi: "Actualiser Leumi",
  advancedLeumi: "Autre méthode : un favori (aucun serveur ne voit alors ton mot de passe Leumi)",
  step1: "1. Glisse ce bouton dans ta barre de favoris :", bookmarkName: "Leumi → True Balance", dragOnly: "Un clic ici ne fait rien : glisse-le dans la barre de favoris.",
  step2: "2. Ouvre Leumi depuis ici et connecte-toi :", openLeumi: "Ouvrir Leumi", step3: "3. Sur la page de Leumi, une fois connecté, clique sur le favori.",
  leumiBad: "La réponse de Leumi n’a pas pu être lue.", leumiBalance: "Solde Leumi", really: "Vraiment disponible", leumiMovements: "Compte Leumi",
  connect: "Ajouter une banque", back: "Retour au tableau de bord", noMax: "Max n’est pas connecté : connecte-le pour voir le prochain débit et les achats.",
  afterMax: (leumi, max) => `Leumi ${leumi} − Max ${max}`,
  testHint: "Compte test : identifiant test, mot de passe test (données d’exemple, rien n’est envoyé).",
  demo: "Essayer avec des données d’exemple", demoNote: "Données d’exemple, rien n’est lu depuis Max.",
  privacy: "Ton mot de passe est envoyé à un relais sans état, uniquement pour ouvrir ta session chez Max. Il n’est ni enregistré ni journalisé, et ce site ne garde rien : tout disparaît quand tu fermes la page. Leumi n’est pas lu ici, seulement Max.",
  refused: "Max a refusé cette connexion. Vérifie ton identifiant et ton mot de passe.",
  rate: "Trop d’essais. Attends une minute.",
  down: "Max n’a pas répondu comme prévu. Réessaie plus tard.",
  offline: "Pas de connexion.",
  next: "Prochain débit Max", inDays: (n) => n === 1 ? "demain" : `dans ${n} jours`, nothing: "Rien à débiter",
  upcoming: "Débits à venir", latest: "Derniers achats", month: "Dépenses du mois", none: "Aucun achat.",
  search: "Rechercher un achat…", allCats: "Toutes les catégories", showMore: "Afficher plus", exportCsv: "Exporter en CSV",
  count: (shown, total) => `${shown} sur ${total} achats`, cols: { date: "Date", merchant: "Commerçant", cat: "Catégorie", card: "Carte", amount: "Montant" },
  updated: "Mis à jour à", filterHint: "Touche / pour chercher", clearFilter: "Tout afficher",
  refresh: "Actualiser Max", sessionLost: "La session Max a expiré, reconnecte-toi.",
  recurringTitle: "Prélèvements réguliers", perMonth: (v) => `${v} par mois`, allMonths: "Tous les mois", months: "Derniers mois", sortBy: "Trier par",
  pending: "En attente", hide: "Masquer les montants", show: "Afficher les montants", forget: "Oublier et fermer",
  foreign: (n) => `${n} achat(s) en devise étrangère ne sont pas comptés.`,
  cat: { insurance: "Assurance", energy: "Énergie", fashion: "Mode", home: "Maison", travel: "Voyage", electronics: "Électronique",
    groceries: "Courses", books: "Livres", leisure: "Loisirs", transport: "Transport", government: "Administration", health: "Santé",
    telecom: "Télécom", other: "Autre", max: "Max", cash: "Espèces", transfer: "Virement", pets: "Animaux", beauty: "Beauté",
    restaurants: "Restaurants", fx: "Change", uncategorized: "Sans catégorie" },
} : {
  lead: "Your next Max debit and what you spent, read from your own Max account.",
  user: "Max username", pass: "Max password", go: "Read my Max account", busy: "Reading…",
  leumiTitle: "Leumi", leumiUser: "Leumi username", leumiPass: "Leumi password", leumiGo: "Read my Leumi account", leumiBusy: "Signing in to Leumi (up to a minute)…",
  leumiPrivacy: "Like Max: your Leumi password goes through a relay that runs a real browser (Leumi doesn't accept a plain form), encrypted both ways, never stored. Leumi checks it's a real browser, which takes a little time.",
  leumiRefused: "Leumi refused this sign-in. Check your username and password.",
  leumiBlocked: "This Leumi subscription is blocked.", leumiChangePassword: "Leumi is asking for a password change: do it on leumi.co.il, then try again here.",
  leumiDown: "Leumi did not answer as expected. Try again later.", leumiSessionLost: "The Leumi session expired, sign in again.", refreshLeumi: "Refresh Leumi",
  advancedLeumi: "Another way: a bookmark (then no server ever sees your Leumi password)",
  step1: "1. Drag this button to your bookmarks bar:", bookmarkName: "Leumi → True Balance", dragOnly: "Clicking it here does nothing: drag it to the bookmarks bar.",
  step2: "2. Open Leumi from here and sign in:", openLeumi: "Open Leumi", step3: "3. On Leumi's page, once signed in, click the bookmark.",
  leumiBad: "The Leumi answer could not be read.", leumiBalance: "Leumi balance", really: "Really available", leumiMovements: "Leumi account",
  connect: "Add a bank", back: "Back to the dashboard", noMax: "Max is not connected: connect it to see the next debit and purchases.",
  afterMax: (leumi, max) => `Leumi ${leumi} − Max ${max}`,
  testHint: "Test account: username test, password test (sample data, nothing is sent).",
  demo: "Try it with sample data", demoNote: "Sample data, nothing is read from Max.",
  privacy: "Your password goes to a stateless relay, only to open your session at Max. It is neither stored nor logged, and this site keeps nothing: everything is gone when you close the page. Leumi is not read here, only Max.",
  refused: "Max refused this sign-in. Check your username and password.",
  rate: "Too many attempts. Wait a minute.",
  down: "Max did not answer as expected. Try again later.",
  offline: "No connection.",
  next: "Next Max debit", inDays: (n) => n === 1 ? "tomorrow" : `in ${n} days`, nothing: "Nothing to debit",
  upcoming: "Upcoming debits", latest: "Latest purchases", month: "Spending this month", none: "No purchases.",
  search: "Search purchases…", allCats: "All categories", showMore: "Show more", exportCsv: "Export as CSV",
  count: (shown, total) => `${shown} of ${total} purchases`, cols: { date: "Date", merchant: "Merchant", cat: "Category", card: "Card", amount: "Amount" },
  updated: "Updated at", filterHint: "Press / to search", clearFilter: "Show all",
  refresh: "Refresh Max", sessionLost: "The Max session expired, sign in again.",
  recurringTitle: "Recurring charges", perMonth: (v) => `${v} a month`, allMonths: "All months", months: "Last months", sortBy: "Sort by",
  pending: "Pending", hide: "Hide amounts", show: "Show amounts", forget: "Forget and close",
  foreign: (n) => `${n} purchase(s) in a foreign currency are not counted.`,
  cat: { insurance: "Insurance", energy: "Energy", fashion: "Fashion", home: "Home", travel: "Travel", electronics: "Electronics",
    groceries: "Groceries", books: "Books", leisure: "Leisure", transport: "Transport", government: "Government", health: "Health",
    telecom: "Telecom", other: "Other", max: "Max", cash: "Cash", transfer: "Transfer", pets: "Pets", beauty: "Beauty",
    restaurants: "Restaurants", fx: "Exchange", uncategorized: "Uncategorized" },
};

// On GitHub Pages the static files are served from sivelswhy.github.io, but the
// relay (which needs a server) only runs on Vercel: calls go there instead.
// On Vercel itself this stays empty, so calls are same-origin (no CORS needed).
const RELAY = location.hostname.endsWith("github.io") ? "https://site-pi-eight-47.vercel.app" : "";

const $ = (id) => document.getElementById(id);
const money = new Intl.NumberFormat(lang, { style: "currency", currency: "ILS" });
const shortDay = (day) => new Date(`${day}T12:00:00`).toLocaleDateString(lang, { day: "numeric", month: "short" });
const longDay = (day) => new Date(`${day}T12:00:00`).toLocaleDateString(lang, { weekday: "long", day: "numeric", month: "long" });

/** Element with text only: merchant names are never put in HTML. */
function el(tag, props = {}, ...kids) {
  const node = document.createElement(tag);
  const { class: cls, text, style, ...rest } = props;
  if (cls) node.className = cls;
  if (text !== undefined) node.textContent = text;
  if (style) Object.assign(node.style, style);
  for (const [k, v] of Object.entries(rest)) node.setAttribute(k, v);
  for (const kid of kids.flat()) if (kid) node.append(kid);
  return node;
}

$("lead").textContent = T.lead;
$("l-user").textContent = T.user;
$("l-pass").textContent = T.pass;
$("go").textContent = T.go;
$("privacy").replaceChildren(icon("Lock", { size: 16 }), el("span", { text: T.privacy }));
$("demo").textContent = T.demo;
$("back").textContent = T.back;
$("back").addEventListener("click", () => state && render());
$("test-hint").textContent = T.testHint;

let state = null; // in memory only, nothing is saved
const newState = () => ({ txns: [], max: false, leumi: null, leumiSession: null, hidden: false, demo: false });

const b64 = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes)));
const unb64 = (str) => Uint8Array.from(atob(str), (c) => c.charCodeAt(0));

// Everything the relay sees is encrypted both ways: the browser wraps a
// one-time AES key with the relay's RSA public key for the request, and sends
// a second one-time key (`responseKey`) the relay must use to encrypt its
// answer, so neither direction is readable in the clear on the wire.
let cachedPublicKey;
async function relayPublicKey() {
  if (cachedPublicKey) return cachedPublicKey;
  const res = await fetch(`${RELAY}/api/max`, { cache: "no-store", credentials: "omit" });
  if (!res.ok) throw new Error("no key");
  cachedPublicKey = (await res.json()).publicKey;
  return cachedPublicKey;
}

/** Encrypts `fields` for a relay: returns the POST body and the key to decrypt the answer with. */
async function sealEnvelope(fields) {
  const rsa = await crypto.subtle.importKey("jwk", await relayPublicKey(), { name: "RSA-OAEP", hash: "SHA-256" }, false, ["encrypt"]);
  const aes = await crypto.subtle.generateKey({ name: "AES-GCM", length: 256 }, true, ["encrypt"]);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const responseKeyBytes = crypto.getRandomValues(new Uint8Array(32));
  const responseKey = await crypto.subtle.importKey("raw", responseKeyBytes, { name: "AES-GCM" }, false, ["decrypt"]);
  const plain = new TextEncoder().encode(JSON.stringify({ ...fields, ts: Date.now(), responseKey: b64(responseKeyBytes) }));
  const ct = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, aes, plain);
  const k = await crypto.subtle.encrypt({ name: "RSA-OAEP" }, rsa, await crypto.subtle.exportKey("raw", aes));
  return { body: JSON.stringify({ v: 1, k: b64(k), iv: b64(iv), ct: b64(ct) }), responseKey };
}

/** Decrypts a successful (status 200) answer with the key `sealEnvelope` made. */
async function openAnswer(res, responseKey) {
  const { iv, ct } = await res.json();
  const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv: unb64(iv) }, responseKey, unb64(ct));
  return JSON.parse(new TextDecoder().decode(plain));
}

/** POSTs an encrypted request to a relay; decrypts a 200, passes through any error as-is (plain, no secret in it). */
async function callRelay(url, fields) {
  const { body, responseKey } = await sealEnvelope(fields);
  const res = await fetch(url, {
    method: "POST", headers: { "Content-Type": "application/json" }, body,
    cache: "no-store", credentials: "omit", referrerPolicy: "no-referrer",
  });
  return res.status === 200 ? { ok: true, body: await openAnswer(res, responseKey) } : { ok: false, status: res.status, error: (await res.json().catch(() => ({}))).error };
}


// ---- Leumi: the headless-browser relay (/api/leumi), or a bookmark as a
// no-server-ever-sees-the-password alternative via postMessage ----

function buildLeumiPanel() {
  const box = $("leumi-card");
  const form = el("form", { id: "leumi-form" },
    el("label", { for: "lu", text: T.leumiUser }),
    el("input", { id: "lu", name: "username", autocomplete: "username", autocapitalize: "none", autocorrect: "off", spellcheck: "false", required: "" }),
    el("label", { for: "lp", text: T.leumiPass }),
    el("input", { id: "lp", name: "password", type: "password", autocomplete: "current-password", required: "" }),
    el("button", { class: "full", id: "lgo", type: "submit", text: T.leumiGo }),
    el("p", { class: "error", id: "lerr", role: "alert", hidden: "" }));

  const link = el("a", { class: "bm", href: bookmarkletHref(location.origin), title: T.dragOnly, draggable: "true" }, icon("Bank", { size: 18 }), el("span", { text: T.bookmarkName }));
  link.addEventListener("click", (e) => { e.preventDefault(); alert(T.dragOnly); });
  const openBtn = iconButton("Bank", T.openLeumi);
  openBtn.addEventListener("click", () => window.open(LEUMI_URL, OPENER_NAME));
  const advanced = el("details", {},
    el("summary", { text: T.advancedLeumi }),
    el("p", { class: "step", text: T.step1 }), el("p", {}, link),
    el("p", { class: "step", text: T.step2 }), el("p", {}, openBtn),
    el("p", { class: "step", text: T.step3 }));

  box.replaceChildren(
    el("h2", { text: T.leumiTitle }),
    el("div", { class: "card pad" }, form, advanced),
    el("p", { class: "note" }, icon("Lock", { size: 16 }), el("span", { text: T.leumiPrivacy })));

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const username = $("lu").value.trim();
    const password = $("lp").value;
    $("lp").value = "";
    const err = $("lerr");
    err.hidden = true;
    $("lgo").disabled = true;
    $("lgo").textContent = T.leumiBusy;
    try {
      const r = await callRelay(`${RELAY}/api/leumi`, { mode: "login", username, password });
      if (!r.ok) {
        err.textContent = { refused: T.leumiRefused, blocked: T.leumiBlocked, changePassword: T.leumiChangePassword, "rate limited": T.rate }[r.error] ?? T.leumiDown;
        err.hidden = false;
        return;
      }
      state ??= newState();
      state.leumi = parseLeumi(String(r.body.body), String(r.body.number ?? ""));
      state.leumiSession = r.body.session;
      $("lu").value = "";
      render();
    } catch {
      err.textContent = navigator.onLine ? T.leumiDown : T.offline;
      err.hidden = false;
    } finally {
      $("lgo").disabled = false;
      $("lgo").textContent = T.leumiGo;
    }
  });
}
buildLeumiPanel();

window.addEventListener("message", (e) => {
  if (!LEUMI_ORIGIN.test(e.origin) || !e.data || e.data.type !== "tb-leumi") return;
  try {
    const leumi = parseLeumi(String(e.data.body), String(e.data.number ?? ""));
    state ??= newState();
    state.leumi = leumi;
    e.source?.postMessage({ type: "tb-ack" }, e.origin);
    render();
  } catch {
    showError(T.leumiBad);
  }
});

// Opened by the bookmark in a window of its own: tell it we are ready for the data.
{
  const asked = location.hash.match(/^#leumi=(.+)$/);
  if (asked && window.opener) {
    try {
      const origin = decodeURIComponent(asked[1]);
      if (LEUMI_ORIGIN.test(origin)) window.opener.postMessage({ type: "tb-ready" }, origin);
    } catch { /* not for us */ }
  }
  if (asked) history.replaceState(null, "", location.pathname + location.search);
}

function showError(message) {
  const e = $("err");
  e.textContent = message;
  e.hidden = !message;
}

$("form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const username = $("u").value.trim();
  const password = $("p").value;
  $("p").value = "";
  showError("");
  // The test account never leaves the browser: sample data, no relay, no Max.
  if (username === "test" && password === "test") {
    $("u").value = "";
    $("demo").click();
    return;
  }
  $("go").disabled = true;
  $("go").textContent = T.busy;
  try {
    const r = await callRelay(`${RELAY}/api/max`, { mode: "login", username, password });
    if (!r.ok) return showError(r.status === 401 ? T.refused : r.status === 429 ? T.rate : T.down);
    state = Object.assign(state ?? newState(), { txns: parseAll(r.body), max: true, maxSession: r.body.session });
    $("u").value = "";
    render();
  } catch {
    showError(navigator.onLine ? T.down : T.offline);
  } finally {
    $("go").disabled = false;
    $("go").textContent = T.go;
  }
});

const PAGE = 50;
const currency = (code) => new Intl.NumberFormat(lang, { style: "currency", currency: code });
const monthName = (m) => new Date(`${m}-15T12:00:00`).toLocaleDateString(lang, { month: "long", year: "numeric" });
const monthShort = (m) => new Date(`${m}-15T12:00:00`).toLocaleDateString(lang, { month: "short" });

function svg(tag, attrs = {}, ...kids) {
  const node = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  for (const kid of kids.flat()) if (kid) node.append(kid);
  return node;
}

function amountCell(t) {
  const cell = el("td", { class: "num amt", text: money.format(-t.amount) });
  if (t.original) cell.append(el("small", { text: currency(t.original.currency).format(t.original.amount) }));
  return cell;
}

function csv(rows) {
  const q = (v) => `"${String(v).replace(/"/g, '""')}"`;
  const head = [T.cols.date, T.cols.merchant, T.cols.cat, T.cols.card, T.cols.amount, "ILS"].map(q).join(",");
  return [head, ...rows.map((t) => [t.day, t.description, T.cat[t.category ?? "uncategorized"], t.card ?? "", -t.amount, t.currency].map(q).join(","))].join("\n");
}

function download(name, text) {
  const url = URL.createObjectURL(new Blob(["﻿" + text], { type: "text/csv;charset=utf-8" }));
  const a = el("a", { href: url, download: name });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

const CATEGORY_ICON = { insurance: "ShieldCheck", energy: "GasStation", fashion: "Tshirt", home: "Sofa", travel: "Airplane", electronics: "Laptop",
  groceries: "Cart", books: "Book", leisure: "Ticket", transport: "Bus", government: "Courthouse", health: "HeartPulse", telecom: "Mobile",
  other: "Category", max: "Card", cash: "Money", transfer: "ArrowSwapHorizontal", pets: "Paw", beauty: "MagicStar", restaurants: "ForkKnife",
  fx: "DollarCircle", uncategorized: "HelpCircle" };

/** A Reicon icon (inlined in icons.js): size in px, weight "O" outline or "F" filled. The markup is our own constant. */
function icon(name, { size = 18, weight = "O" } = {}) {
  const data = ICONS[name] ?? ICONS.HelpCircle;
  const node = svg("svg", { viewBox: "0 0 24 24", width: size, height: size, fill: "none", "aria-hidden": "true", class: "ico-svg" });
  node.innerHTML = data[weight] ?? data.O;
  return node;
}

/** A tinted square with an icon in it. */
const tile = (name, color, weight = "F") => {
  const t = el("div", { class: "ico", "aria-hidden": "true", style: { background: `${color}26`, color } });
  t.append(icon(name, { size: 19, weight }));
  return t;
};

const compact = new Intl.NumberFormat(lang, { notation: "compact", maximumFractionDigits: 1 });

/** Rounded on top only, flat on the baseline. */
const roundedTop = (x, y, w, h, r) => {
  const k = Math.min(r, w / 2, h);
  return `M${x},${y + h} V${y + k} Q${x},${y} ${x + k},${y} H${x + w - k} Q${x + w},${y} ${x + w},${y + k} V${y + h} Z`;
};

/** A "nice" ceiling for the axis: 1, 2, 2.5, 5 or 10 times a power of ten. */
const niceMax = (v) => {
  const p = 10 ** Math.floor(Math.log10(v || 1));
  return ([1, 2, 2.5, 5, 10].find((m) => m * p >= v) ?? 10) * p;
};

/** Bars per month with gridlines, an average line and a value above each bar. Click or Enter selects, again clears. */
function monthChart(months, selected, pick, current) {
  const slot = 96, left = 46, top = 26, bottom = 28, H = 210;
  const W = left + months.length * slot + 8;
  const top$ = niceMax(Math.max(...months.map((m) => m.total), 1));
  const y = (v) => top + (H - top - bottom) * (1 - v / top$);
  const avg = months.reduce((sum, m) => sum + m.total, 0) / months.length;

  const grid = [0, 0.5, 1].map((f) => {
    const v = top$ * f;
    return svg("g", {},
      svg("line", { x1: left, x2: W - 4, y1: y(v), y2: y(v), class: "grid" }),
      Object.assign(svg("text", { x: left - 8, y: y(v) + 4, "text-anchor": "end", class: "axis" }), { textContent: v ? compact.format(v) : "0" }));
  });

  const bars = months.map((m, i) => {
    const w = 44, x = left + i * slot + (slot - w) / 2, h = Math.max(4, y(0) - y(m.total));
    const on = m.month === selected;
    const partial = m.month === current;
    const g = svg("g", { class: `bar${on ? " on" : ""}${partial ? " partial" : ""}`, role: "button", tabindex: "0", "aria-pressed": String(on),
      "aria-label": `${monthName(m.month)}: ${money.format(m.total)}` },
      svg("title", {}, Object.assign(document.createTextNode(`${monthName(m.month)} · ${money.format(m.total)}${partial ? " …" : ""}`))),
      svg("rect", { x: left + i * slot, y: 0, width: slot, height: H, fill: "transparent" }),
      svg("path", { d: roundedTop(x, y(m.total), w, h, 9), class: "fill", fill: "url(#barGradient)" }),
      Object.assign(svg("text", { x: x + w / 2, y: y(m.total) - 8, "text-anchor": "middle", class: "val" }), { textContent: compact.format(m.total) }),
      Object.assign(svg("text", { x: x + w / 2, y: H - 8, "text-anchor": "middle", class: "lab" }), { textContent: monthShort(m.month) }));
    const choose = () => pick(on ? "" : m.month);
    g.addEventListener("click", choose);
    g.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); choose(); } });
    return g;
  });

  const defs = svg("defs", {}, svg("linearGradient", { id: "barGradient", x1: 0, y1: 0, x2: 0, y2: 1 },
    svg("stop", { offset: "0%", style: "stop-color: var(--accent)" }), svg("stop", { offset: "100%", style: "stop-color: var(--indigo)" })));
  const average = months.length > 2 ? svg("g", {},
    svg("line", { x1: left, x2: W - 4, y1: y(avg), y2: y(avg), class: "avg" }),
    Object.assign(svg("text", { x: W - 6, y: y(avg) - 5, "text-anchor": "end", class: "avgl" }), { textContent: `Ø ${compact.format(avg)}` })) : null;
  return svg("svg", { viewBox: `0 0 ${W} ${H}`, class: "chart", role: "group", "aria-label": T.months }, defs, grid, bars, average);
}

function iconButton(name, label) {
  const b = el("button", { class: "plain btn-i", type: "button" }, icon(name, { size: 18 }), el("span", { text: label }));
  return b;
}
function setIconButton(b, name, label) {
  b.replaceChildren(icon(name, { size: 18 }), el("span", { text: label }));
}

/** Back to the connect screen, keeping what is already loaded. */
function showLogin() {
  $("dash").hidden = true;
  $("login").hidden = false;
  $("title").hidden = false;
  $("lead").hidden = false;
  $("back-wrap").hidden = !state;
}

function render() {
  const dash = $("dash");
  const today = israelDay();
  const { charges, foreign } = upcoming(state.txns, today);
  const next = charges[0];
  const all = purchases(state.txns);
  const months = monthlyTotals(state.txns).slice(-6);
  const view = { query: "", cat: "", shown: PAGE, month: months.some((m) => m.month === today.slice(0, 7)) ? today.slice(0, 7) : "",
                 sort: "day", dir: -1 };

  // Top bar
  const toggle = iconButton("EyeOff", T.hide);
  toggle.addEventListener("click", () => {
    state.hidden = !state.hidden;
    document.body.classList.toggle("hide", state.hidden);
    setIconButton(toggle, state.hidden ? "Eye" : "EyeOff", state.hidden ? T.show : T.hide);
  });
  const forget = iconButton("Logout", T.forget);
  forget.addEventListener("click", () => {
    state = null;
    document.body.classList.remove("hide");
    dash.replaceChildren();
    dash.hidden = true;
    $("login").hidden = false;
    $("title").hidden = false;
    $("lead").hidden = false;
    $("u").focus();
  });
  const connect = iconButton("Plug", T.connect);
  connect.addEventListener("click", showLogin);
  const refreshMax = state.maxSession ? iconButton("Repeat", T.refresh) : null;
  refreshMax?.addEventListener("click", async () => {
    refreshMax.disabled = true;
    try {
      const r = await callRelay(`${RELAY}/api/max`, { mode: "refresh", token: state.maxSession });
      if (!r.ok) {
        if (r.error === "session") { state.maxSession = null; showLogin(); showError(T.sessionLost); return; }
        return;
      }
      state.txns = parseAll(r.body);
      state.maxSession = r.body.session;
      render();
    } finally {
      refreshMax.disabled = false;
    }
  });
  const refreshLeumi = state.leumiSession ? iconButton("Repeat", T.refreshLeumi) : null;
  refreshLeumi?.addEventListener("click", async () => {
    refreshLeumi.disabled = true;
    try {
      const r = await callRelay(`${RELAY}/api/leumi`, { mode: "refresh", token: state.leumiSession });
      if (!r.ok) {
        if (r.error === "session") { state.leumiSession = null; showLogin(); showError(T.leumiSessionLost); return; }
        return;
      }
      state.leumi = parseLeumi(String(r.body.body), String(r.body.number ?? ""));
      state.leumiSession = r.body.session;
      render();
    } finally {
      refreshLeumi.disabled = false;
    }
  });
  const sources = [state.max ? "Max" : null, state.leumi ? "Leumi" : null].filter(Boolean).join(" + ");
  const bar = el("div", { class: "bar-top" },
    el("div", { class: "grow" }, el("h1", { text: "True Balance" }),
      el("div", { class: "sub", text: `${state.demo ? T.demoNote : sources} · ${T.updated} ${new Date().toLocaleTimeString(lang, { hour: "2-digit", minute: "2-digit" })}` })),
    state.max && state.leumi ? null : connect, refreshMax, refreshLeumi, toggle, forget);

  // Side column
  const side = el("div", { class: "side" });
  if (state.leumi) {
    const real = state.max ? trueBalance(state.leumi.balance, charges) : state.leumi.balance;
    side.append(el("div", { class: "card hero" },
      el("div", { class: "k", text: state.max ? T.really : T.leumiBalance }),
      el("div", { class: "v", text: money.format(real), style: real < 0 ? { color: "var(--red)" } : {} }),
      state.max ? el("div", { class: "s", text: T.afterMax(money.format(state.leumi.balance), money.format(next?.total ?? 0)) }) : null));
  }
  if (state.max) {
    side.append(el("div", { class: "card hero" },
      el("div", { class: "k", text: T.next }),
      el("div", { class: "v", text: next ? money.format(next.total) : T.nothing }),
      next ? el("div", { class: "s", text: `${longDay(next.day)} · ${T.inDays(daysUntil(next.day, today))}` }) : null));
  } else {
    side.append(el("p", { class: "note", text: T.noMax }));
  }

  if (charges.length > 1) {
    side.append(el("div", {}, el("h2", { text: T.upcoming }), el("div", { class: "card" }, charges.map((c) =>
      el("div", { class: "row" },
        tile("Calendar", "#0A84FF", "O"),
        el("div", { class: "grow" }, el("div", { class: "t", text: longDay(c.day) }), el("div", { class: "d", text: T.inDays(daysUntil(c.day, today)) })),
        el("div", { class: "amt", text: money.format(c.total) }))))));
  }

  const spendingBox = el("div");
  if (state.max) side.append(spendingBox);

  if (state.leumi) {
    const rows = state.leumi.movements.slice(0, 10).map((m) => el("div", { class: "row" },
      tile(m.amount >= 0 ? "ArrowDownLeft" : "ArrowUpRight", m.amount >= 0 ? "#30D158" : "#8E8E93", "O"),
      el("div", { class: "grow" }, el("div", { class: "t", text: m.description }),
        el("div", { class: "d", text: [shortDay(m.day), m.pending ? T.pending : null].filter(Boolean).join(" · ") })),
      el("div", { class: "amt", style: m.amount >= 0 ? { color: "var(--green)" } : {}, text: (m.amount >= 0 ? "+" : "") + money.format(m.amount) })));
    side.append(el("div", {}, el("h2", { text: `${T.leumiMovements}${state.leumi.number ? ` · ${state.leumi.number}` : ""}` }), el("div", { class: "card" }, rows)));
  }

  const regular = recurring(state.txns, today);
  if (regular.length) {
    const total = regular.reduce((sum, r) => sum + r.amount, 0);
    side.append(el("div", {},
      el("h2", { text: `${T.recurringTitle} · ${T.perMonth(money.format(total))}` }),
      el("div", { class: "card" }, regular.slice(0, 8).map((r) =>
        el("div", { class: "row" },
          tile("Repeat", "#AF52DE", "O"),
          el("div", { class: "grow" }, el("div", { class: "t", text: r.name }), el("div", { class: "d", text: `${T.next} ${shortDay(r.next)}` })),
          el("div", { class: "amt", text: money.format(r.amount) }))))));
  }
  if (foreign.length) side.append(el("p", { class: "note", text: T.foreign(foreign.length) }));

  // Purchases
  const search = el("input", { type: "search", placeholder: T.search, "aria-label": T.search });
  const searchField = el("div", { class: "field" }, icon("Search", { size: 18 }), search);
  const select = el("select", { "aria-label": T.allCats },
    el("option", { value: "", text: T.allCats }),
    [...new Set(all.map((t) => t.category ?? "uncategorized"))].sort((x, y) => T.cat[x].localeCompare(T.cat[y], lang))
      .map((k) => el("option", { value: k, text: T.cat[k] })));
  const exportBtn = iconButton("Download", T.exportCsv);
  const body = el("tbody");
  const footer = el("div", { class: "more" });
  const empty = el("p", { class: "note", text: T.none });
  const heads = [["day", T.cols.date, ""], ["description", T.cols.merchant, ""], [null, T.cols.cat, "col-cat"], [null, T.cols.card, "col-card"], ["amount", T.cols.amount, "num"]]
    .map(([key, label, cls]) => {
      const th = el("th", { class: cls });
      if (key) {
        const b = el("button", { class: "th", type: "button", title: `${T.sortBy} ${label}` });
        b.addEventListener("click", () => {
          view.dir = view.sort === key ? -view.dir : (key === "description" ? 1 : -1);
          view.sort = key;
          refresh();
        });
        th.append(b);
        th.sortKey = key;
        th.label = label;
        th.button = b;
      } else {
        th.textContent = label;
      }
      return th;
    });
  const table = el("table", {}, el("thead", {}, el("tr", {}, heads)), body);

  const filtered = () => {
    const q = view.query.trim().toLowerCase();
    const rows = all.filter((t) => (!view.month || t.day.startsWith(view.month))
      && (!view.cat || (t.category ?? "uncategorized") === view.cat)
      && (!q || t.description.toLowerCase().includes(q)));
    const by = { day: (t) => t.day, description: (t) => t.description.toLowerCase(), amount: (t) => -t.amount }[view.sort];
    return rows.sort((a, b) => (by(a) < by(b) ? -1 : by(a) > by(b) ? 1 : 0) * view.dir);
  };

  const chartBox = el("div", { class: "card pad" });
  const spendingRows = () => {
    const spending = spendingByCategory(state.txns, view.month);
    if (!spending.length) return el("div");
    const max = spending[0].total;
    const sum = spending.reduce((acc, sp) => acc + sp.total, 0);
    const rows = spending.map((sp) => {
      const color = CATEGORY_COLORS[sp.key];
      const row = el("button", { class: "row cat", type: "button", "aria-pressed": String(sp.key === view.cat), title: T.cat[sp.key] },
        tile(CATEGORY_ICON[sp.key] ?? "HelpCircle", color),
        el("div", { class: "grow" },
          el("div", { class: "line" }, el("span", { class: "t", text: T.cat[sp.key] }), el("span", { class: "amt", text: money.format(sp.total) })),
          el("div", { class: "line" },
            el("div", { class: "track" }, el("div", { class: "meter", style: { width: `${Math.max(3, (sp.total / max) * 100)}%`, background: `linear-gradient(90deg, ${color}, ${color}b3)` } })),
            el("span", { class: "pct", text: `${Math.round((sp.total / sum) * 100)} %` }))));
      row.addEventListener("click", () => { view.cat = view.cat === sp.key ? "" : sp.key; view.shown = PAGE; refresh(); });
      return row;
    });
    return el("div", {}, el("h2", { text: `${T.month} · ${view.month ? monthName(view.month) : T.allMonths}` }), el("div", { class: "card" }, rows));
  };

  function refresh() {
    chartBox.replaceChildren(monthChart(months, view.month, (m) => { view.month = m; view.shown = PAGE; refresh(); }, today.slice(0, 7)));
    spendingBox.replaceChildren(spendingRows());
    const rows = filtered();
    const page = rows.slice(0, view.shown);
    body.replaceChildren(...page.map((t) => el("tr", {},
      el("td", { class: "d", text: shortDay(t.day) }),
      el("td", {}, el("span", { class: "dot", style: { background: CATEGORY_COLORS[t.category ?? "uncategorized"] } }),
        t.description, t.pending ? el("span", { class: "pill", text: T.pending }) : null),
      el("td", { class: "col-cat d", text: T.cat[t.category ?? "uncategorized"] }),
      el("td", { class: "col-card d", text: t.card ? `•••• ${t.card}` : "" }),
      amountCell(t))));
    for (const th of heads) {
      if (!th.sortKey) continue;
      const active = th.sortKey === view.sort;
      th.button.replaceChildren(el("span", { text: th.label }), active ? icon(view.dir < 0 ? "ArrowDown" : "ArrowUp", { size: 13 }) : "");
      th.setAttribute("aria-sort", active ? (view.dir < 0 ? "descending" : "ascending") : "none");
    }
    table.hidden = rows.length === 0;
    empty.hidden = rows.length > 0;
    const more = el("button", { class: "plain", type: "button", text: T.showMore });
    more.addEventListener("click", () => { view.shown += PAGE; refresh(); });
    footer.replaceChildren(el("span", { text: T.count(page.length, rows.length) }), page.length < rows.length ? more : "");
    select.value = view.cat;
  }

  search.addEventListener("input", () => { view.query = search.value; view.shown = PAGE; refresh(); });
  select.addEventListener("change", () => { view.cat = select.value; view.shown = PAGE; refresh(); });
  exportBtn.addEventListener("click", () => download(`max-${view.month || "all"}.csv`, csv(filtered())));

  const main = !state.max ? el("div") : el("div", { class: "stack" },
    months.length > 1 ? el("div", {}, el("h2", { text: T.months }), chartBox) : null,
    el("div", {}, el("h2", { text: T.latest }),
      el("div", { class: "card" }, el("div", { class: "tools" }, searchField, select, exportBtn), table, empty, footer)));

  dash.replaceChildren(bar, el("div", { class: "layout" }, side, main));
  dash.hidden = false;
  $("login").hidden = true;
  $("title").hidden = true;
  $("lead").hidden = true;
  refresh();
  window.scrollTo(0, 0);
}

// "/" jumps to the search box on the dashboard.
document.addEventListener("keydown", (e) => {
  if (e.key !== "/" || !state || ["INPUT", "SELECT", "TEXTAREA"].includes(document.activeElement?.tagName)) return;
  e.preventDefault();
  document.querySelector("#dash input[type=search]")?.focus();
});

$("demo").addEventListener("click", () => {
  state = Object.assign(newState(), { txns: parseAll(demoAnswer()), max: true, leumi: demoLeumi(), demo: true });
  render();
});
if (new URLSearchParams(location.search).has("demo")) $("demo").click();
