import {initializeApp} from "https://www.gstatic.com/firebasejs/11.1.0/firebase-app.js";
import {
  getAuth,
  GoogleAuthProvider,
  onAuthStateChanged,
  signInWithEmailAndPassword,
  signInWithPopup,
  signOut,
} from "https://www.gstatic.com/firebasejs/11.1.0/firebase-auth.js";

const firebase = initializeApp({
  apiKey: "AIzaSyCC3QjxVO3U8fNZawlnFj4V0GlNibRGf3o",
  authDomain: "sabibom-app.firebaseapp.com",
  projectId: "sabibom-app",
  appId: "1:939523940329:web:ade397a5e19770f1f03578",
});
const auth = getAuth(firebase);
const $ = (id) => document.getElementById(id);
const state = {examples: [], unanswered: [], filter: "all", businessId: ""};
const intents = [
  ["draft_customer", "Add customer"],
  ["draft_supplier", "Add supplier"],
  ["draft_product", "Add product"],
  ["draft_expense", "Add expense"],
  ["draft_sale", "Create sale"],
  ["draft_purchase", "Create purchase"],
  ["sales_report", "Sales report"],
  ["profit_report", "Profit report"],
  ["end_of_day_report", "End-of-day report"],
  ["list_customers", "List customers"],
  ["list_suppliers", "List suppliers"],
  ["list_products", "List products"],
  ["check_low_stock", "Check low stock"],
  ["answer_general", "General guidance"],
];

function icons() { window.lucide?.createIcons(); }
function toast(message) {
  $("toast").textContent = message;
  $("toast").classList.add("show");
  setTimeout(() => $("toast").classList.remove("show"), 2600);
}
function escapeHtml(value = "") {
  return String(value).replace(/[&<>"']/g, (char) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
  })[char]);
}
async function api(path, options = {}) {
  const token = await auth.currentUser?.getIdToken(true);
  if (!token) throw new Error("Sign in again.");
  const response = await fetch(path, {
    ...options,
    headers: {"Content-Type": "application/json", Authorization: `Bearer ${token}`, ...(options.headers || {})},
  });
  const json = await response.json().catch(() => ({}));
  if (!response.ok || json.success === false) throw new Error(json?.error?.message || "Request failed.");
  return json.data;
}
function setView(name) {
  document.querySelectorAll(".nav-item").forEach((button) => button.classList.toggle("active", button.dataset.view === name));
  document.querySelectorAll(".view").forEach((view) => view.classList.add("hidden"));
  $(`${name}View`).classList.remove("hidden");
  $("viewTitle").textContent = {inbox: "Training inbox", examples: "Training examples", test: "Test Sabi understanding"}[name];
}
function render() {
  $("inboxBadge").textContent = state.unanswered.filter((item) => item.status !== "trained").length;
  $("unreviewedCount").textContent = state.unanswered.filter((item) => item.status !== "trained").length;
  $("publishedCount").textContent = state.examples.filter((item) => item.status === "published").length;
  $("draftCount").textContent = state.examples.filter((item) => item.status === "draft").length;
  const inbox = state.unanswered.filter((item) => item.status !== "trained");
  $("inboxList").innerHTML = inbox.length ? inbox.map((item) => `
    <article class="list-item">
      <div><h4>${escapeHtml(item.question)}</h4><div class="meta"><span>Asked ${item.count} time${item.count === 1 ? "" : "s"}</span><span>${item.lastAskedAt ? new Date(item.lastAskedAt).toLocaleString() : "Recently"}</span></div></div>
      <div class="item-actions"><button class="primary train-button" data-id="${item.id}"><i data-lucide="graduation-cap"></i> Train Sabi</button></div>
    </article>`).join("") : '<div class="empty-list">No unanswered requests need review.</div>';
  const examples = state.filter === "all" ? state.examples : state.examples.filter((item) => item.status === state.filter);
  $("examplesList").innerHTML = examples.length ? examples.map((item) => `
    <article class="list-item">
      <div><h4>${escapeHtml(item.utterance)}</h4><div class="meta"><span class="status ${item.status}">${item.status}</span><span>${escapeHtml(intents.find(([key]) => key === item.intent)?.[1] || item.intent)}</span><span>Try: ${escapeHtml(item.suggestedPrompt)}</span></div></div>
      <div class="item-actions">
        <button class="secondary edit-button" data-id="${item.id}" title="Edit"><i data-lucide="pencil"></i></button>
        ${item.status !== "published" ? `<button class="primary status-button" data-id="${item.id}" data-status="published">Publish</button>` : `<button class="secondary status-button" data-id="${item.id}" data-status="archived">Archive</button>`}
      </div>
    </article>`).join("") : '<div class="empty-list">No examples in this view.</div>';
  icons();
}
async function loadBusiness() {
  const businessId = $("businessId").value.trim();
  if (!businessId) return toast("Enter a business ID.");
  const data = await api(`/api/sabi-training/overview?businessId=${encodeURIComponent(businessId)}`);
  state.businessId = businessId;
  state.examples = data.examples || [];
  state.unanswered = data.unanswered || [];
  localStorage.setItem("sabiTrainingBusinessId", businessId);
  $("emptyBusiness").classList.add("hidden");
  $("inboxView").classList.remove("hidden");
  setView("inbox");
  render();
}
async function loadOwnedBusinesses() {
  const businesses = await api("/api/sabi-training/businesses");
  const remembered = localStorage.getItem("sabiTrainingBusinessId") || "";
  $("businessId").innerHTML =
    '<option value="">Select a business</option>' +
    businesses.map((business) =>
      `<option value="${escapeHtml(business.id)}">${escapeHtml(business.name)}</option>`,
    ).join("");
  if (businesses.some((business) => business.id === remembered)) {
    $("businessId").value = remembered;
  }
}
function openEditor(example = {}) {
  $("editorTitle").textContent = example.id ? "Edit example" : "New example";
  $("exampleId").value = example.id || "";
  $("sourceUnansweredId").value = example.sourceUnansweredId || "";
  $("utterance").value = example.utterance || "";
  $("intent").value = example.intent || "draft_customer";
  $("clarification").value = example.clarification || "";
  $("suggestedPrompt").value = example.suggestedPrompt || "";
  $("notes").value = example.notes || "";
  $("editor").showModal();
  icons();
}
async function saveExample(status) {
  const payload = {
    businessId: state.businessId,
    id: $("exampleId").value || undefined,
    sourceUnansweredId: $("sourceUnansweredId").value || null,
    utterance: $("utterance").value.trim(),
    intent: $("intent").value,
    clarification: $("clarification").value.trim() || null,
    suggestedPrompt: $("suggestedPrompt").value.trim(),
    notes: $("notes").value.trim() || null,
    status,
  };
  if (!payload.utterance || !payload.suggestedPrompt) return toast("User wording and corrected prompt are required.");
  await api("/api/sabi-training/save", {method: "POST", body: JSON.stringify(payload)});
  $("editor").close();
  await loadBusiness();
  setView("examples");
  toast(status === "published" ? "Example published." : "Draft saved.");
}

$("intent").innerHTML = intents.map(([value, label]) => `<option value="${value}">${label}</option>`).join("");
$("loginForm").addEventListener("submit", async (event) => {
  event.preventDefault();
  $("authError").textContent = "";
  try { await signInWithEmailAndPassword(auth, $("email").value, $("password").value); }
  catch (error) { $("authError").textContent = error.message || "Could not sign in."; }
});
$("googleLogin").addEventListener("click", async () => {
  try { await signInWithPopup(auth, new GoogleAuthProvider()); }
  catch (error) { $("authError").textContent = error.message || "Could not sign in."; }
});
$("logout").addEventListener("click", () => signOut(auth));
$("loadBusiness").addEventListener("click", () => loadBusiness().catch((error) => toast(error.message)));
document.querySelectorAll(".nav-item").forEach((button) => button.addEventListener("click", () => {
  if (!state.businessId) return toast("Load a business first.");
  setView(button.dataset.view);
}));
$("newExample").addEventListener("click", () => openEditor());
$("closeEditor").addEventListener("click", () => $("editor").close());
$("saveDraft").addEventListener("click", () => saveExample("draft").catch((error) => toast(error.message)));
$("publish").addEventListener("click", () => saveExample("published").catch((error) => toast(error.message)));
document.addEventListener("click", async (event) => {
  const train = event.target.closest(".train-button");
  if (train) {
    const item = state.unanswered.find((entry) => entry.id === train.dataset.id);
    openEditor({utterance: item.question, sourceUnansweredId: item.id});
  }
  const edit = event.target.closest(".edit-button");
  if (edit) openEditor(state.examples.find((entry) => entry.id === edit.dataset.id));
  const status = event.target.closest(".status-button");
  if (status) {
    try {
      await api("/api/sabi-training/status", {method: "POST", body: JSON.stringify({businessId: state.businessId, id: status.dataset.id, status: status.dataset.status})});
      await loadBusiness();
      setView("examples");
      toast("Status updated.");
    } catch (error) { toast(error.message); }
  }
  const filter = event.target.closest(".filter");
  if (filter) {
    document.querySelectorAll(".filter").forEach((item) => item.classList.remove("active"));
    filter.classList.add("active");
    state.filter = filter.dataset.status;
    render();
  }
});
$("runTest").addEventListener("click", async () => {
  const message = $("testMessage").value.trim();
  if (!message) return toast("Enter wording to test.");
  try {
    const result = await api("/api/sabi-training/preview", {method: "POST", body: JSON.stringify({businessId: state.businessId, message})});
    $("testResult").classList.add("has-result");
    $("testResult").innerHTML = `<p class="eyebrow">Resolved intent</p><h3>${escapeHtml(result.resolvedIntent || "No confident match")}</h3>
      <div class="result-row"><strong>Built-in match</strong><p>${escapeHtml(result.builtInIntent || "None")}</p></div>
      <div class="result-row"><strong>Published matches</strong><p>${result.matchedExamples.length ? result.matchedExamples.map((item) => escapeHtml(item.utterance)).join("<br>") : "None"}</p></div>`;
  } catch (error) { toast(error.message); }
});
onAuthStateChanged(auth, (user) => {
  $("authView").classList.toggle("hidden", Boolean(user));
  $("appView").classList.toggle("hidden", !user);
  if (user) {
    $("userEmail").textContent = user.email || user.uid;
    loadOwnedBusinesses().catch((error) => toast(error.message));
  } else {
    state.businessId = "";
  }
  setTimeout(icons, 0);
});
window.addEventListener("DOMContentLoaded", icons);
