// leumi.html: connect Leumi, nothing else. Same hand-off to index.html as
// max-login.js. The bookmarklet stays as a fallback for anyone who'd rather
// no server ever see their Leumi password.
import { LEUMI_ORIGIN, LEUMI_URL, OPENER_NAME, bookmarkletHref } from "./leumi.js";
import { parseLeumi } from "./lib.js";
import { T, $, icon, el, iconButton, callRelay, RELAY, saveSaved } from "./shared.js";

$("back-link").textContent = T.backHome;
$("lead").textContent = T.leumiLead;
$("l-user").textContent = T.leumiUser;
$("l-pass").textContent = T.leumiPass;
$("lgo").textContent = T.leumiGo;
$("privacy").replaceChildren(icon("Lock", { size: 16 }), el("span", { text: T.leumiPrivacy }));

function showError(message) {
  const e = $("lerr");
  e.textContent = message;
  e.hidden = !message;
}

// ---- Fallback: a bookmark run on Leumi's own page, no server involved ----

const link = el("a", { class: "bm", href: bookmarkletHref(location.origin), title: T.dragOnly, draggable: "true" }, icon("Bank", { size: 18 }), el("span", { text: T.bookmarkName }));
link.addEventListener("click", (e) => { e.preventDefault(); alert(T.dragOnly); });
const openBtn = iconButton("Bank", T.openLeumi);
openBtn.addEventListener("click", () => window.open(LEUMI_URL, OPENER_NAME));
$("advanced-box").replaceChildren(el("details", {},
  el("summary", { text: T.advancedLeumi }),
  el("p", { class: "step", text: T.step1 }), el("p", {}, link),
  el("p", { class: "step", text: T.step2 }), el("p", {}, openBtn),
  el("p", { class: "step", text: T.step3 })));

// The bookmark reads Leumi directly, with no relay and no session token to
// save (there's nothing to refresh later: the data it hands over is the one
// answer). It's passed to index.html through a one-shot sessionStorage key,
// consumed and removed there on load, not through the reusable saved-token
// store.
window.addEventListener("message", (e) => {
  if (!LEUMI_ORIGIN.test(e.origin) || !e.data || e.data.type !== "tb-leumi") return;
  try {
    const body = String(e.data.body), number = String(e.data.number ?? "");
    parseLeumi(body, number); // validated before handing off
    e.source?.postMessage({ type: "tb-ack" }, e.origin);
    try { sessionStorage.setItem("tb-leumi-handoff", JSON.stringify({ body, number })); } catch {}
    location.href = "index.html";
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

// ---- The relay form ----

$("leumi-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const username = $("lu").value.trim();
  const password = $("lp").value;
  $("lp").value = "";
  showError("");
  $("lgo").disabled = true;
  $("lgo").textContent = T.leumiBusy;
  try {
    const r = await callRelay(`${RELAY}/api/leumi`, { mode: "login", username, password });
    if (!r.ok) {
      showError({ refused: T.leumiRefused, blocked: T.leumiBlocked, changePassword: T.leumiChangePassword, timeout: T.leumiTimeout, firewall: T.leumiFirewall, "rate limited": T.rate }[r.error] ?? T.leumiDown);
      return;
    }
    saveSaved({ leumi: r.body.session });
    location.href = "index.html";
  } catch {
    showError(navigator.onLine ? T.leumiDown : T.offline);
  } finally {
    $("lgo").disabled = false;
    $("lgo").textContent = T.leumiGo;
  }
});
