// A pretend backend so the interface can be previewed in a plain browser (no Tauri). Never used inside the app.
const GB = 1e9, MB = 1e6;
const cand = (id, rule, title, why, tier, regen, bytes, extra = {}) => ({ id, ruleId: rule, kind: "rule", title, why, tier, regen, action: { type: "deleteContents" }, targets: [], displayPath: extra.path || "", bytes, ageDays: extra.age ?? 0, preselected: tier === "safe", git: extra.git || "notRepo", note: extra.note || null, heldBack: extra.held || null, minAgeMinutes: null });
let candidates = [
  cand("a1", "cache.gradle", "Gradle caches", "Libraries Gradle downloaded for Android and Java builds. The next build downloads them again, which can take a while.", "rebuildable", "hours", 6.2 * GB, { path: "C:\\Users\\You\\.gradle\\caches", age: 12 }),
  cand("a2", "cache.chrome", "Chrome cache", "Page and asset caches. Sites load a little slower once. No logins or bookmarks are touched.", "safe", "instant", 1.4 * GB, { path: "C:\\Users\\You\\AppData\\Local\\Google\\Chrome\\User Data\\Default\\Cache", held: "Close chrome to include this." }),
  cand("a3", "cache.user-temp", "Temporary files", "Scratch files apps leave behind in your Temp folder. Files used in the last hour are kept.", "safe", "instant", 840 * MB, { path: "C:\\Users\\You\\AppData\\Local\\Temp" }),
  cand("a4", "cache.shaders", "Graphics shader cache", "Compiled graphics code for games and apps. Rebuilt the next time you run them.", "safe", "minutes", 510 * MB, { path: "C:\\Users\\You\\AppData\\Local\\D3DSCache" }),
  cand("a5", "detect.node_modules", "node_modules: web-app", "Packages for a project you haven't opened in 60 days. Run an install to get them back.", "rebuildable", "minutes", 1.1 * GB, { path: "C:\\Users\\You\\Projects\\web-app\\node_modules", age: 140, git: "pushed" }),
  cand("a6", "detect.installer", "Old installers in Downloads (6 files)", "Setup files you already ran. They wait in the undo vault for 7 days, and you can download them again.", "rebuildable", "minutes", 2.3 * GB, { path: "C:\\Users\\You\\Downloads", age: 45 }),
  cand("a7", "detect.large-old", "Large and untouched: holiday-2024-raw.mov", "Over 500 MB and unchanged for 310 days. Only you know if it matters.", "yours", "never", 3.8 * GB, { path: "C:\\Users\\You\\Videos\\holiday-2024-raw.mov", age: 310 }),
  cand("a8", "system.recycle-bin", "Recycle Bin", "Files you already deleted. Emptying it is permanent, so check it first.", "yours", "never", 420 * MB),
  cand("a9", "cache.onedrive-demo", "Design exports", "Large files in a synced folder.", "yours", "never", 700 * MB, { path: "C:\\Users\\You\\OneDrive\\Exports", note: "This is in OneDrive. Deleting it also removes it from OneDrive and your other devices." }),
];
let settings = { staleProjectDays: 60, vaultRebuildable: false, projectRoots: [], workTypes: [], onboarded: false, appearance: "system" };
let vault = [{ id: "v1", label: "Old installers in Downloads (6 files)", created: Date.now() / 1000 - 3600 * 30, expires: Date.now() / 1000 + 6 * 86400, entries: [{}, {}], totalBytes: 2.3 * GB, drives: [], available: true, usesRecycleBin: false },
  { id: "v2", label: "Large and untouched: render.mov", created: Date.now() / 1000 - 86400 * 2, expires: Date.now() / 1000 + 5 * 86400, entries: [{}], totalBytes: 5.1 * GB, drives: ["E:\\"], available: false, usesRecycleBin: false }];
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const overview = () => ({ free: 42.01 * GB, total: 494.33 * GB, drive: "C:", version: "1.2.0", settings, effect: "none", vaultBytes: vault.reduce((s, v) => s + v.totalBytes, 0), vaultBatches: vault.length });
const dir = (name, gb, kids = [], files = 0) => ({ name, path: name, bytes: gb * GB, kind: "dir", files: files || Math.round(gb * 800), children: kids });
const lump = (n, gb) => ({ name: `[${n} files]`, path: "", bytes: gb * GB, kind: "files", files: n, children: [] });
const file = (name, gb) => ({ name, path: name, bytes: gb * GB, kind: "file", files: 1, children: [] });
const sample = (path) => {
  const withPaths = (nodes, base) => nodes.map((n) => ({ ...n, path: n.kind === "dir" || n.kind === "file" ? base + "\\" + n.name : "", children: withPaths(n.children, base + "\\" + n.name) }));
  const kids = [
    dir("SteamLibrary", 152, [dir("steamapps", 150, [dir("common", 148), lump(40, 2)]), lump(12, 2)]),
    dir("Games", 148, [dir("Elden Ring", 121), dir("Hades II", 14), dir("Celeste", 4), lump(220, 9)]),
    dir("Anime", 42.4, [dir("Blue Box", 21.2), dir("Fire Force S2", 9.9), dir("Frieren", 6), lump(30, 5.3)]),
    dir("Riot Games", 36.8, [dir("VALORANT", 32.7), dir("League of Legends", 3), lump(9, 1.1)]),
    dir("Movies", 33.9, [dir("Obsession 2025 UHD", 20), dir("The Wolf of Wall Street", 9), file("trailer.mkv", 1.4), lump(8, 3.5)]),
    dir("Personal-Proj", 21.4, [dir("FakeNews", 17.5), dir("web-app", 2.2), dir("notes", 0.9), lump(60, 0.8)]),
    dir("wsl", 6.9, [dir("kali", 6.5), lump(3, 0.4)]), dir("EpicGames", 6.2), dir("SIH", 4.4), dir("flutter", 2.1), dir("colab", 1.2), dir("tmp", 0.4), dir("keys", 0.05),
    file("pagefile.sys", 3.2), file("hiberfil.sys", 2.4), { name: "14 smaller files", path: "", bytes: 0.6 * GB, kind: "files", files: 14, children: [] },
  ];
  const k = withPaths(kids, path.replace(/\\+$/, ""));
  return { name: path.split(/[\\/]/).filter(Boolean).pop() || path, path, bytes: k.reduce((s, c) => s + c.bytes, 0), kind: "dir", files: k.reduce((s, c) => s + c.files, 0), children: k };
};
const handlers = {
  get_overview: () => overview(),
  save_settings: ({ settings: s }) => { settings = s; return overview(); },
  scan: async () => { for (const t of ["Temporary files", "Browser caches", "Projects", "Downloads"]) { window.__mockEmit?.("scan-progress", t); await wait(350); } return candidates; },
  make_plan: ({ goalBytes }) => { let t = 0; const ids = []; for (const c of [...candidates].filter((c) => c.tier !== "yours" && !c.heldBack).sort((a, b) => b.bytes - a.bytes)) { if (t >= goalBytes) break; ids.push(c.id); t += c.bytes; } return { itemIds: ids, goalBytes, guaranteedBytes: t, reachesGoal: t >= goalBytes, shortfall: Math.max(0, goalBytes - t), totalRegret: 0.3 }; },
  preview_clean: ({ ids }) => { const v = candidates.filter((c) => ids.includes(c.id) && (c.tier === "yours" || ["detect.installer", "detect.zip-duplicate"].includes(c.ruleId))); const d = candidates.filter((c) => ids.includes(c.id) && !v.includes(c)); return { directIds: d.map((c) => c.id), vaultIds: v.map((c) => c.id), directBytes: d.reduce((s, c) => s + c.bytes, 0), vaultBytes: v.reduce((s, c) => s + c.bytes, 0) }; },
  clean: async ({ req }) => { await wait(900); const res = candidates.filter((c) => req.ids.includes(c.id)).map((c) => ({ id: c.id, title: c.title, bytes: c.bytes, status: c.tier === "yours" || c.ruleId === "detect.installer" ? { kind: "vaulted", detail: 7 } : { kind: "deleted" } })); candidates = candidates.filter((c) => !req.ids.includes(c.id)); return { results: res, freeBefore: 42 * GB, freeAfter: 46.5 * GB, measuredFreed: 4.5 * GB, vaultedBytes: 0 }; },
  vault_list: () => vault, vault_restore: ({ id }) => { vault = vault.filter((v) => v.id !== id); return 1; }, vault_purge: ({ id }) => { const v = vault.find((x) => x.id === id); if (v && !v.available) return false; vault = vault.filter((x) => x.id !== id); return true; }, vault_empty: () => { vault = vault.filter((v) => !v.available); return 1; },
  map_tree: async ({ path }) => { await wait(700); return sample(path); }, map_cancel: () => {}, known_places: () => [{ name: "Home", path: "C:\\Users\\You" }, { name: "Downloads", path: "C:\\Users\\You\\Downloads" }, { name: "Projects", path: "C:\\Users\\You\\Projects" }], set_window_theme: () => "none", list_drives: () => [{ name: "C:", path: "C:\\", free: 42 * GB, total: 494 * GB }, { name: "E:", path: "E:\\", free: 800 * GB, total: 2000 * GB }], home_dir: () => "C:\\Users\\You", reveal: () => {},
};
const listeners = {};
window.__mockEmit = (name, payload) => (listeners[name] || []).forEach((f) => f({ payload }));
window.__TAURI__ = { dialog: { open: async () => "D:\\Games" }, core: { invoke: async (cmd, args) => { await wait(60); return handlers[cmd](args || {}); } }, event: { listen: async (name, f) => { (listeners[name] ||= []).push(f); return () => {}; } } };
