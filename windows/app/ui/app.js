import { ICONS } from "./icons.js";
import { PERSONAS } from "./personas.js";

// Inside the app, Tauri provides the bridge. In a plain browser (design preview) a pretend backend stands in.
if (!window.__TAURI__) await import("./mock.js");
const invoke = (cmd, args) => window.__TAURI__.core.invoke(cmd, args);
const listen = (name, fn) => window.__TAURI__.event.listen(name, fn);

// ---------- helpers ----------
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const icon = (name, size = 20) => `<svg class="i" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name] || ""}</svg>`;
const MARK = `<svg viewBox="0 0 48 48" aria-hidden="true"><path fill="currentColor" d="M12 42V10a6 6 0 0 1 6-6h12a6 6 0 0 1 6 6v32h-4V10a2 2 0 0 0-2-2H18a2 2 0 0 0-2 2v32z"/><rect fill="currentColor" x="6" y="40" width="36" height="4" rx="2"/><circle cx="28" cy="25" r="3.2" fill="#F2542D"/></svg>`;
const WAVE = (cls) => `<svg class="wave ${cls}" viewBox="0 0 1200 16" preserveAspectRatio="none" aria-hidden="true"><path d="M0 8 Q75 0 150 8 T300 8 T450 8 T600 8 T750 8 T900 8 T1050 8 T1200 8 V16 H0Z" fill="currentColor"/></svg>`;
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const store = { get: (k, d) => { try { return JSON.parse(localStorage.getItem(k)) ?? d; } catch { return d; } }, set: (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* private mode */ } } };

function fmt(bytes) {
  if (bytes < 1000) return `${Math.round(bytes)} bytes`;
  const units = ["KB", "MB", "GB", "TB"]; let v = bytes, u = -1;
  do { v /= 1000; u++; } while (v >= 1000 && u < units.length - 1);
  return `${v >= 100 ? v.toFixed(0) : v.toFixed(1)} ${units[u]}`;
}
const ago = (days) => days < 1 ? "today" : days === 1 ? "yesterday" : days < 14 ? `${days} days ago` : days < 60 ? `${Math.floor(days / 7)} weeks ago` : days < 365 ? `${Math.floor(days / 30)} months ago` : `${Math.floor(days / 365)} year${days >= 730 ? "s" : ""} ago`;
const left = (expires) => { const s = expires - Date.now() / 1000; if (s <= 0) return "expires now"; const d = Math.floor(s / 86400); return d >= 1 ? `${d} day${d === 1 ? "" : "s"} left` : `${Math.max(1, Math.floor(s / 3600))} hours left`; };
const TIER = { safe: "Safe", rebuildable: "Rebuildable", yours: "Yours" };
const badge = (tier) => `<span class="badge"><i class="dot ${tier}"></i>${TIER[tier]}</span>`;
const sum = (list, f = (x) => x.bytes) => list.reduce((s, x) => s + f(x), 0);
const regenText = { instant: "Rebuilds instantly", minutes: "Minutes to rebuild", hours: "Hours to rebuild", never: "Cannot be rebuilt" };
const plainWords = (c) => c.tier === "safe" ? "Nothing you would notice. The app rebuilds this by itself when it needs it."
  : c.tier === "rebuildable" ? "Your own files are not touched. It gets rebuilt the next time you need it, which can take a while."
  : "This could be your own work. Room keeps it in the undo vault for 7 days, then it is gone for good.";

// A segmented control whose thumb slides between options.
const seg = (id, label, options, active, act, dataKey = "v") =>
  `<div class="seg" id="${id}" role="group" aria-label="${label}"><i class="thumb"></i>${options.map(([v, text]) => `<button data-act="${act}" data-${dataKey}="${v}" aria-pressed="${v == active}">${text}</button>`).join("")}</div>`;
function placeThumb(segEl, animate = true) {
  const t = $(".thumb", segEl), b = $('[aria-pressed="true"]', segEl);
  if (!t || !b) return;
  if (!animate) t.style.transition = "none";
  t.style.setProperty("--x", `${b.offsetLeft - 3}px`); t.style.setProperty("--w", `${b.offsetWidth}px`);
  if (!animate) { void t.offsetWidth; t.style.transition = ""; }
}
const placeThumbs = (root = document, animate = false) => $$(".seg", root).forEach((s) => placeThumb(s, animate));
function press(segEl, btn) { $$("button", segEl).forEach((b) => b.setAttribute("aria-pressed", b === btn)); placeThumb(segEl, true); }

// Numbers that count up to their value.
const shown = new Map();
function countUps(root = document) {
  $$("[data-to]", root).forEach((el) => {
    const to = +el.dataset.to, key = el.dataset.key || el.id, from = shown.get(key) ?? 0;
    shown.set(key, to);
    if (reduceMotion || from === to) { el.textContent = fmt(to); return; }
    const t0 = performance.now(), dur = 1100;
    const step = (now) => {
      const p = Math.min(1, (now - t0) / dur), e = p === 1 ? 1 : 1 - Math.pow(2, -10 * p);
      el.textContent = fmt(from + (to - from) * e);
      if (p < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  });
}
const stagger = (root) => { [...root.children].forEach((el, i) => el.style.setProperty("--i", i)); $$(".list > .item", root).forEach((el, i) => el.style.setProperty("--i", i)); };

// ---------- state ----------
const S = {
  view: "overview", overview: null, candidates: [], scanning: false, scanLabel: "", scannedOnce: false,
  selection: new Set(), filter: "all", detail: null, goalGB: 24, plan: null, vault: [],
  collapsed: store.get("navCollapsed", false), onboard: null,
  map: { drives: [], places: [], stack: [], tree: null, loading: false, mode: store.get("mapMode", "treemap"), sort: { k: "bytes", d: -1 }, cache: new Map(), timer: null, elapsed: 0, stopped: false },
};
const settings = () => S.overview?.settings;

function toast(title, detail = "", bad = false) {
  const el = document.createElement("div");
  el.className = `toast${bad ? " bad" : ""}`;
  el.innerHTML = `<b>${esc(title)}</b>${detail ? `<span class="muted">${esc(detail)}</span>` : ""}`;
  $("#toasts").append(el);
  setTimeout(() => { el.style.transition = "opacity .25s, transform .25s"; el.style.opacity = 0; el.style.transform = "translateX(12px)"; setTimeout(() => el.remove(), 260); }, 4800);
}

function applyTheme() {
  const root = document.documentElement, o = S.overview;
  if (!o) return;
  const a = o.settings.appearance;
  if (a === "light" || a === "dark") root.dataset.theme = a; else delete root.dataset.theme;
  root.dataset.effect = o.effect;
}

// ---------- navigation pane ----------
const NAV = [["overview", "Overview", "layout-dashboard"], ["review", "Review", "list-checks"], ["map", "Map", "folder-tree"], ["vault", "Vault", "archive"]];
function buildShell() {
  $(".shell").classList.toggle("collapsed", S.collapsed);
  const item = ([id, label, ic]) => `<button data-act="go" data-view="${id}" title="${label}" data-nav="${id}">${icon(ic)}<span class="lbl">${label}</span><em class="count" style="font-style:normal"></em></button>`;
  $("#nav").innerHTML = `<div class="nav-top"><button class="toggle" data-act="toggle-nav" title="${S.collapsed ? "Expand" : "Collapse"} navigation" aria-label="Toggle navigation" aria-expanded="${!S.collapsed}">${icon("panel-left")}</button><div class="brand">${MARK}<span>Room</span></div></div>${NAV.map(item).join("")}<div class="spacer"></div>${item(["settings", "Settings", "settings"])}<div class="foot">Version ${esc(S.overview?.version || "")}</div>`;
  updateNav();
}
function updateNav() {
  const counts = { review: S.candidates.filter((c) => !c.heldBack).length || "", vault: S.vault.length || S.overview?.vaultBatches || "" };
  $$("[data-nav]").forEach((b) => {
    const id = b.dataset.nav;
    if (S.view === id) b.setAttribute("aria-current", "page"); else b.removeAttribute("aria-current");
    const c = $(".count", b); if (c) c.textContent = counts[id] ?? "";
  });
}
function toggleNav() {
  S.collapsed = !S.collapsed; store.set("navCollapsed", S.collapsed);
  $(".shell").classList.toggle("collapsed", S.collapsed);
  const b = $(".toggle"); b.setAttribute("aria-expanded", !S.collapsed); b.title = `${S.collapsed ? "Expand" : "Collapse"} navigation`;
  setTimeout(() => { placeThumbs(); if (S.view === "map") layoutMap(); }, 360);
}

async function go(view) {
  S.view = view; closeDetail(true);
  if (view === "vault") S.vault = await invoke("vault_list");
  if (view === "map" && !S.map.drives.length) await mapInit();
  let done = false;
  const swap = () => { if (done) return; done = true; render(true); $("#view").scrollTo(0, 0); };
  // A soft cross-fade where the browser supports it. Navigation never depends on it: the swap runs regardless.
  if (document.startViewTransition && !reduceMotion && document.visibilityState === "visible") { document.startViewTransition(swap); setTimeout(swap, 350); } else swap();
}

function render(enter = false) {
  updateNav();
  const v = { overview: viewOverview, review: viewReview, map: viewMap, vault: viewVault, settings: viewSettings }[S.view];
  $("#view").innerHTML = `<div class="page${enter ? " enter" : ""}">${v()}</div>`;
  const page = $(".page");
  if (enter) { stagger(page); $$(".list", page).forEach((l) => l.classList.add("enter")); }
  placeThumbs(page); countUps(page);
  if (S.view === "overview") requestAnimationFrame(() => { const t = $(".tank"); if (t) t.style.setProperty("--fill", t.dataset.fill + "%"); });
  if (S.view === "map") requestAnimationFrame(layoutMap);
}

// ---------- overview ----------
function viewOverview() {
  const o = S.overview, used = o.total ? Math.round(((o.total - o.free) / o.total) * 100) : 0;
  const mood = used >= 90 ? "It is getting tight. Let's make some room." : used >= 75 ? "You have room to work. Keep an eye on what grows." : "Plenty of room. Nothing needs doing right now.";
  const by = (t) => S.candidates.filter((c) => c.tier === t && !c.heldBack);
  const tile = (t, label, hint) => `<button class="card tile" data-act="filter" data-v="${t}"><span class="badge"><i class="dot ${t}"></i>${label}</span><div class="v" data-to="${sum(by(t))}" data-key="tile-${t}">${fmt(sum(by(t)))}</div><div class="muted">${hint}</div></button>`;
  return `
    <div><p class="eyebrow">Storage</p><h1>Your PC has <span class="num" data-to="${o.free}" data-key="free-h1">${fmt(o.free)}</span> left.</h1><p class="lede">${mood}</p></div>
    <div class="grid g2">
      <div class="card tank stack" data-fill="${used}">
        <div class="water">${WAVE("a")}${WAVE("b")}</div>
        <div class="row between"><h3>Free space on ${esc(o.drive)}</h3><span class="muted mono">${used}% used</span></div>
        <div class="big-num" data-to="${o.free}" data-key="free-big">${fmt(o.free)}</div><div class="muted mono">of ${fmt(o.total)}</div>
      </div>
      <div class="card stack">
        <h2>How much room do you need?</h2>
        <p class="muted" style="margin:0">A Windows feature update needs about 24 GB free. Pick a target and Room plans the safest way to reach it.</p>
        ${seg("goalseg", "Target free space", [10, 24, 50, 100].map((g) => [g, `${g} GB`]), S.goalGB, "goal", "gb")}
        <div class="row"><button class="btn accent" id="plan-btn" data-act="plan" ${S.scanning ? "disabled" : ""}>Plan ${S.goalGB} GB</button></div>
        <div id="plan">${planHtml()}</div>
      </div>
    </div>
    <div class="row between" style="margin-top:8px"><h2 style="margin:0">${S.scanning ? "Looking for space" : "What Room found"}</h2>
      <button class="btn subtle" data-act="rescan" ${S.scanning ? "disabled" : ""}>${icon("refresh-cw", 16)}Scan again</button></div>
    ${S.scanning ? `<div class="card row"><span class="spinner"></span><span class="muted" id="scan-now">Measuring ${esc(S.scanLabel || "caches, projects and downloads")}</span></div>` : `
    <div class="grid g3">${tile("safe", "Safe", "Caches that rebuild by themselves")}${tile("rebuildable", "Rebuildable", "Takes time or bandwidth to get back")}${tile("yours", "Yours", "Could be your work. Always your call")}</div>
    <div class="card row between">
      <div class="row">${icon("archive")}<div><h3 style="margin:0">Undo vault</h3><span class="muted">${S.overview.vaultBatches ? `${fmt(S.overview.vaultBytes)} waiting, restorable for 7 days` : "Empty. Your own files wait here for 7 days after you delete them."}</span></div></div>
      <button class="btn" data-act="go" data-view="vault">Open vault</button></div>`}`;
}
function planHtml() {
  const p = S.plan;
  if (!p) return "";
  return `<div class="notice">${icon("sparkles", 18)}<div>${p.itemIds.length} item${p.itemIds.length === 1 ? "" : "s"}, about <b>${fmt(p.guaranteedBytes)}</b>.
    ${p.reachesGoal ? "That reaches your goal using only safe and rebuildable items." : `That is ${fmt(p.shortfall)} short. The rest would have to come from files only you can judge.`}
    <div style="margin-top:10px"><button class="btn" data-act="review-plan">Review the plan</button></div></div></div>`;
}

// ---------- review ----------
const visible = () => S.candidates.filter((c) => S.filter === "all" || c.tier === S.filter);
const picked = () => S.candidates.filter((c) => S.selection.has(c.id));
function reviewList() {
  const list = visible();
  const row = (c) => `<div class="item ${c.heldBack ? "held" : ""}" tabindex="0" data-act="detail" data-id="${esc(c.id)}">
      <input type="checkbox" data-act="toggle" data-id="${esc(c.id)}" ${S.selection.has(c.id) ? "checked" : ""} ${c.heldBack ? "disabled" : ""} aria-label="Select ${esc(c.title)}">
      <div style="min-width:0"><div class="title">${esc(c.title)}</div><div class="sub">${esc(c.heldBack || c.why)}</div></div>
      ${badge(c.tier)}<div class="size">${fmt(c.bytes)}</div></div>`;
  if (S.scanning) return `<div class="card row"><span class="spinner"></span><span class="muted">Still scanning. More may appear.</span></div>`;
  return list.length ? `<div class="card tight list">${list.map(row).join("")}</div>` : `<div class="card empty">${icon("check", 32)}<div><b>Nothing here.</b></div><div>Room didn't find anything in this group.</div></div>`;
}
function viewReview() {
  return `
    <div><p class="eyebrow">Review</p><h1>Nothing happens until you say so.</h1>
    <p class="lede">Each suggestion says what it is, what you get, and how hard it is to get back. Nothing in <b>Yours</b> is ticked for you.</p></div>
    <div class="row between">${seg("filterseg", "Filter", [["all", "All"], ["safe", "Safe"], ["rebuildable", "Rebuildable"], ["yours", "Yours"]], S.filter, "filter")}<span class="muted mono" id="count">${visible().length} item${visible().length === 1 ? "" : "s"}</span></div>
    <div id="reviewlist">${reviewList()}</div>
    <div class="actionbar"><div><div class="muted">Selected</div><div class="total" id="total">${fmt(sum(picked()))}</div></div>
      <button class="btn accent big" id="free-btn" data-act="confirm" ${S.selection.size ? "" : "disabled"}>Free up ${fmt(sum(picked()))}${icon("arrow-right", 18)}</button></div>`;
}
function updateTotal() {
  const t = sum(picked());
  const a = $("#total"); if (a) a.textContent = fmt(t);
  const b = $("#free-btn"); if (b) { b.disabled = !S.selection.size; b.innerHTML = `Free up ${fmt(t)}${icon("arrow-right", 18)}`; }
}

// ---------- details panel ----------
function openDetail(id) {
  const c = S.candidates.find((x) => x.id === id);
  if (!c) return;
  const swap = !!S.detail;
  S.detail = id;
  const where = c.targets.length > 1 ? `${c.targets.length} items in ${c.displayPath}` : c.displayPath;
  const html = `<aside class="pop" role="dialog" aria-label="Details">
    <div class="row between">${badge(c.tier)}<button class="btn subtle icon" data-act="close-detail" aria-label="Close">${icon("x", 18)}</button></div>
    <h2>${esc(c.title)}</h2><p class="muted" style="margin:10px 0 0">${esc(c.why)}</p>
    ${c.note ? `<div class="notice" style="margin-top:14px">${icon("triangle-alert", 18)}<div>${esc(c.note)}</div></div>` : ""}
    ${c.heldBack ? `<div class="notice" style="margin-top:14px">${icon("info", 18)}<div>${esc(c.heldBack)}</div></div>` : ""}
    <dl class="facts"><dt>Frees</dt><dd class="mono">${fmt(c.bytes)}</dd><dt>Rebuild</dt><dd>${regenText[c.regen]}</dd><dt>Changed</dt><dd>${ago(c.ageDays)}</dd>
      ${c.git !== "notRepo" ? `<dt>Git</dt><dd>${{ pushed: "Everything is pushed", noRemote: "Repository with no remote", unpushed: "Has unpushed commits", dirty: "Has uncommitted changes" }[c.git]}</dd>` : ""}</dl>
    ${where ? `<div class="path">${esc(where)}</div>` : ""}
    <div class="plain"><small>${icon("sparkles", 14)}IN PLAIN WORDS</small>${esc(plainWords(c))}</div>
    ${c.targets.length ? `<div style="padding-top:18px"><button class="btn" data-act="reveal" data-path="${esc(c.targets[0])}">${icon("folder-open", 16)}Show in Explorer</button></div>` : ""}</aside>`;
  const root = $("#pop-root");
  if (swap) { root.innerHTML = html; $(".pop", root).style.animation = "none"; } else root.innerHTML = html;
}
function closeDetail(instant = false) {
  const pop = $(".pop");
  S.detail = null;
  if (!pop) return;
  if (instant || reduceMotion) { $("#pop-root").innerHTML = ""; return; }
  pop.classList.add("out"); setTimeout(() => { if (!S.detail) $("#pop-root").innerHTML = ""; }, 190);
}

// ---------- confirm + clean ----------
async function openConfirm() {
  const items = picked();
  if (!items.length) return;
  const ids = items.map((c) => c.id), pv = await invoke("preview_clean", { ids });
  const by = (list) => list.map((id) => items.find((c) => c.id === id)).filter(Boolean);
  const direct = by(pv.directIds), vaulted = by(pv.vaultIds);
  const yours = items.filter((c) => c.tier === "yours");
  const unbacked = yours.filter((c) => !["notRepo", "pushed"].includes(c.git));
  const names = (l) => l.slice(0, 4).map((c) => esc(c.title)).join(", ") + (l.length > 4 ? ` and ${l.length - 4} more` : "");
  const confirms = [
    ...yours.map((c) => `<label class="confirm"><input type="checkbox" data-need="1" data-kind="yours" data-id="${esc(c.id)}"><span>I want to remove <b>${esc(c.title)}</b>. I know it is mine.${c.note ? `<br><span class="muted">${esc(c.note)}</span>` : ""}</span></label>`),
    ...unbacked.map((c) => `<label class="confirm"><input type="checkbox" data-need="1" data-kind="unbacked" data-id="${esc(c.id)}"><span><b>${esc(c.title)}</b> is in a git repository with ${c.git === "dirty" ? "uncommitted changes" : c.git === "unpushed" ? "unpushed commits" : "no remote"}. A copy may not exist anywhere else.</span></label>`),
  ].join("");
  modal(`<div class="body"><h2>Free up ${fmt(pv.directBytes + pv.vaultBytes)}?</h2>
    ${direct.length ? `<div class="section"><h3>${icon("trash-2", 16)} Removed now (${fmt(pv.directBytes)})</h3><span class="muted">${names(direct)}. These come back by themselves when needed.</span></div>` : ""}
    ${vaulted.length ? `<div class="section"><h3>${icon("archive", 16)} Kept in the undo vault for 7 days (${fmt(pv.vaultBytes)})</h3><span class="muted">${names(vaulted)}. You can restore them in one click. The space returns when the vault is emptied.</span></div>` : ""}
    ${confirms}</div>
    <div class="foot"><button class="btn" data-act="modal-close">Cancel</button><button class="btn accent" id="do-clean" ${confirms ? "disabled" : ""}>Free up space</button></div>`);
  const dlg = $(".dialog");
  dlg.addEventListener("change", () => { $("#do-clean").disabled = $$("[data-need]", dlg).some((b) => !b.checked); });
  $("#do-clean").addEventListener("click", () => runClean(ids, dlg));
}

async function runClean(ids, dlg) {
  const need = (k) => $$(`[data-kind="${k}"]`, dlg).filter((b) => b.checked).map((b) => b.dataset.id);
  const declined = S.candidates.filter((c) => c.preselected && !c.heldBack && !S.selection.has(c.id)).map((c) => c.id);
  const confirmedYours = need("yours"), confirmedUnbacked = need("unbacked");
  dlg.innerHTML = `<div class="body"><h2>Working on it</h2><div class="row"><span class="spinner"></span><span class="muted" id="clean-now">Starting</span></div></div><div class="foot"></div>`;
  const stop = await listen("clean-progress", (e) => { const el = $("#clean-now"); if (el) el.textContent = e.payload; });
  let report;
  try { report = await invoke("clean", { req: { ids, confirmedYours, confirmedUnbacked, declined } }); }
  catch (e) { closeModal(); toast("Couldn't finish", String(e), true); return; }
  finally { stop?.(); }
  const done = new Set(report.results.filter((r) => ["deleted", "vaulted"].includes(r.status.kind)).map((r) => r.id));
  S.candidates = S.candidates.filter((c) => !done.has(c.id)); S.selection = new Set([...S.selection].filter((i) => !done.has(i))); S.plan = null;
  S.map.cache.clear();
  S.overview = await invoke("get_overview"); applyTheme();
  const line = (r) => {
    const k = r.status.kind, d = r.status.detail;
    const text = k === "deleted" ? "Removed" : k === "vaulted" ? `In the vault for ${d} days` : k === "skipped" ? `Skipped: ${d}` : `Couldn't remove: ${d}`;
    return `<div class="row between" style="padding:6px 0"><span>${esc(r.title)}</span><span class="${k === "failed" ? "" : "muted"}" style="${k === "failed" ? "color:var(--bad)" : ""}">${esc(text)}</span></div>`;
  };
  dlg.innerHTML = `<div class="body"><h2>${report.measuredFreed > 0 ? `${fmt(report.measuredFreed)} returned` : "Done"}</h2>
    <p class="muted">${report.measuredFreed > 0 ? "Measured on your drive just now." : "Items in the vault only free their space when the vault is emptied."}</p>
    <div class="section">${report.results.map(line).join("")}</div></div>
    <div class="foot">${report.vaultedBytes ? `<button class="btn" data-act="open-vault">Open vault</button>` : ""}<button class="btn accent" data-act="modal-close">Done</button></div>`;
  render();
}

// ---------- map ----------
const PALETTE = ["#F2542D", "#D4D4D8", "#7C93C3", "#C9962E", "#8A8A93", "#E58A6E"];
function worst(row, side) { const s = sum(row, (r) => r.a), mx = Math.max(...row.map((r) => r.a)), mn = Math.min(...row.map((r) => r.a)); return Math.max((side * side * mx) / (s * s), (s * s) / (side * side * mn)); }
function lay(row, r, out) {
  const s = sum(row, (x) => x.a);
  if (r.w >= r.h) { const w = s / r.h; let y = r.y; for (const it of row) { const h = it.a / w; out.push({ ...it, x: r.x, y, w, h }); y += h; } return { x: r.x + w, y: r.y, w: r.w - w, h: r.h }; }
  const h = s / r.w; let x = r.x; for (const it of row) { const w = it.a / h; out.push({ ...it, x, y: r.y, w, h }); x += w; } return { x: r.x, y: r.y + h, w: r.w, h: r.h - h };
}
function squarify(items, w, h) {
  const out = [], total = sum(items, (i) => i.bytes);
  if (!total || w < 2 || h < 2) return out;
  const rest = items.filter((i) => i.bytes > 0).sort((a, b) => b.bytes - a.bytes).map((i) => ({ ...i, a: (i.bytes / total) * w * h }));
  let row = [], rect = { x: 0, y: 0, w, h };
  while (rest.length) {
    const side = Math.min(rect.w, rect.h), next = rest[0];
    if (!row.length || worst([...row, next], side) <= worst(row, side)) { row.push(next); rest.shift(); } else { rect = lay(row, rect, out); row = []; }
  }
  if (row.length) lay(row, rect, out);
  return out;
}

async function mapInit() {
  const [drives, places] = await Promise.all([invoke("list_drives"), invoke("known_places")]);
  S.map.drives = drives; S.map.places = places;
}
async function mapOpen(path, name, mode = "push") {
  const m = S.map;
  if (mode === "push") m.stack.push({ path, name });
  m.loading = true; m.stopped = false; m.elapsed = 0; m.tree = null; render();
  clearInterval(m.timer); const t0 = Date.now(); let seen = { files: 0, bytes: 0 };
  const paint = () => { const el = $("#map-wait"); if (el) el.textContent = `Measuring ${name} · ${Math.floor((Date.now() - t0) / 1000)}s${seen.files ? ` · ${seen.files.toLocaleString()} files · ${fmt(seen.bytes)} so far` : ""}`; };
  m.timer = setInterval(paint, 500);
  const stop = await listen("map-progress", (e) => { seen = e.payload; paint(); });
  try {
    const cached = m.cache.get(path);
    m.tree = cached || await invoke("map_tree", { path });
    if (!cached && !m.stopped) m.cache.set(path, m.tree);
  } catch (e) { toast("Couldn't read that folder", String(e), true); m.stack.pop(); }
  finally { stop?.(); }
  clearInterval(m.timer); m.loading = false; render();
}
const mapTop = () => S.map.stack.at(-1);
async function mapRefresh() { const top = mapTop(); if (!top) return mapInit().then(render); S.map.cache.delete(top.path); await mapOpen(top.path, top.name, "reload"); }
async function pickFolder() {
  const dlg = window.__TAURI__.dialog;
  const dir = dlg ? await dlg.open({ directory: true, multiple: false, title: "Choose a folder to map" }) : null;
  if (!dir) return;
  const path = typeof dir === "string" ? dir : dir.path;
  S.map.stack = []; await mapOpen(path, path.split(/[\\/]/).filter(Boolean).pop() || path);
}

function viewMap() {
  const m = S.map;
  const crumbs = [`<button data-act="map-root">${icon("hard-drive", 15)} All drives</button>`, ...m.stack.map((s, i) => `${icon("chevron-right", 14)}<button data-act="map-to" data-i="${i}">${esc(s.name)}</button>`)].join("");
  const places = `<select data-act="map-place" aria-label="Jump to"><option value="">Jump to…</option>${m.places.map((p) => `<option value="${esc(p.path)}">${esc(p.name)}</option>`).join("")}</select>`;
  const head = `<div><p class="eyebrow">Map</p><h1>Where your space went.</h1><p class="lede">Every folder, drawn by size. Nothing here changes anything.</p></div>`;
  if (!m.stack.length) {
    return `${head}<div class="maptools"><button class="btn" data-act="pick-folder">${icon("folder-open", 16)}Choose a folder…</button>${places}</div>
      <div class="grid g3">${m.drives.map((d) => { const used = Math.round(((d.total - d.free) / d.total) * 100); return `<button class="card tile" data-act="map-drive" data-path="${esc(d.path)}" data-name="${esc(d.name)}"><div class="row">${icon("hard-drive")}<h3 style="margin:0">${esc(d.name)}</h3></div><div class="v">${fmt(d.free)}</div><div class="muted" style="margin-bottom:10px">free of ${fmt(d.total)}</div><div class="gauge"><i style="width:${used}%"></i></div></button>`; }).join("")}</div>`;
  }
  const tools = `<div class="maptools">${seg("modeseg", "View", [["treemap", `${icon("layout-grid", 15)}Treemap`], ["list", `${icon("list", 15)}List`]], m.mode, "map-mode")}
    <button class="btn icon" data-act="map-up" title="Up one level" aria-label="Up one level">${icon("arrow-up", 16)}</button>
    <button class="btn icon" data-act="map-refresh" title="Measure again" aria-label="Refresh">${icon("refresh-cw", 16)}</button>
    <span class="grow"></span><button class="btn" data-act="pick-folder">${icon("folder-open", 16)}Choose a folder…</button>${places}</div>`;
  let body;
  if (m.loading) body = `<div class="card row between"><div class="row"><span class="spinner"></span><span class="muted" id="map-wait">Measuring ${esc(mapTop().name)}</span></div><button class="btn" data-act="map-cancel">Stop</button></div>`;
  else if (!m.tree || !m.tree.children.length) body = `<div class="card empty">${icon("folder-open", 32)}<div>Nothing here.</div></div>`;
  else if (m.mode === "list") body = mapTable();
  else body = `<div class="map" id="mapbox"></div><div class="mapstatus" id="mapstatus">${mapSummary()}</div>`;
  const sxs = /[\\/]winsxs$/i.test(mapTop().path) ? `<div class="notice">${icon("info", 18)}<div>Windows shares these files with other folders (hard links), so the sizes here look bigger than what is really used. To free space, use Windows' own cleanup rather than deleting anything in here.</div></div>` : "";
  const drive = m.stack.length === 1 ? m.drives.find((d) => d.path.toLowerCase() === mapTop().path.toLowerCase()) : null;
  const bar = drive ? `<div class="drivebar"><div class="gauge" role="img" aria-label="Drive usage"><i style="width:${Math.round(((drive.total - drive.free) / drive.total) * 100)}%"></i></div><span class="muted mono">${fmt(drive.total - drive.free)} used · ${fmt(drive.free)} free of ${fmt(drive.total)}</span></div>` : "";
  return `${head}<div class="crumbs">${crumbs}</div>${tools}${bar}${sxs}${body}`;
}
const mapSummary = () => { const t = S.map.tree; return t ? `<b>${esc(t.name)}</b> · ${fmt(t.bytes)} in ${t.files.toLocaleString()} files${S.map.stopped ? " · stopped early, so this is partial" : ""}. Click a folder to look inside, a file to show it in Explorer.` : ""; };

function sortedChildren() {
  const { k, d } = S.map.sort;
  return [...S.map.tree.children].sort((a, b) => k === "name" ? d * a.name.localeCompare(b.name) : k === "files" ? d * (a.files - b.files) : d * (a.bytes - b.bytes));
}
function mapTable() {
  const t = S.map.tree, all = sortedChildren(), kids = all.slice(0, 1000), max = Math.max(...kids.map((c) => c.bytes), 1);
  const arrow = (k) => S.map.sort.k === k ? (S.map.sort.d < 0 ? " ↓" : " ↑") : "";
  const row = (c) => {
    const open = c.kind === "dir" ? `data-act="map-open" data-path="${esc(c.path)}" data-name="${esc(c.name)}"` : c.kind === "file" ? `data-act="reveal" data-path="${esc(c.path)}"` : "";
    return `<tr class="${open ? "rowlink" : ""}" ${open}><td><div class="name">${icon(c.kind === "dir" ? "folder" : "file", 18)}<span>${esc(c.name)}</span></div></td>
      <td style="width:26%"><div class="bar"><i style="width:${(c.bytes / max) * 100}%"></i></div></td><td class="r">${fmt(c.bytes)}</td><td class="r">${((c.bytes / t.bytes) * 100).toFixed(1)}%</td><td class="r">${c.kind === "dir" || c.kind === "files" || c.kind === "other" ? c.files.toLocaleString() : ""}</td></tr>`;
  };
  return `<div class="card tight"><table class="table"><thead><tr><th data-act="map-sort" data-k="name">Name${arrow("name")}</th><th></th><th class="r" data-act="map-sort" data-k="bytes">Size${arrow("bytes")}</th><th class="r">Share</th><th class="r" data-act="map-sort" data-k="files">Files${arrow("files")}</th></tr></thead><tbody>${kids.map(row).join("")}</tbody></table></div>
    <div class="mapstatus">${all.length > kids.length ? `Showing the ${kids.length.toLocaleString()} biggest of ${all.length.toLocaleString()}. ` : ""}${mapSummary()}</div>`;
}

// Blocks too small to read are merged into one "smaller items" block, so the map never turns into dots.
function fitItems(items, w, h, minArea, maxCount) {
  const total = sum(items, (i) => i.bytes);
  if (!total) return [];
  const area = w * h, keep = [];
  let lump = null;
  const count = (it) => (it.kind === "other" || it.kind === "files") ? (parseInt(it.name.replace(/[^0-9]/g, ""), 10) || 1) : 1;
  for (const it of [...items].sort((a, b) => b.bytes - a.bytes)) {
    if (keep.length < maxCount && (it.bytes / total) * area >= minArea) { keep.push(it); continue; }
    lump ??= { name: "", path: "", bytes: 0, kind: "other", files: 0, children: [], n: 0 };
    lump.bytes += it.bytes; lump.files += it.files; lump.n += count(it);
  }
  if (lump) { lump.name = `${lump.n.toLocaleString()} smaller items`; keep.push(lump); }
  return keep;
}
const radius = (w, h) => Math.max(2, Math.min(8, Math.min(w, h) / 7));

function cellHtml(n, x, y, w, h, color, depth) {
  const open = n.kind === "dir" ? `data-act="map-open" data-path="${esc(n.path)}" data-name="${esc(n.name)}"` : n.kind === "file" ? `data-act="reveal" data-path="${esc(n.path)}"` : n.kind === "other" && depth === 0 ? `data-act="map-list" title="Click to list them all"` : "";
  const fs = Math.max(10, Math.min(14, Math.min(w / 9, h / 2.6)));
  const showName = w > 44 && h > 20, showSize = w > 74 && h > 36;
  const hasKids = n.kind === "dir" && n.children?.length && w > 120 && h > 84 && depth === 0;
  let inner = "";
  if (hasKids) {
    const kids = squarify(fitItems(n.children, w - 8, h - 30, 520, 24), w - 8, h - 30);
    inner = kids.map((k, j) => cellHtml(k, k.x + 4, k.y + 26, k.w, k.h, `color-mix(in srgb, ${color} ${j % 2 ? 62 : 74}%, white)`, 1)).join("");
  }
  const cls = `cell${n.kind === "files" || n.kind === "other" ? " lump" : ""}${hasKids ? "" : " leaf"}`;
  return `<div class="${cls}" ${open} style="left:${x}px;top:${y}px;width:${Math.max(0, w - 2)}px;height:${Math.max(0, h - 2)}px;background:${color};font-size:${fs}px;border-radius:${radius(w, h)}px" data-name="${esc(n.name)}" data-bytes="${n.bytes}" data-files="${n.files}">
    ${showName ? `<span class="hd">${esc(n.name)}${showSize || hasKids ? `<small>${fmt(n.bytes)}</small>` : ""}</span>` : ""}${inner}</div>`;
}
function layoutMap() {
  const box = $("#mapbox"), t = S.map.tree;
  if (!box || !t) return;
  const W = box.clientWidth, H = box.clientHeight;
  // Free space is not drawn as a block (it would waste the map); it is the thin bar above.
  const cells = squarify(fitItems(t.children.map((c) => ({ ...c })), W, H, 760, 140), W, H);
  box.innerHTML = cells.map((c, i) => cellHtml(c, c.x, c.y, c.w, c.h, PALETTE[i % PALETTE.length], 0)).join("");
}
let resizeT;
addEventListener("resize", () => { clearTimeout(resizeT); resizeT = setTimeout(() => { placeThumbs(); if (S.view === "map") layoutMap(); }, 120); });

// ---------- vault ----------
function viewVault() {
  const b = (v) => {
    const note = v.drives.length && !v.available ? `On ${v.drives.map(esc).join(", ")}. Connect the drive to restore or delete it.` : v.drives.length ? `Kept on ${v.drives.map(esc).join(", ")}, so nothing was copied.` : v.usesRecycleBin ? "This drive can't hold a vault, so these items are in the Recycle Bin." : "";
    return `<div class="card row between"><div style="min-width:0"><h3 style="margin:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(v.label)}</h3>
      <span class="muted">${v.entries.length} item${v.entries.length === 1 ? "" : "s"}, deleted ${new Date(v.created * 1000).toLocaleString([], { dateStyle: "medium", timeStyle: "short" })}</span>${note ? `<br><span class="muted">${note}</span>` : ""}</div>
      <div class="row"><span class="badge"><i class="dot rebuildable"></i>${left(v.expires)}</span><span class="mono" style="width:80px;text-align:right">${fmt(v.totalBytes)}</span>
      <button class="btn" data-act="restore" data-id="${esc(v.id)}">${icon("undo-2", 16)}Restore</button><button class="btn subtle danger" data-act="purge" data-id="${esc(v.id)}">Delete now</button></div></div>`;
  };
  return `<div class="row between" style="align-items:flex-end"><div><p class="eyebrow">Vault</p><h1>Changed your mind? Undo here.</h1></div>${S.vault.length ? `<button class="btn" data-act="empty-vault">Empty vault</button>` : ""}</div>
    <p class="lede">Your files, installers and zips wait here for 7 days after you delete them. The space only comes back when the vault is emptied.</p>
    ${S.vault.length ? `<div class="stack"><div class="muted mono">${fmt(sum(S.vault, (v) => v.totalBytes))} in ${S.vault.length} batch${S.vault.length === 1 ? "" : "es"}</div>${S.vault.map(b).join("")}</div>`
      : `<div class="card empty">${icon("archive", 32)}<div><b>The vault is empty.</b></div><div>When you delete something that is yours, it waits here so you can put it back.</div></div>`}`;
}

// ---------- settings ----------
function viewSettings() {
  const s = settings();
  const row = (title, body, control) => `<div class="row between" style="padding:16px 0;border-top:1px solid var(--stroke)"><div style="max-width:560px"><h3>${title}</h3><span class="muted">${body}</span></div>${control}</div>`;
  const mine = PERSONAS.filter((p) => s.workTypes.includes(p.id)).map((p) => p.title);
  return `<div><p class="eyebrow">Settings</p><h1>Make Room yours.</h1></div>
    <div class="card" style="padding:6px 22px"><h2 style="margin:16px 0 0">Your work</h2>
      ${row("What you do most on this PC", mine.length ? esc(mine.join(", ")) : "Not set. Room checks for everyone's usual suspects.", `<button class="btn" data-act="redo-onboarding">Change</button>`)}
      <h2 style="margin:20px 0 0">Cleaning</h2>
      ${row("Keep rebuildable folders in the vault too", "Folders like node_modules wait 7 days in the undo vault instead of being removed right away. Caches are always removed directly.", `<input type="checkbox" class="switch" data-act="set-vault" ${s.vaultRebuildable ? "checked" : ""} aria-label="Keep rebuildable folders in the vault">`)}
      ${row("A project counts as stale after", "Only stale projects have their node_modules suggested.", `<select data-act="set-stale" aria-label="Stale after">${[30, 60, 90, 180].map((d) => `<option value="${d}" ${s.staleProjectDays === d ? "selected" : ""}>${d} days</option>`).join("")}</select>`)}
      <h2 style="margin:20px 0 0">Appearance</h2>
      ${row("Theme", "Room follows Windows by default.", seg("themeseg", "Theme", [["system", "System"], ["light", "Light"], ["dark", "Dark"]], s.appearance, "set-theme"))}
      <h2 style="margin:20px 0 0">Privacy</h2>
      <div style="padding:16px 0;border-top:1px solid var(--stroke)" class="row">${icon("shield-check")}<span class="muted" style="max-width:640px">Room has no accounts and sends nothing anywhere. What it learns from your choices stays on this PC, in a file you can delete.</span></div>
    </div>`;
}
async function saveSettings(patch) {
  const next = { ...settings(), ...patch };
  S.overview = await invoke("save_settings", { settings: next });
  if (patch.appearance !== undefined) { const effect = await invoke("set_window_theme", { theme: patch.appearance }); S.overview.effect = effect; }
  applyTheme();
}

// ---------- onboarding ----------
function openOnboarding(step = 0) { S.onboard = { step, picks: new Set(settings().workTypes) }; drawOnboarding(); }
function onboardingHtml() {
  const { step, picks } = S.onboard;
  const steps = `<div class="steps"><i class="on"></i><i class="${step >= 1 ? "on" : ""}"></i></div>`;
  if (step === 0) return `<div class="body">${steps}<div style="width:46px">${MARK}</div><h2 style="font-size:30px;margin-top:12px">Welcome to Room</h2>
      <p class="muted" style="font-size:15px">Room finds what is safe to remove, shows you exactly what it will do, and only cleans after you say so.</p>
      <div class="stack" style="margin-top:14px">
        <div class="row" style="align-items:flex-start">${icon("list-checks")}<span>Every suggestion says what it is and how hard it is to get back.</span></div>
        <div class="row" style="align-items:flex-start">${icon("archive")}<span>Anything that might be yours waits 7 days in an undo vault.</span></div>
        <div class="row" style="align-items:flex-start">${icon("shield-check")}<span>No accounts. Nothing leaves this PC.</span></div></div></div>
      <div class="foot"><button class="btn subtle" data-act="onb-skip">Skip</button><button class="btn accent" data-act="onb-next">Continue</button></div>`;
  return `<div class="body">${steps}<h2 style="font-size:26px">What do you do most on this PC?</h2>
      <p class="muted">Pick as many as you like. Room uses this to look in the right places. It never changes how careful Room is.</p>
      <div class="persona-grid">${PERSONAS.map((p) => `<button class="persona" data-act="persona" data-id="${p.id}" aria-pressed="${picks.has(p.id)}"><span class="ico">${icon(p.icon, 20)}</span><b>${esc(p.title)}</b><small>${esc(p.hint)}</small><span class="tick">${icon("check", 18)}</span></button>`).join("")}</div></div>
      <div class="foot"><button class="btn subtle" data-act="onb-skip">Skip</button><button class="btn accent" id="onb-done" data-act="onb-done">${onboardingLabel()}</button></div>`;
}
const onboardingLabel = () => S.onboard.picks.size ? `Continue with ${S.onboard.picks.size}` : "Just everyday use";
function drawOnboarding() {
  const dlg = $(".dialog");
  if (dlg) { dlg.innerHTML = onboardingHtml(); $(".body", dlg).style.animation = "rise .4s var(--out) both"; } // a step change, not a new window
  else modal(onboardingHtml(), "wide");
}
async function finishOnboarding(picks) {
  closeModal();
  await saveSettings({ workTypes: [...picks], onboarded: true });
  S.onboard = null;
  render(); startScan();
}

// ---------- modal ----------
function modal(html, size = "") {
  $("#modal-root").innerHTML = `<div class="smoke" data-act="smoke"><div class="dialog ${size}" role="dialog" aria-modal="true">${html}</div></div>`;
  $(".dialog button:not([disabled])")?.focus();
}
function closeModal() {
  const s = $(".smoke");
  if (!s) return;
  if (reduceMotion) { $("#modal-root").innerHTML = ""; return; }
  s.classList.add("out"); setTimeout(() => { $("#modal-root").innerHTML = ""; }, 170);
}

// ---------- scanning ----------
async function startScan() {
  if (S.scanning) return;
  S.scanning = true; S.scanLabel = ""; render();
  const stop = await listen("scan-progress", (e) => { S.scanLabel = e.payload; const el = $("#scan-now"); if (el) el.textContent = `Measuring ${e.payload}`; });
  try {
    S.candidates = await invoke("scan");
    S.selection = new Set(S.candidates.filter((c) => c.preselected && !c.heldBack).map((c) => c.id));
    S.plan = null; S.scannedOnce = true;
  } catch (e) { toast("The scan didn't finish", String(e), true); }
  finally { stop?.(); S.scanning = false; S.overview = await invoke("get_overview"); render(); }
}

// ---------- events ----------
document.addEventListener("click", async (e) => {
  // A click anywhere outside the details card closes it (and still does whatever was clicked).
  if (S.detail && !e.target.closest(".pop") && !e.target.closest('[data-act="detail"]')) closeDetail();
  const el = e.target.closest("[data-act]");
  if (!el) return;
  const a = el.dataset.act, d = el.dataset;
  if (a === "toggle") { e.stopPropagation(); el.checked ? S.selection.add(d.id) : S.selection.delete(d.id); updateTotal(); return; }
  if (a === "smoke") { if (e.target === el && !S.onboard) closeModal(); return; }
  switch (a) {
    case "go": return go(d.view);
    case "toggle-nav": return toggleNav();
    case "filter":
      if (S.view === "overview") { S.filter = d.v; return go("review"); }
      S.filter = d.v; press($("#filterseg"), el); $("#reviewlist").innerHTML = reviewList(); $("#count").textContent = `${visible().length} item${visible().length === 1 ? "" : "s"}`; return;
    case "goal": S.goalGB = +d.gb; S.plan = null; press($("#goalseg"), el); $("#plan-btn").textContent = `Plan ${S.goalGB} GB`; $("#plan").innerHTML = ""; return;
    case "plan": S.plan = await invoke("make_plan", { goalBytes: S.goalGB * 1e9 }); $("#plan").innerHTML = planHtml(); return;
    case "review-plan": S.selection = new Set(S.plan.itemIds); S.filter = "all"; return go("review");
    case "rescan": return startScan();
    case "detail": return openDetail(d.id);
    case "close-detail": return closeDetail();
    case "reveal": return invoke("reveal", { path: d.path });
    case "confirm": return openConfirm();
    case "modal-close": return closeModal();
    case "open-vault": closeModal(); return go("vault");
    case "map-root": S.map.stack = []; S.map.tree = null; return render(true);
    case "map-drive": case "map-open": return mapOpen(d.path, d.name);
    case "map-to": S.map.stack = S.map.stack.slice(0, +d.i + 1); return mapOpen(mapTop().path, mapTop().name, "reload");
    case "map-up": if (S.map.stack.length > 1) { S.map.stack.pop(); return mapOpen(mapTop().path, mapTop().name, "reload"); } S.map.stack = []; S.map.tree = null; return render(true);
    case "map-refresh": return mapRefresh();
    case "map-cancel": S.map.stopped = true; return invoke("map_cancel");
    case "map-mode": S.map.mode = d.v; store.set("mapMode", d.v); press($("#modeseg"), el); setTimeout(() => render(), 200); return;
    case "map-list": S.map.mode = "list"; store.set("mapMode", "list"); return render(true);
    case "map-sort": { const s = S.map.sort; s.d = s.k === d.k ? -s.d : (d.k === "name" ? 1 : -1); s.k = d.k; return render(); }
    case "pick-folder": return pickFolder();
    case "restore":
      try { const n = await invoke("vault_restore", { id: d.id }); toast("Restored", `${n} item${n === 1 ? "" : "s"} back where ${n === 1 ? "it was" : "they were"}`); }
      catch (err) { toast("Couldn't restore", String(err), true); }
      S.vault = await invoke("vault_list"); S.overview = await invoke("get_overview"); return render();
    case "purge": {
      const ok = await invoke("vault_purge", { id: d.id });
      S.vault = await invoke("vault_list"); S.overview = await invoke("get_overview");
      ok ? toast("Deleted", "The space is back.") : toast("That drive isn't connected", "Connect it and try again.", true);
      return render();
    }
    case "empty-vault": await invoke("vault_empty"); S.vault = await invoke("vault_list"); S.overview = await invoke("get_overview"); toast("Vault emptied"); return render();
    case "set-theme": press($("#themeseg"), el); await saveSettings({ appearance: d.v }); return;
    case "redo-onboarding": return openOnboarding(1);
    case "persona": {
      S.onboard.picks.has(d.id) ? S.onboard.picks.delete(d.id) : S.onboard.picks.add(d.id);
      el.setAttribute("aria-pressed", S.onboard.picks.has(d.id));          // update in place: no redraw, no flash
      $("#onb-done").textContent = onboardingLabel(); return;
    }
    case "onb-next": S.onboard.step = 1; return drawOnboarding();
    case "onb-skip": return finishOnboarding(new Set(settings().workTypes));
    case "onb-done": return finishOnboarding(S.onboard.picks);
  }
});
document.addEventListener("change", async (e) => {
  const el = e.target.closest("[data-act]");
  if (!el) return;
  if (el.dataset.act === "set-vault") await saveSettings({ vaultRebuildable: el.checked });
  if (el.dataset.act === "set-stale") { await saveSettings({ staleProjectDays: +el.value }); toast("Saved", "Scan again to apply."); }
  if (el.dataset.act === "map-place" && el.value) { const p = S.map.places.find((x) => x.path === el.value); S.map.stack = []; mapOpen(p.path, p.name); }
});
document.addEventListener("mouseover", (e) => {
  const c = e.target.closest(".cell");
  const st = $("#mapstatus");
  if (!st || !c) return;
  const t = S.map.tree, b = +c.dataset.bytes;
  st.innerHTML = `<b>${esc(c.dataset.name)}</b> · ${fmt(b)}${t?.bytes ? ` · ${((b / t.bytes) * 100).toFixed(1)}% of ${esc(t.name)}` : ""}${+c.dataset.files ? ` · ${(+c.dataset.files).toLocaleString()} files` : ""}`;
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") { if (S.detail) closeDetail(); else if (!S.onboard) closeModal(); }
  if ((e.key === "Enter" || e.key === " ") && e.target.matches?.(".item")) { e.preventDefault(); e.target.click(); }
});

// ---------- start ----------
S.overview = await invoke("get_overview");
applyTheme();
S.vault = await invoke("vault_list");
buildShell();
render(true);
if (!settings().onboarded) openOnboarding(0); else startScan();
