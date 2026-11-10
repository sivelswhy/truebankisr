// Shared by all three pages (index.html the dashboard, max.html and
// leumi.html the two sign-in pages): language strings, small DOM/SVG
// helpers, the relay's encryption, and the saved-session storage.

import { ICONS } from "./icons.js";

export const fr = (navigator.language || "en").toLowerCase().startsWith("fr");
export const lang = fr ? "fr" : "en";
document.documentElement.lang = lang;

export const T = fr ? {
  lead: "Ton prochain débit Max et tes dépenses, lus depuis ton compte Max.",
  user: "Identifiant Max", pass: "Mot de passe Max", go: "Lire mon compte Max", busy: "Lecture en cours…",
  leumiLead: "Le solde et les mouvements de ton compte Leumi.",
  leumiTitle: "Leumi", leumiUser: "Identifiant Leumi", leumiPass: "Mot de passe Leumi", leumiGo: "Lire mon compte Leumi", leumiBusy: "Connexion à Leumi (jusqu’à une minute)…",
  leumiPrivacy: "Comme pour Max : ton mot de passe Leumi passe par un relais qui lance un vrai navigateur (Leumi ne se connecte pas avec un simple formulaire), chiffré dans les deux sens, jamais enregistré. Un jeton de session reste 20 minutes sur cet appareil, pas ton mot de passe. Leumi vérifie que c’est un vrai navigateur, ce qui prend un peu de temps.",
  leumiRefused: "Leumi a refusé cette connexion. Vérifie ton identifiant et ton mot de passe.",
  leumiBlocked: "Cet abonnement Leumi est bloqué.", leumiChangePassword: "Leumi demande de changer le mot de passe : fais-le sur leumi.co.il, puis réessaie ici.",
  leumiDown: "Leumi n’a pas répondu comme prévu. Réessaie plus tard.", leumiTimeout: "La page de connexion Leumi n’a jamais abouti (peut-être une vérification anti-robot). Réessaie, ou utilise le favori plus bas.", leumiFirewall: "Le pare-feu de Leumi a rejeté cette connexion. Réessaie, ou utilise le favori plus bas.",
  leumiSessionLost: "La session Leumi a expiré, reconnecte-toi.", refreshLeumi: "Actualiser Leumi",
  advancedLeumi: "Autre méthode : un favori (aucun serveur ne voit alors ton mot de passe Leumi)",
  step1: "1. Glisse ce bouton dans ta barre de favoris :", bookmarkName: "Leumi → True Balance", dragOnly: "Un clic ici ne fait rien : glisse-le dans la barre de favoris.",
  step2: "2. Ouvre Leumi depuis ici et connecte-toi :", openLeumi: "Ouvrir Leumi", step3: "3. Sur la page de Leumi, une fois connecté, clique sur le favori.",
  leumiBad: "La réponse de Leumi n’a pas pu être lue.", leumiBalance: "Solde Leumi", really: "Vraiment disponible", leumiMovements: "Compte Leumi",
  connectMax: "Connecter Max", connectLeumi: "Connecter Leumi", connect: "Ajouter une banque", back: "Retour au tableau de bord",
  backHome: "← Retour à l’accueil", noMax: "Max n’est pas connecté : connecte-le pour voir le prochain débit et les achats.",
  afterMax: (leumi, max) => `Leumi ${leumi} − Max ${max}`,
  chooseTitle: "Connecter une banque", chooseLead: "Chaque banque a sa page, avec son propre formulaire.",
  testHint: "Compte test : identifiant test, mot de passe test (données d’exemple, rien n’est envoyé).",
  demo: "Essayer avec des données d’exemple", demoNote: "Données d’exemple, rien n’est lu depuis Max.",
  privacy: "Ton mot de passe est envoyé à un relais sans état, uniquement pour ouvrir ta session chez Max. Il n’est ni enregistré ni journalisé. Un jeton de session (jamais ton mot de passe, jamais tes données) reste sur cet appareil 20 minutes, pour ne pas redemander le mot de passe à chaque réouverture ; « Oublier » l’efface tout de suite.",
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
  leumiLead: "Your Leumi account's balance and movements.",
  leumiTitle: "Leumi", leumiUser: "Leumi username", leumiPass: "Leumi password", leumiGo: "Read my Leumi account", leumiBusy: "Signing in to Leumi (up to a minute)…",
  leumiPrivacy: "Like Max: your Leumi password goes through a relay that runs a real browser (Leumi doesn't accept a plain form), encrypted both ways, never stored. A session token stays on this device for 20 minutes, not your password. Leumi checks it's a real browser, which takes a little time.",
  leumiRefused: "Leumi refused this sign-in. Check your username and password.",
  leumiBlocked: "This Leumi subscription is blocked.", leumiChangePassword: "Leumi is asking for a password change: do it on leumi.co.il, then try again here.",
  leumiDown: "Leumi did not answer as expected. Try again later.", leumiTimeout: "Leumi's sign-in page never went through (possibly an anti-bot check). Try again, or use the bookmark below.", leumiFirewall: "Leumi's firewall rejected this sign-in. Try again, or use the bookmark below.",
  leumiSessionLost: "The Leumi session expired, sign in again.", refreshLeumi: "Refresh Leumi",
  advancedLeumi: "Another way: a bookmark (then no server ever sees your Leumi password)",
  step1: "1. Drag this button to your bookmarks bar:", bookmarkName: "Leumi → True Balance", dragOnly: "Clicking it here does nothing: drag it to the bookmarks bar.",
  step2: "2. Open Leumi from here and sign in:", openLeumi: "Open Leumi", step3: "3. On Leumi's page, once signed in, click the bookmark.",
  leumiBad: "The Leumi answer could not be read.", leumiBalance: "Leumi balance", really: "Really available", leumiMovements: "Leumi account",
  connectMax: "Connect Max", connectLeumi: "Connect Leumi", connect: "Add a bank", back: "Back to the dashboard",
  backHome: "← Back to the dashboard", noMax: "Max is not connected: connect it to see the next debit and purchases.",
  afterMax: (leumi, max) => `Leumi ${leumi} − Max ${max}`,
  chooseTitle: "Connect a bank", chooseLead: "Each bank has its own page, with its own form.",
  testHint: "Test account: username test, password test (sample data, nothing is sent).",
  demo: "Try it with sample data", demoNote: "Sample data, nothing is read from Max.",
  privacy: "Your password goes to a stateless relay, only to open your session at Max. It is neither stored nor logged. A session token (never your password, never your data) stays on this device for 20 minutes, so reopening the page doesn't ask for it again right away; \"Forget\" erases it at once.",
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

// On GitHub Pages the static files are served from sivelswhy.github.io, but
// the relay (which needs a server) only runs on Vercel: calls go there
// instead. On Vercel itself this stays empty, so calls are same-origin.
export const RELAY = location.hostname.endsWith("github.io") ? "https://site-pi-eight-47.vercel.app" : "";

export const $ = (id) => document.getElementById(id);

/** Element with text only: merchant names are never put in HTML. */
export function el(tag, props = {}, ...kids) {
  const node = document.createElement(tag);
  const { class: cls, text, style, ...rest } = props;
  if (cls) node.className = cls;
  if (text !== undefined) node.textContent = text;
  if (style) Object.assign(node.style, style);
  for (const [k, v] of Object.entries(rest)) node.setAttribute(k, v);
  for (const kid of kids.flat()) if (kid) node.append(kid);
  return node;
}

const NS = "http://www.w3.org/2000/svg";
export function svg(tag, attrs = {}, ...kids) {
  const node = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  for (const kid of kids.flat()) if (kid) node.append(kid);
  return node;
}

/** A Reicon icon (inlined in icons.js): size in px, weight "O" outline or "F" filled. */
export function icon(name, { size = 18, weight = "O" } = {}) {
  const data = ICONS[name] ?? ICONS.HelpCircle;
  const node = svg("svg", { viewBox: "0 0 24 24", width: size, height: size, fill: "none", "aria-hidden": "true", class: "ico-svg" });
  node.innerHTML = data[weight] ?? data.O;
  return node;
}

/** A tinted square with an icon in it. */
export const tile = (name, color, weight = "F") => {
  const t = el("div", { class: "ico", "aria-hidden": "true", style: { background: `${color}26`, color } });
  t.append(icon(name, { size: 19, weight }));
  return t;
};

export function iconButton(name, label) {
  return el("button", { class: "plain btn-i", type: "button" }, icon(name, { size: 18 }), el("span", { text: label }));
}
export function setIconButton(b, name, label) {
  b.replaceChildren(icon(name, { size: 18 }), el("span", { text: label }));
}

const b64 = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes)));
const unb64 = (str) => Uint8Array.from(atob(str), (c) => c.charCodeAt(0));

// Everything the relay sees is encrypted both ways: the browser wraps a
// one-time AES key with the relay's RSA public key for the request, and sends
// a second one-time key (`responseKey`) the relay must use to encrypt its
// answer, so neither direction is readable in the clear on the wire.
const publicKeyCache = new Map(); // url -> key, since Max and Leumi are different relay endpoints
async function relayPublicKey(url) {
  if (publicKeyCache.has(url)) return publicKeyCache.get(url);
  const res = await fetch(url, { cache: "no-store", credentials: "omit" });
  if (!res.ok) throw new Error("no key");
  const key = (await res.json()).publicKey;
  publicKeyCache.set(url, key);
  return key;
}

/** Encrypts `fields` for the relay at `url`: returns the POST body and the key to decrypt the answer with. */
async function sealEnvelope(url, fields) {
  const rsa = await crypto.subtle.importKey("jwk", await relayPublicKey(url), { name: "RSA-OAEP", hash: "SHA-256" }, false, ["encrypt"]);
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
export async function callRelay(url, fields) {
  const { body, responseKey } = await sealEnvelope(url, fields);
  const res = await fetch(url, {
    method: "POST", headers: { "Content-Type": "application/json" }, body,
    cache: "no-store", credentials: "omit", referrerPolicy: "no-referrer",
  });
  return res.status === 200 ? { ok: true, body: await openAnswer(res, responseKey) } : { ok: false, status: res.status, error: (await res.json().catch(() => ({}))).error };
}

// The session tokens (never the password, never account data) are kept in
// this browser's own localStorage, so reopening the page — or going from one
// of the sign-in pages back to the dashboard — doesn't ask for the password
// again right away. Only this device holds them, and each one is useless on
// its own after its 20-minute expiry (the relay checks that; a copy sitting
// in storage past then is inert). "Forget" erases them at once.
const STORAGE_KEY = "tb-session";
export function loadSaved() {
  try { return JSON.parse(localStorage.getItem(STORAGE_KEY)) ?? {}; } catch { return {}; }
}
export function saveSaved(patch) {
  try {
    const next = { ...loadSaved(), ...patch };
    if (!next.max && !next.leumi) localStorage.removeItem(STORAGE_KEY);
    else localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  } catch { /* private browsing or storage blocked: just skip saving */ }
}
export function clearSaved() {
  try { localStorage.removeItem(STORAGE_KEY); } catch {}
}
