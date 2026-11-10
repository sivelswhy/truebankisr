// index.html: the dashboard, and the "choose a bank" landing when nothing is
// connected yet. Signing in itself happens on separate pages (max.html,
// leumi.html — each its own form, its own relay call); this page only
// restores saved sessions and renders what they bring back.
import { demoAnswer, demoLeumi } from "./demo.js";
import { parseAll, upcoming, purchases, spendingByCategory, monthlyTotals, recurring, parseLeumi, trueBalance, israelDay, daysUntil, CATEGORY_COLORS } from "./lib.js";
import {
  T, lang, $, el, svg, icon, tile, iconButton, setIconButton,
  RELAY, callRelay, loadSaved, saveSaved, clearSaved,
} from "./shared.js";

$("lead").textContent = T.chooseLead;
$("link-max").textContent = T.connectMax;
$("link-leumi").textContent = T.connectLeumi;
$("link-max").addEventListener("click", () => { location.href = "max.html"; });
$("link-leumi").addEventListener("click", () => { location.href = "leumi.html"; });
$("demo").textContent = T.demo;

let state = null; // txns/balances: in memory only, never saved
const newState = () => ({ txns: [], max: false, leumi: null, leumiSession: null, hidden: false, demo: false });

const money = new Intl.NumberFormat(lang, { style: "currency", currency: "ILS" });
const shortDay = (day) => new Date(`${day}T12:00:00`).toLocaleDateString(lang, { day: "numeric", month: "short" });
const longDay = (day) => new Date(`${day}T12:00:00`).toLocaleDateString(lang, { weekday: "long", day: "numeric", month: "long" });

$("demo").addEventListener("click", () => {
  state = Object.assign(newState(), { txns: parseAll(demoAnswer()), max: true, leumi: demoLeumi(), demo: true });
  render();
});
if (new URLSearchParams(location.search).has("demo")) $("demo").click();

const PAGE = 50;
const currency = (code) => new Intl.NumberFormat(lang, { style: "currency", currency: code });
const monthName = (m) => new Date(`${m}-15T12:00:00`).toLocaleDateString(lang, { month: "long", year: "numeric" });
const monthShort = (m) => new Date(`${m}-15T12:00:00`).toLocaleDateString(lang, { month: "short" });

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

function showChoose() {
  $("dash").hidden = true;
  $("dash").replaceChildren();
  $("choose").hidden = false;
  $("title").textContent = "True Balance";
  $("title").hidden = false;
  $("lead").textContent = T.chooseLead;
  $("lead").hidden = false;
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
    clearSaved();
    document.body.classList.remove("hide");
    showChoose();
  });
  const connect = iconButton("Plug", T.connect);
  connect.addEventListener("click", () => { location.href = state.max ? "leumi.html" : "max.html"; });
  const refreshMax = state.maxSession ? iconButton("Repeat", T.refresh) : null;
  refreshMax?.addEventListener("click", async () => {
    refreshMax.disabled = true;
    try {
      const r = await callRelay(`${RELAY}/api/max`, { mode: "refresh", token: state.maxSession });
      if (!r.ok) {
        if (r.error === "session") { state.maxSession = null; saveSaved({ max: null }); state.max = false; render(); return; }
        return;
      }
      state.txns = parseAll(r.body);
      state.maxSession = r.body.session;
      saveSaved({ max: state.maxSession });
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
        if (r.error === "session") { state.leumiSession = null; saveSaved({ leumi: null }); state.leumi = null; render(); return; }
        return;
      }
      state.leumi = parseLeumi(String(r.body.body), String(r.body.number ?? ""));
      state.leumiSession = r.body.session;
      saveSaved({ leumi: state.leumiSession });
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
  $("choose").hidden = true;
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

// A Leumi bookmark hand-off (leumi-login.js): one-shot, consumed immediately.
(() => {
  let handoff = null;
  try {
    const raw = sessionStorage.getItem("tb-leumi-handoff");
    if (raw) { handoff = JSON.parse(raw); sessionStorage.removeItem("tb-leumi-handoff"); }
  } catch {}
  if (!handoff) return;
  try {
    state ??= newState();
    state.leumi = parseLeumi(String(handoff.body), String(handoff.number ?? ""));
    render();
  } catch { /* malformed: just ignore it */ }
})();

// A saved token from an earlier visit (max-login.js / leumi-login.js, or a
// previous visit here): try it silently instead of asking for the password
// again. Each bank restores independently and renders as soon as it answers,
// so one slow bank (Leumi) never holds up the other (Max).
(() => {
  const saved = loadSaved();
  if (!saved.max && !saved.leumi) return;

  const settle = () => { if (state && (state.max || state.leumi)) render(); };

  if (saved.max) {
    $("link-max").disabled = true;
    $("max-busy").textContent = T.busy;
    $("max-busy").hidden = false;
    callRelay(`${RELAY}/api/max`, { mode: "refresh", token: saved.max }).then((r) => {
      if (r.ok) {
        state = Object.assign(state ?? newState(), { txns: parseAll(r.body), max: true, maxSession: r.body.session });
        saveSaved({ max: state.maxSession });
      } else {
        saveSaved({ max: null });
      }
    }).catch(() => {}).finally(() => {
      $("link-max").disabled = false;
      $("max-busy").hidden = true;
      settle();
    });
  }

  if (saved.leumi) {
    $("link-leumi").disabled = true;
    $("leumi-busy").textContent = T.leumiBusy;
    $("leumi-busy").hidden = false;
    callRelay(`${RELAY}/api/leumi`, { mode: "refresh", token: saved.leumi }).then((r) => {
      if (r.ok) {
        state ??= newState();
        state.leumi = parseLeumi(String(r.body.body), String(r.body.number ?? ""));
        state.leumiSession = r.body.session;
        saveSaved({ leumi: state.leumiSession });
      } else {
        saveSaved({ leumi: null });
      }
    }).catch(() => {}).finally(() => {
      $("link-leumi").disabled = false;
      $("leumi-busy").hidden = true;
      settle();
    });
  }
})();
