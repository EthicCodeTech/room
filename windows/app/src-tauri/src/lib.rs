//! Room for Windows: the Tauri shell around `room-core`. Every command is a thin wrapper; the rules live in the engine.
use room_core::catalog::Catalog;
use room_core::cleaner::{Cleaner, Confirmations, Report};
use room_core::decision::DecisionLog;
use room_core::discover::{discover, Options};
use room_core::env::Env;
use room_core::map::{self, Drive, MapNode};
use room_core::model::{Candidate, DeletionPolicy, Tier};
use room_core::planner::{self, Plan};
use room_core::scorer::{restore_rates, Scorer};
use room_core::settings::Settings;
use room_core::vault::{Manifest, Vault};
use room_core::{platform, APP_VERSION};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use tauri::{AppHandle, Emitter, Manager, State};

struct Paths { root: PathBuf }
impl Paths {
    fn vault(&self) -> PathBuf { self.root.join("Vault") }
    fn settings(&self) -> PathBuf { self.root.join("settings.json") }
    fn decisions(&self) -> PathBuf { self.root.join("decisions.jsonl") }
    fn model(&self) -> PathBuf { self.root.join("scorer-weights.json") }
}

struct AppState {
    env: Env,
    paths: Paths,
    candidates: Mutex<Vec<Candidate>>,
    scorer: Mutex<Scorer>,
    busy: Mutex<bool>,
    effect: Mutex<&'static str>,
}

fn now() -> i64 { std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0) }
fn known_rules() -> HashSet<String> { Catalog::builtin().rules.into_iter().map(|r| r.id).collect() }

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Overview { free: u64, total: u64, drive: String, version: &'static str, settings: Settings, effect: String, vault_bytes: u64, vault_batches: usize }

fn overview(s: &AppState) -> Overview {
    let (free, total) = platform::disk_space(&s.env.home);
    let vault = Vault::new(s.paths.vault());
    Overview {
        free, total, drive: s.env.system_drive.clone(), version: APP_VERSION, settings: Settings::load(&s.paths.settings()),
        effect: s.effect.lock().map(|e| e.to_string()).unwrap_or_default(), vault_bytes: vault.total_bytes(), vault_batches: vault.list().len(),
    }
}

#[tauri::command]
fn get_overview(state: State<AppState>) -> Overview { overview(&state) }

#[tauri::command]
fn save_settings(state: State<AppState>, settings: Settings) -> Overview {
    settings.save(&state.paths.settings());
    overview(&state)
}

/// Finds everything Room could clean (read-only) and returns it. Progress arrives as `scan-progress` events.
#[tauri::command]
async fn scan(app: AppHandle) -> Result<Vec<Candidate>, String> {
    {
        let state = app.state::<AppState>();
        let mut busy = state.busy.lock().map_err(|e| e.to_string())?;
        if *busy { return Err("A scan is already running.".into()); }
        *busy = true;
    }
    let handle = app.clone();
    let result = tauri::async_runtime::spawn_blocking(move || {
        let state = handle.state::<AppState>();
        let settings = Settings::load(&state.paths.settings());
        let mut opts = Options::new(state.env.clone());
        opts.stale_project_days = settings.stale_project_days;
        opts.work_types = settings.work_types.clone();
        for extra in &settings.project_roots { if extra.is_dir() && !opts.project_roots.contains(extra) { opts.project_roots.push(extra.clone()); } }
        let emitter = handle.clone();
        let found = discover(&opts, &move |name| { let _ = emitter.emit("scan-progress", name.to_string()); });
        if let Ok(mut c) = state.candidates.lock() { *c = found.clone(); }
        found
    }).await.map_err(|e| e.to_string());
    if let Ok(mut busy) = app.state::<AppState>().busy.lock() { *busy = false; }
    result
}

#[tauri::command]
fn make_plan(state: State<AppState>, goal_bytes: u64) -> Plan {
    let cands = state.candidates.lock().map(|c| c.clone()).unwrap_or_default();
    let rates = restore_rates(&DecisionLog::new(state.paths.decisions()).load());
    let scorer = state.scorer.lock().expect("scorer lock");
    planner::plan(&scorer, &rates, goal_bytes, &cands, &[Tier::Safe, Tier::Rebuildable])
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct CleanRequest { ids: Vec<String>, confirmed_yours: Vec<String>, confirmed_unbacked: Vec<String>, declined: Vec<String> }

/// Splits what will happen to each item, so the confirmation can say it before anything runs.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Preview { direct_ids: Vec<String>, vault_ids: Vec<String>, direct_bytes: u64, vault_bytes: u64 }

#[tauri::command]
fn preview_clean(state: State<AppState>, ids: Vec<String>) -> Preview {
    let settings = Settings::load(&state.paths.settings());
    let cands = state.candidates.lock().map(|c| c.clone()).unwrap_or_default();
    let mut p = Preview { direct_ids: vec![], vault_ids: vec![], direct_bytes: 0, vault_bytes: 0 };
    for c in cands.iter().filter(|c| ids.contains(&c.id)) {
        match DeletionPolicy::default_for(c, settings.vault_rebuildable) {
            DeletionPolicy::Immediate => { p.direct_ids.push(c.id.clone()); p.direct_bytes += c.bytes; }
            DeletionPolicy::Vault { .. } => { p.vault_ids.push(c.id.clone()); p.vault_bytes += c.bytes; }
        }
    }
    p
}

#[tauri::command]
async fn clean(app: AppHandle, req: CleanRequest) -> Result<Report, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let state = app.state::<AppState>();
        let settings = Settings::load(&state.paths.settings());
        let all = state.candidates.lock().map(|c| c.clone()).unwrap_or_default();
        let items: Vec<Candidate> = req.ids.iter().filter_map(|id| all.iter().find(|c| &c.id == id).cloned()).collect();
        let conf = Confirmations {
            yours: req.confirmed_yours.into_iter().collect(),
            unbacked_repo: req.confirmed_unbacked.into_iter().collect(),
            declined: req.declined.iter().filter_map(|id| all.iter().find(|c| &c.id == id).cloned()).collect(),
        };
        let vault = Vault::new(state.paths.vault());
        let log = DecisionLog::new(state.paths.decisions());
        let rules = known_rules();
        let cleaner = Cleaner { vault: &vault, log: Some(&log), env: &state.env, known_rules: &rules };
        let emitter = app.clone();
        let report = cleaner.execute(&items, &conf, &|c| DeletionPolicy::default_for(c, settings.vault_rebuildable), now(),
                                     &move |t| { let _ = emitter.emit("clean-progress", t.to_string()); });
        if let Ok(mut s) = state.scorer.lock() { s.retrain(&log.load()); persist_model(&state.paths, &s); }
        // Cleaned items are gone, so drop them from the list the UI holds.
        let done: HashSet<&str> = report.results.iter().filter(|r| matches!(r.status, room_core::cleaner::Status::Deleted | room_core::cleaner::Status::Vaulted(_))).map(|r| r.id.as_str()).collect();
        if let Ok(mut c) = state.candidates.lock() { c.retain(|x| !done.contains(x.id.as_str())); }
        report
    }).await.map_err(|e| e.to_string())
}

fn persist_model(paths: &Paths, scorer: &Scorer) {
    let _ = std::fs::create_dir_all(&paths.root);
    if let Ok(t) = serde_json::to_string(&scorer.model) { let _ = std::fs::write(paths.model(), t); }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct VaultBatch { #[serde(flatten)] manifest: Manifest, total_bytes: u64, drives: Vec<String>, available: bool, uses_recycle_bin: bool }

#[tauri::command]
fn vault_list(state: State<AppState>) -> Vec<VaultBatch> {
    let vault = Vault::new(state.paths.vault());
    vault.list().into_iter().map(|m| VaultBatch {
        total_bytes: m.total_bytes(), drives: m.drive_names(), available: vault.is_available(&m), uses_recycle_bin: m.uses_recycle_bin(), manifest: m,
    }).collect()
}

#[tauri::command]
fn vault_restore(state: State<AppState>, id: String) -> Result<usize, String> {
    let vault = Vault::new(state.paths.vault());
    let log = DecisionLog::new(state.paths.decisions());
    let rules = known_rules();
    let cleaner = Cleaner { vault: &vault, log: Some(&log), env: &state.env, known_rules: &rules };
    let restored = cleaner.restore(&id, now()).map_err(|e| e.to_string())?;
    if let Ok(mut s) = state.scorer.lock() { s.retrain(&log.load()); persist_model(&state.paths, &s); }
    Ok(restored.len())
}

/// Returns false when part of the batch is on a drive that isn't connected.
#[tauri::command]
fn vault_purge(state: State<AppState>, id: String) -> bool { Vault::new(state.paths.vault()).purge(&id) }

#[tauri::command]
fn vault_empty(state: State<AppState>) -> usize {
    let vault = Vault::new(state.paths.vault());
    vault.list().iter().filter(|m| vault.purge(&m.id)).count()
}

#[tauri::command]
async fn map_children(path: String) -> Result<Vec<MapNode>, String> {
    tauri::async_runtime::spawn_blocking(move || map::children(Path::new(&path), 60)).await.map_err(|e| e.to_string())
}

#[tauri::command]
fn list_drives() -> Vec<Drive> { map::drives() }

#[tauri::command]
fn home_dir(state: State<AppState>) -> String { state.env.home.to_string_lossy().to_string() }

/// Shows a file in Explorer. Only paths that exist are opened.
#[tauri::command]
fn reveal(path: String) {
    let p = Path::new(&path);
    if !p.exists() { return; }
    #[cfg(windows)]
    { use std::os::windows::process::CommandExt; let _ = std::process::Command::new("explorer").arg(format!("/select,{}", p.display())).creation_flags(0x0800_0000).spawn(); }
    #[cfg(target_os = "macos")]
    { let _ = std::process::Command::new("open").arg("-R").arg(p).spawn(); }
}

pub fn run() {
    let env = Env::detect();
    let root = dirs::data_local_dir().unwrap_or_else(|| env.home.clone()).join("Room");
    let paths = Paths { root };
    let _ = std::fs::create_dir_all(&paths.root);

    let mut scorer = Scorer::new(std::fs::read_to_string(paths.model()).ok().and_then(|t| serde_json::from_str(&t).ok()));
    let history = DecisionLog::new(paths.decisions()).load();
    if !history.is_empty() { scorer.retrain(&history); }
    Vault::new(paths.vault()).purge_expired(now());

    tauri::Builder::default()
        .manage(AppState { env, paths, candidates: Mutex::new(vec![]), scorer: Mutex::new(scorer), busy: Mutex::new(false), effect: Mutex::new("none") })
        .setup(|app| {
            let state = app.state::<AppState>();
            #[cfg(windows)]
            if let Some(window) = app.get_webview_window("main") {
                use window_vibrancy::{apply_acrylic, apply_mica};
                // Windows 11 gets Mica, like Settings and Explorer. Windows 10 gets a light acrylic. Anything else stays solid.
                let effect = if apply_mica(&window, None).is_ok() { "mica" } else if apply_acrylic(&window, Some((18, 18, 20, 160))).is_ok() { "acrylic" } else { "none" };
                if let Ok(mut e) = state.effect.lock() { *e = effect; }
            }
            #[cfg(not(windows))]
            let _ = (&state, app.get_webview_window("main"));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_overview, save_settings, scan, make_plan, preview_clean, clean, vault_list, vault_restore, vault_purge, vault_empty,
            map_children, list_drives, home_dir, reveal
        ])
        .run(tauri::generate_context!())
        .expect("Room could not start");
}
