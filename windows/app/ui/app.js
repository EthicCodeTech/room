import { ICONS } from "./icons.js";
import { PERSONAS } from "./personas.js";

// Inside the app, Tauri provides the bridge. In a plain browser (design preview) a pretend backend stands in.
if (!window.__TAURI__) await import("./mock.js");
const invoke = (cmd, args) => window.__TAURI__.core.invoke(cmd, args);
const listen = (name, fn) => window.__TAURI__.event.listen(name, fn);

// ---------- helpers ----------
const $ = (sel, root = document) => root.querySelector(sel);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const icon = (name, size = 20) => `<svg class="i" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name] || ""}</svg>`;
const MARK = `<svg viewBox="0 0 48 48" aria-hidden="true"><path fill="currentColor" d="M12 42V10a6 6 0 0 1 6-6h12a6 6 0 0 1 6 6v32h-4V10a2 2 0 0 0-2-2H18a2 2 0 0 0-2 2v32z"/><rect fill="currentColor" x="6" y="40" width="36" height="4" rx="2"/><circle cx="28" cy="25" r="3.2" fill="#F2542D"/></svg>`;

function fmt(bytes) {
  if (bytes < 1000) return `${bytes} bytes`;
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

// ---------- state ----------
const S = {
  view: "overview", overview: null, candidates: [], scanning: false, scanLabel: "", scannedOnce: false,
  selection: new Set(), filter: "all", detail: null, goalGB: 24, plan: null,
  vault: [], map: { drives: [], stack: [], nodes: [], loading: false },
  onboard: null,
};
const settings = () => S.overview?.settings;

function toast(title, detail = "", bad = false) {
  const el = document.createElement("div");
  el.className = `toast${bad ? " bad" : ""}`;
  el.innerHTML = `<b>${esc(title)}</b>${detail ? `<span class="muted">${esc(detail)}</span>` : ""}`;
  $("#toasts").append(el);
  setTimeout(() => el.remove(), 5200);
}

function applyTheme() {
  const root = document.documentElement, o = S.overview;
  if (!o) return;
  const a = o.settings.appearance;
  if (a === "light" || a === "dark") root.dataset.theme = a; else delete root.dataset.theme;
  root.dataset.effect = o.effect;
}

// ---------- navigation ----------
const NAV = [["overview", "Overview", "layout-dashboard"], ["review", "Review", "list-checks"], ["map", "Map", "folder-tree"], ["vault", "Vault", "archive"]];
function renderNav() {
  const count = { review: S.candidates.filter((c) => !c.heldBack).length || "", vault: S.vault.length || S.overview?.vaultBatches || "" };
  const item = ([id, label, ic]) => `<button data-act="go" data-view="${id}" ${S.view === id ? 'aria-current="page"' : ""}>${icon(ic)}<span>${label}</span>${count[id] ? `<em class="count" style="font-style:normal">${count[id]}</em>` : ""}</button>`;
  $("#nav").innerHTML = `<div class="brand">${MARK}<span>Room</span></div>${NAV.map(item).join("")}<div class="spacer"></div>${item(["settings", "Settings", "settings"])}<div class="foot">Version ${esc(S.overview?.version || "")}</div>`;
}

async function go(view) {
  S.view = view; S.detail = null;
  if (view === "vault") S.vault = await invoke("vault_list");
  if (view === "map" && !S.map.stack.length) await openDrives();
  render(true);
  $("#view").scrollTo(0, 0);
}

function render(enter = false) {
  renderNav();
  const v = { overview: viewOverview, review: viewReview, map: viewMap, vault: viewVault, settings: viewSettings }[S.view];
  $("#view").innerHTML = `<div class="page${enter ? " enter" : ""}">${v()}</div>${S.detail ? flyout() : ""}`;
}

// ---------- overview ----------
function viewOverview() {
  const o = S.overview, used = o.total ? Math.round(((o.total - o.free) / o.total) * 100) : 0;
  const mood = used >= 90 ? "It is getting tight. Let's make some room." : used >= 75 ? "You have room to work. Keep an eye on what grows." : "Plenty of room. Nothing needs doing right now.";
  const by = (t) => S.candidates.filter((c) => c.tier === t && !c.heldBack);
  const tile = (t, label, hint) => `<button class="card tile" data-act="filter" data-tier="${t}"><span class="badge"><i class="dot ${t}"></i>${label}</span><div class="v">${fmt(sum(by(t)))}</div><div class="muted">${hint}</div></button>`;
  const planned = S.plan;
  return `
    <p class="eyebrow">Storage</p>
    <h1>Your PC has <span class="num">${fmt(o.free)}</span> left.</h1>
    <p class="lede">${mood}</p>
    <div class="grid g2">
      <div class="card stack">
        <div class="row between"><h3>Free space on ${esc(o.drive)}</h3><span class="muted mono">${used}% used</span></div>
        <div class="big-num">${fmt(o.free)}</div><div class="muted mono">of ${fmt(o.total)}</div>
        <div class="gauge" role="img" aria-label="${used} percent used"><i style="width:${used}%"></i></div>
      </div>
      <div class="card stack">
        <h2>How much room do you need?</h2>
        <p class="muted" style="margin:0">A Windows feature update needs about 24 GB free. Pick a target and Room plans the safest way to reach it.</p>
        <div class="seg" role="group" aria-label="Target free space">${[10, 24, 50, 100].map((g) => `<button data-act="goal" data-gb="${g}" aria-pressed="${S.goalGB === g}">${g} GB</button>`).join("")}</div>
        <div class="row"><button class="btn accent" data-act="plan" ${S.scanning ? "disabled" : ""}>Plan ${S.goalGB} GB</button></div>
        ${planned ? `<div class="notice">${icon("sparkles", 18)}<div>${planned.itemIds.length} item${planned.itemIds.length === 1 ? "" : "s"}, about <b>${fmt(planned.guaranteedBytes)}</b>.
          ${planned.reachesGoal ? "That reaches your goal using only safe and rebuildable items." : `That is ${fmt(planned.shortfall)} short. The rest would have to come from files only you can judge.`}
          <div style="margin-top:8px"><button class="btn" data-act="review-plan">Review the plan</button></div></div></div>` : ""}
      </div>
    </div>
    <div style="margin:24px 0 12px" class="row between"><h2 style="margin:0">${S.scanning ? "Looking for space" : "What Room found"}</h2>
      <button class="btn subtle" data-act="rescan" ${S.scanning ? "disabled" : ""}>${icon("refresh-cw", 16)}Scan again</button></div>
    ${S.scanning ? `<div class="card row"><span class="spinner"></span><span class="muted">Measuring ${esc(S.scanLabel || "caches, projects and downloads")}</span></div>` : `
    <div class="grid g3">${tile("safe", "Safe", "Caches that rebuild by themselves")}${tile("rebuildable", "Rebuildable", "Takes time or bandwidth to get back")}${tile("yours", "Yours", "Could be your work. Always your call")}</div>
    <div class="card row between" style="margin-top:16px">
      <div class="row">${icon("archive")}<div><h3 style="margin:0">Undo vault</h3><span class="muted">${S.overview.vaultBatches ? `${fmt(S.overview.vaultBytes)} waiting, restorable for 7 days` : "Empty. Your own files wait here for 7 days after you delete them."}</span></div></div>
      <button class="btn" data-act="go" data-view="vault">Open vault</button></div>`}`;
}

// ---------- review ----------
const visible = () => S.candidates.filter((c) => S.filter === "all" || c.tier === S.filter);
const picked = () => S.candidates.filter((c) => S.selection.has(c.id));

function viewReview() {
  const list = visible(), total = sum(picked());
  const filters = [["all", "All"], ["safe", "Safe"], ["rebuildable", "Rebuildable"], ["yours", "Yours"]];
  const row = (c) => `<div class="item ${c.heldBack ? "held" : ""}" tabindex="0" data-act="detail" data-id="${esc(c.id)}">
      <input type="checkbox" data-act="toggle" data-id="${esc(c.id)}" ${S.selection.has(c.id) ? "checked" : ""} ${c.heldBack ? "disabled" : ""} aria-label="Select ${esc(c.title)}">
      <div style="min-width:0"><div class="title">${esc(c.title)}</div><div class="sub">${esc(c.heldBack || c.why)}</div></div>
      ${badge(c.tier)}<div class="size">${fmt(c.bytes)}</div></div>`;
  return `
    <p class="eyebrow">Review</p>
    <h1>Nothing happens until you say so.</h1>
    <p class="lede">Each suggestion says what it is, what you get, and how hard it is to get back. Nothing in <b>Yours</b> is ticked for you.</p>
    <div class="row between" style="margin-bottom:12px"><div class="seg" role="group" aria-label="Filter">${filters.map(([k, l]) => `<button data-act="filter" data-tier="${k}" aria-pressed="${S.filter === k}">${l}</button>`).join("")}</div>
      <span class="muted mono">${list.length} item${list.length === 1 ? "" : "s"}</span></div>
    ${S.scanning ? `<div class="card row"><span class="spinner"></span><span class="muted">Still scanning. More may appear.</span></div>` : list.length ? `<div class="card tight list">${list.map(row).join("")}</div>`
      : `<div class="card empty">${icon("check", 32)}<div><b>Nothing here.</b></div><div>Room didn't find anything in this group.</div></div>`}
    <div class="actionbar"><div><div class="muted">Selected</div><div class="total">${fmt(total)}</div></div>
      <button class="btn accent big" data-act="confirm" ${S.selection.size ? "" : "disabled"}>Free up ${fmt(total)}${icon("arrow-right", 18)}</button></div>`;
}

function flyout() {
  const c = S.candidates.find((x) => x.id === S.detail);
  if (!c) return "";
  const where = c.targets.length > 1 ? `${c.targets.length} items in ${c.displayPath}` : c.displayPath;
  return `<aside class="flyout" role="dialog" aria-label="Details">
    <div class="row between">${badge(c.tier)}<button class="btn subtle" data-act="close-detail" aria-label="Close">${icon("x", 18)}</button></div>
    <h2 style="margin-top:14px">${esc(c.title)}</h2><p class="muted">${esc(c.why)}</p>
    ${c.note ? `<div class="notice" style="margin-bottom:12px">${icon("triangle-alert", 18)}<div>${esc(c.note)}</div></div>` : ""}
    ${c.heldBack ? `<div class="notice" style="margin-bottom:12px">${icon("info", 18)}<div>${esc(c.heldBack)}</div></div>` : ""}
    <dl class="facts"><dt>Frees</dt><dd class="mono">${fmt(c.bytes)}</dd><dt>Rebuild</dt><dd>${regenText[c.regen]}</dd><dt>Changed</dt><dd>${ago(c.ageDays)}</dd>
      ${c.git !== "notRepo" ? `<dt>Git</dt><dd>${{ pushed: "Everything is pushed", noRemote: "Repository with no remote", unpushed: "Has unpushed commits", dirty: "Has uncommitted changes" }[c.git]}</dd>` : ""}</dl>
    ${where ? `<div class="path">${esc(where)}</div>` : ""}
    ${c.targets.length ? `<div style="margin-top:16px"><button class="btn" data-act="reveal" data-path="${esc(c.targets[0])}">${icon("folder-open", 16)}Show in Explorer</button></div>` : ""}</aside>`;
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
  const sync = () => { $("#do-clean").disabled = [...dlg.querySelectorAll("[data-need]")].some((b) => !b.checked); };
  dlg.addEventListener("change", sync);
  $("#do-clean").addEventListener("click", () => runClean(ids, dlg));
}

async function runClean(ids, dlg) {
  const need = (k) => [...dlg.querySelectorAll(`[data-kind="${k}"]`)].filter((b) => b.checked).map((b) => b.dataset.id);
  const declined = S.candidates.filter((c) => c.preselected && !c.heldBack && !S.selection.has(c.id)).map((c) => c.id);
  dlg.innerHTML = `<div class="body"><h2>Working on it</h2><div class="row"><span class="spinner"></span><span class="muted" id="clean-now">Starting</span></div></div><div class="foot"></div>`;
  const stop = await listen("clean-progress", (e) => { const el = $("#clean-now"); if (el) el.textContent = e.payload; });
  let report;
  try { report = await invoke("clean", { req: { ids, confirmedYours: need("yours"), confirmedUnbacked: need("unbacked"), declined } }); }
  catch (e) { modalClose(); toast("Couldn't finish", String(e), true); return; }
  finally { stop?.(); }
  const done = new Set(report.results.filter((r) => ["deleted", "vaulted"].includes(r.status.kind)).map((r) => r.id));
  S.candidates = S.candidates.filter((c) => !done.has(c.id)); S.selection = new Set([...S.selection].filter((i) => !done.has(i))); S.plan = null;
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
const PALETTE = ["#F2542D", "#D4D4D8", "#7C93C3", "#C9962E", "#8A8A93"];
function worst(row, side) { const s = sum(row, (r) => r.a), mx = Math.max(...row.map((r) => r.a)), mn = Math.min(...row.map((r) => r.a)); return Math.max((side * side * mx) / (s * s), (s * s) / (side * side * mn)); }
function lay(row, r, out) {
  const s = sum(row, (x) => x.a);
  if (r.w >= r.h) { const w = s / r.h; let y = r.y; for (const it of row) { const h = it.a / w; out.push({ ...it, x: r.x, y, w, h }); y += h; } return { x: r.x + w, y: r.y, w: r.w - w, h: r.h }; }
  const h = s / r.w; let x = r.x; for (const it of row) { const w = it.a / h; out.push({ ...it, x, y: r.y, w, h }); x += w; } return { x: r.x, y: r.y + h, w: r.w, h: r.h - h };
}
function squarify(items) {
  const out = [], total = sum(items, (i) => i.bytes);
  let rest = items.filter((i) => i.bytes > 0).sort((a, b) => b.bytes - a.bytes).map((i) => ({ ...i, a: (i.bytes / total) * 10000 }));
  let row = [], rect = { x: 0, y: 0, w: 100, h: 100 };
  while (rest.length) {
    const side = Math.min(rect.w, rect.h), next = rest[0];
    if (!row.length || worst([...row, next], side) <= worst(row, side)) { row.push(next); rest.shift(); } else { rect = lay(row, rect, out); row = []; }
  }
  if (row.length) lay(row, rect, out);
  return out;
}

async function openDrives() { S.map.drives = await invoke("list_drives"); S.map.stack = []; S.map.nodes = []; }
async function descend(path, name) { S.map.stack.push({ path, name }); await loadMap(); }
async function loadMap() {
  S.map.loading = true; render();
  const top = S.map.stack.at(-1);
  S.map.nodes = top ? await invoke("map_children", { path: top.path }) : [];
  S.map.loading = false; render();
}

function viewMap() {
  const m = S.map, crumbs = [`<button data-act="map-root">All drives</button>`, ...m.stack.map((s, i) => `${icon("chevron-right", 14)}<button data-act="map-to" data-i="${i}">${esc(s.name)}</button>`)].join("");
  let body;
  if (!m.stack.length) {
    body = `<div class="grid g3">${m.drives.map((d) => { const used = Math.round(((d.total - d.free) / d.total) * 100); return `<button class="card tile" data-act="map-drive" data-path="${esc(d.path)}" data-name="${esc(d.name)}"><div class="row">${icon("hard-drive")}<h3 style="margin:0">${esc(d.name)}</h3></div><div class="v">${fmt(d.free)}</div><div class="muted" style="margin-bottom:10px">free of ${fmt(d.total)}</div><div class="gauge"><i style="width:${used}%"></i></div></button>`; }).join("")}</div>`;
  } else if (m.loading) body = `<div class="card row"><span class="spinner"></span><span class="muted">Measuring ${esc(m.stack.at(-1).name)}</span></div>`;
  else if (!m.nodes.length) body = `<div class="card empty">${icon("folder-open", 32)}<div>Nothing here.</div></div>`;
  else {
    const cells = squarify(m.nodes);
    body = `<div class="map">${cells.map((c, i) => `<div class="cell" style="left:${c.x}%;top:${c.y}%;width:${c.w}%;height:${c.h}%;background:${PALETTE[i % PALETTE.length]}" data-act="${c.isDir ? "map-open" : "reveal"}" data-path="${esc(c.path)}" data-name="${esc(c.name)}" title="${esc(c.name)}: ${fmt(c.bytes)}"><b>${esc(c.name)}</b><span>${fmt(c.bytes)}</span></div>`).join("")}</div>
      <p class="muted" style="margin-top:10px">Click a folder to look inside. Click a file to show it in Explorer. Sizes are what the files take on disk.</p>`;
  }
  return `<p class="eyebrow">Map</p><h1>Where your space went.</h1><p class="lede">Every folder, drawn by size. Nothing here changes anything.</p><div class="crumbs">${crumbs}</div>${body}`;
}

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
  const row = (title, body, control) => `<div class="row between" style="padding:14px 0;border-top:1px solid var(--stroke)"><div style="max-width:560px"><h3>${title}</h3><span class="muted">${body}</span></div>${control}</div>`;
  const mine = PERSONAS.filter((p) => s.workTypes.includes(p.id)).map((p) => p.title);
  return `<p class="eyebrow">Settings</p><h1>Make Room yours.</h1><p class="lede"></p>
    <div class="card" style="padding:6px 20px"><h2 style="margin:14px 0 0">Your work</h2>
      ${row("What you do most on this PC", mine.length ? esc(mine.join(", ")) : "Not set. Room checks for everyone's usual suspects.", `<button class="btn" data-act="redo-onboarding">Change</button>`)}
      <h2 style="margin:18px 0 0">Cleaning</h2>
      ${row("Keep rebuildable folders in the vault too", "Folders like node_modules wait 7 days in the undo vault instead of being removed right away. Caches are always removed directly.", `<input type="checkbox" class="switch" data-act="set-vault" ${s.vaultRebuildable ? "checked" : ""} aria-label="Keep rebuildable folders in the vault">`)}
      ${row("A project counts as stale after", "Only stale projects have their node_modules suggested.", `<select data-act="set-stale" aria-label="Stale after">${[30, 60, 90, 180].map((d) => `<option value="${d}" ${s.staleProjectDays === d ? "selected" : ""}>${d} days</option>`).join("")}</select>`)}
      <h2 style="margin:18px 0 0">Appearance</h2>
      ${row("Theme", "Room follows Windows by default.", `<div class="seg" role="group" aria-label="Theme">${["system", "light", "dark"].map((a) => `<button data-act="set-theme" data-v="${a}" aria-pressed="${s.appearance === a}">${a[0].toUpperCase() + a.slice(1)}</button>`).join("")}</div>`)}
      <h2 style="margin:18px 0 0">Privacy</h2>
      <div style="padding:14px 0;border-top:1px solid var(--stroke)" class="row">${icon("shield-check")}<span class="muted" style="max-width:640px">Room has no accounts and sends nothing anywhere. What it learns from your choices stays on this PC, in a file you can delete.</span></div>
    </div>`;
}

async function saveSettings(patch) {
  S.overview = await invoke("save_settings", { settings: { ...settings(), ...patch } });
  applyTheme();
}

// ---------- onboarding ----------
function openOnboarding(step = 0) {
  S.onboard = { step, picks: new Set(settings().workTypes) };
  drawOnboarding();
}
function drawOnboarding() {
  const { step, picks } = S.onboard;
  const steps = `<div class="steps"><i class="${step >= 0 ? "on" : ""}"></i><i class="${step >= 1 ? "on" : ""}"></i></div>`;
  if (step === 0) {
    modal(`<div class="body">${steps}<div style="width:44px;color:var(--text)">${MARK}</div><h2 style="font-size:28px;margin-top:12px">Welcome to Room</h2>
      <p class="muted" style="font-size:15px">Room finds what is safe to remove, shows you exactly what it will do, and only cleans after you say so.</p>
      <div class="stack" style="margin-top:14px">
        <div class="row" style="align-items:flex-start">${icon("list-checks")}<span>Every suggestion says what it is and how hard it is to get back.</span></div>
        <div class="row" style="align-items:flex-start">${icon("archive")}<span>Anything that might be yours waits 7 days in an undo vault.</span></div>
        <div class="row" style="align-items:flex-start">${icon("shield-check")}<span>No accounts. Nothing leaves this PC.</span></div></div></div>
      <div class="foot"><button class="btn subtle" data-act="onb-skip">Skip</button><button class="btn accent" data-act="onb-next">Continue</button></div>`, "wide");
  } else {
    modal(`<div class="body">${steps}<h2 style="font-size:26px">What do you do most on this PC?</h2>
      <p class="muted">Pick as many as you like. Room uses this to look in the right places. It never changes how careful Room is.</p>
      <div class="persona-grid">${PERSONAS.map((p) => `<button class="persona" data-act="persona" data-id="${p.id}" aria-pressed="${picks.has(p.id)}"><span class="ico">${icon(p.icon, 20)}</span><b>${esc(p.title)}</b><small>${esc(p.hint)}</small><span class="tick">${icon("check", 18)}</span></button>`).join("")}</div></div>
      <div class="foot"><button class="btn subtle" data-act="onb-skip">Skip</button><button class="btn accent" data-act="onb-done">${picks.size ? `Continue with ${picks.size}` : "Just everyday use"}</button></div>`, "wide");
  }
}
async function finishOnboarding(picks) {
  modalClose();
  await saveSettings({ workTypes: [...picks], onboarded: true });
  S.onboard = null;
  render(); startScan();
}

// ---------- modal ----------
function modal(html, size = "") {
  $("#modal-root").innerHTML = `<div class="smoke" data-act="smoke"><div class="dialog ${size}" role="dialog" aria-modal="true">${html}</div></div>`;
  $(".dialog button:not([disabled])")?.focus();
}
const modalClose = () => { $("#modal-root").innerHTML = ""; };

// ---------- scanning ----------
async function startScan() {
  if (S.scanning) return;
  S.scanning = true; S.scanLabel = ""; render();
  const stop = await listen("scan-progress", (e) => { S.scanLabel = e.payload; if (S.view === "overview") { const el = $(".card.row .muted"); if (el && S.scanning) el.textContent = `Measuring ${e.payload}`; } });
  try {
    S.candidates = await invoke("scan");
    S.selection = new Set(S.candidates.filter((c) => c.preselected && !c.heldBack).map((c) => c.id));
    S.plan = null; S.scannedOnce = true;
  } catch (e) { toast("The scan didn't finish", String(e), true); }
  finally { stop?.(); S.scanning = false; S.overview = await invoke("get_overview"); render(); }
}

// ---------- events ----------
document.addEventListener("click", async (e) => {
  const el = e.target.closest("[data-act]");
  if (!el) return;
  const a = el.dataset.act, d = el.dataset;
  if (a === "toggle") { e.stopPropagation(); el.checked ? S.selection.add(d.id) : S.selection.delete(d.id); render(); return; }
  if (a === "smoke") { if (e.target === el && !S.onboard) modalClose(); return; }
  switch (a) {
    case "go": return go(d.view);
    case "filter": S.filter = d.tier; return S.view === "overview" ? go("review") : render();
    case "goal": S.goalGB = +d.gb; S.plan = null; return render();
    case "plan": S.plan = await invoke("make_plan", { goalBytes: S.goalGB * 1e9 }); return render();
    case "review-plan": S.selection = new Set(S.plan.itemIds); S.filter = "all"; return go("review");
    case "rescan": return startScan();
    case "detail": S.detail = d.id; return render();
    case "close-detail": S.detail = null; return render();
    case "reveal": return invoke("reveal", { path: d.path });
    case "confirm": return openConfirm();
    case "modal-close": return modalClose();
    case "open-vault": modalClose(); return go("vault");
    case "map-root": S.map.stack = []; return go("map");
    case "map-drive": case "map-open": return descend(d.path, d.name);
    case "map-to": S.map.stack = S.map.stack.slice(0, +d.i + 1); return loadMap();
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
    case "set-theme": await saveSettings({ appearance: d.v }); return render();
    case "redo-onboarding": return openOnboarding(1);
    case "persona": S.onboard.picks.has(d.id) ? S.onboard.picks.delete(d.id) : S.onboard.picks.add(d.id); return drawOnboarding();
    case "onb-next": S.onboard.step = 1; return drawOnboarding();
    case "onb-skip": return finishOnboarding(new Set(settings().workTypes));
    case "onb-done": return finishOnboarding(S.onboard.picks);
  }
});
document.addEventListener("change", async (e) => {
  const el = e.target.closest("[data-act]");
  if (!el) return;
  if (el.dataset.act === "set-vault") { await saveSettings({ vaultRebuildable: el.checked }); render(); }
  if (el.dataset.act === "set-stale") { await saveSettings({ staleProjectDays: +el.value }); toast("Saved", "Scan again to apply."); }
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") { if (S.detail) { S.detail = null; render(); } else if (!S.onboard) modalClose(); }
  if ((e.key === "Enter" || e.key === " ") && e.target.matches?.(".item")) { e.preventDefault(); e.target.click(); }
});

// ---------- start ----------
S.overview = await invoke("get_overview");
applyTheme();
S.vault = await invoke("vault_list");
render();
if (!settings().onboarded) openOnboarding(0); else startScan();
