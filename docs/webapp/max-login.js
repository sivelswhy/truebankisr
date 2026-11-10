// max.html: connect Max, nothing else. On success, the session token is
// saved (shared.js) and the page hands off to index.html, which picks up
// the saved token on load and fetches the data from there.
import { T, $, icon, el, callRelay, RELAY, saveSaved } from "./shared.js";

$("back-link").textContent = T.backHome;
$("lead").textContent = T.lead;
$("l-user").textContent = T.user;
$("l-pass").textContent = T.pass;
$("go").textContent = T.go;
$("privacy").replaceChildren(icon("Lock", { size: 16 }), el("span", { text: T.privacy }));
$("test-hint").textContent = T.testHint;
$("demo").textContent = T.demo;

function showError(message) {
  const e = $("err");
  e.textContent = message;
  e.hidden = !message;
}

$("demo").addEventListener("click", () => {
  location.href = `index.html?demo`;
});

$("form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const username = $("u").value.trim();
  const password = $("p").value;
  $("p").value = "";
  showError("");
  // The test account never leaves the browser: sample data, no relay, no Max.
  if (username === "test" && password === "test") {
    $("demo").click();
    return;
  }
  $("go").disabled = true;
  $("go").textContent = T.busy;
  try {
    const r = await callRelay(`${RELAY}/api/max`, { mode: "login", username, password });
    if (!r.ok) return showError(r.status === 401 ? T.refused : r.status === 429 ? T.rate : T.down);
    saveSaved({ max: r.body.session });
    location.href = "index.html";
  } catch {
    showError(navigator.onLine ? T.down : T.offline);
  } finally {
    $("go").disabled = false;
    $("go").textContent = T.go;
  }
});
