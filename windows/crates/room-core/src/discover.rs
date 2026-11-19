use crate::catalog::Catalog;
use crate::env::Env;
use crate::model::*;
use crate::{git, platform, safety, scan};
use rayon::prelude::*;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

#[derive(Clone, Debug)]
pub struct Options {
    pub env: Env,
    pub catalog: Catalog,
    pub project_roots: Vec<PathBuf>,
    pub stale_project_days: u32,
    pub min_bytes: u64,
    /// What the user said they do most ("dev", "video", ...). Empty means everyone's rules.
    pub work_types: Vec<String>,
    /// Tests turn this off so nothing depends on which programs happen to be running.
    pub check_running_apps: bool,
}

impl Options {
    pub fn new(env: Env) -> Options {
        Options { project_roots: env.default_project_roots(), env, catalog: Catalog::builtin(), stale_project_days: 60, min_bytes: 1_000_000, work_types: vec![], check_running_apps: true }
    }
}

fn short_id(prefix: &str, key: &str) -> String {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in key.bytes() { h ^= b as u64; h = h.wrapping_mul(0x100000001b3); }
    format!("{prefix}#{:08x}", (h >> 16) as u32)
}

#[allow(clippy::too_many_arguments)]
fn base(id: String, rule_id: &str, kind: Kind, title: String, why: String, tier: Tier, regen: Regen, action: Action, targets: Vec<PathBuf>, bytes: u64) -> Candidate {
    let display = targets.first().map(|p| p.to_string_lossy().to_string()).unwrap_or_default();
    Candidate { id, rule_id: rule_id.into(), kind, title, why, tier, regen, action, display_path: display, targets, bytes, age_days: 0,
                preselected: tier == Tier::Safe, git: GitStatus::NotRepo, note: None, held_back: None, min_age_minutes: None }
}

/// Finds everything Room could clean. Read-only.
pub fn discover(opts: &Options, progress: &(dyn Fn(&str) + Sync)) -> Vec<Candidate> {
    let mut out: Vec<Candidate> = opts.catalog.rules.par_iter().filter_map(|rule| {
        if !rule.personas.is_empty() && !opts.work_types.is_empty() && !rule.personas.iter().any(|p| opts.work_types.contains(p)) { return None; }
        progress(&rule.title);
        let (targets, bytes) = if rule.id == "system.recycle-bin" {
            (vec![], platform::recycle_bin_bytes())
        } else {
            let targets: Vec<PathBuf> = rule.paths.iter().flat_map(|p| opts.env.expand(p)).collect();
            let measured = targets.par_iter().map(|t| scan::measure(t).bytes).sum::<u64>();
            (targets, measured)
        };
        if bytes < opts.min_bytes { return None; }
        if let Action::Command(cmd) = rule.action {
            if let Some(tool) = cmd.required_tool() { if !platform::tool_exists(tool) { return None; } }
        }
        let mut c = base(short_id(&rule.id, &targets.iter().map(|t| t.to_string_lossy()).collect::<String>()), &rule.id, Kind::Rule,
                         rule.title.clone(), rule.why.clone(), rule.tier, rule.regen, rule.action, targets, bytes);
        c.min_age_minutes = rule.min_age_minutes;
        c.age_days = c.targets.first().map(|t| scan::age_days(t)).unwrap_or(0);
        if opts.check_running_apps {
            if let Some(app) = rule.guards.app_running.iter().find(|a| is_running(a)) {
                c.preselected = false;
                c.held_back = Some(format!("Close {} to include this.", app.trim_end_matches(".exe")));
            }
        }
        Some(c)
    }).collect();

    progress("Projects");
    out.extend(stale_node_modules(opts));
    progress("Downloads");
    out.extend(installers_and_zips(opts));
    progress("Large files");
    out.extend(large_old_files(opts));

    for c in out.iter_mut() { apply_cloud_caution(c); }
    out.sort_by_key(|c| std::cmp::Reverse(c.bytes));
    out
}

fn is_running(program: &str) -> bool { platform::is_process_running(program) }

/// Deleting inside a cloud-synced folder removes the file from every device, so such items are always the user's call.
fn apply_cloud_caution(c: &mut Candidate) {
    let Some(service) = c.targets.iter().find_map(|t| safety::in_cloud_folder(t)) else { return };
    c.tier = Tier::Yours;
    c.preselected = false;
    c.note = Some(format!("This is in {service}. Deleting it also removes it from {service} and your other devices."));
}

fn stale_node_modules(opts: &Options) -> Vec<Candidate> {
    let cutoff = Duration::from_secs(opts.stale_project_days as u64 * 86_400);
    let now = SystemTime::now();
    let stale = |p: &Path| scan::modified(p).and_then(|t| now.duration_since(t).ok()).map(|d| d >= cutoff).unwrap_or(false);
    let mut found: Vec<PathBuf> = vec![];
    for root in &opts.project_roots {
        find_dirs_named(root, "node_modules", 5, &mut found);
    }
    found.par_iter().filter_map(|nm| {
        let project = nm.parent()?;
        if !stale(project) || !stale(&project.join("package.json")) { return None; }
        let bytes = scan::measure(nm).bytes;
        if bytes < opts.min_bytes { return None; }
        let name = project.file_name()?.to_string_lossy().to_string();
        let mut c = base(short_id("detect.node_modules", &nm.to_string_lossy()), "detect.node_modules", Kind::NodeModules,
                         format!("node_modules: {name}"), format!("Packages for a project you haven't opened in {} days. Run an install to get them back.", opts.stale_project_days),
                         Tier::Rebuildable, Regen::Minutes, Action::DeleteItem, vec![nm.clone()], bytes);
        c.age_days = scan::age_days(project);
        c.git = git::status(project);
        Some(c)
    }).collect()
}

fn find_dirs_named(dir: &Path, name: &str, depth: usize, out: &mut Vec<PathBuf>) {
    if depth == 0 { return; }
    let Ok(entries) = fs::read_dir(dir) else { return };
    for e in entries.flatten() {
        let path = e.path();
        let Ok(meta) = fs::symlink_metadata(&path) else { continue };
        if !meta.is_dir() || platform::is_reparse_point(&meta) { continue; }
        let n = e.file_name().to_string_lossy().to_lowercase();
        if n == name { out.push(path); }                         // never look inside it
        else if !n.starts_with('.') && n != "target" && n != "bin" && n != "obj" { find_dirs_named(&path, name, depth - 1, out); }
    }
}

fn installers_and_zips(opts: &Options) -> Vec<Candidate> {
    let downloads = opts.env.home.join("Downloads");
    if !downloads.is_dir() { return vec![]; }
    type Files = Vec<(PathBuf, u64)>;
    let (mut installers, mut zips): (Files, Files) = (vec![], vec![]);
    scan::walk_files(&downloads, 2, &[], &mut |p, m| {
        let name = p.file_name().map(|n| n.to_string_lossy().to_lowercase()).unwrap_or_default();
        let ext = p.extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default();
        let size = platform::allocated_size(p, m);
        let old = scan::age_days(p) >= 14;
        let looks_like_installer = matches!(ext.as_str(), "msi" | "msix" | "appx" | "msixbundle") || (ext == "exe" && (name.contains("setup") || name.contains("install")));
        if old && looks_like_installer { installers.push((p.to_path_buf(), size)); }
        if ext == "zip" {
            let sibling = p.with_extension("");
            if sibling.is_dir() { zips.push((p.to_path_buf(), size)); }
        }
    });
    let mut out = vec![];
    let mk = |rule: &str, title: &str, why: &str, items: Vec<(PathBuf, u64)>| -> Option<Candidate> {
        let bytes: u64 = items.iter().map(|i| i.1).sum();
        if items.is_empty() || bytes < opts.min_bytes { return None; }
        let age = items.iter().map(|i| scan::age_days(&i.0)).min().unwrap_or(0);
        let mut c = base(short_id(rule, &downloads.to_string_lossy()), rule, if rule == "detect.installer" { Kind::Installer } else { Kind::Duplicate },
                         format!("{title} ({} files)", items.len()), why.into(), Tier::Rebuildable, Regen::Minutes, Action::DeleteItem,
                         items.into_iter().map(|i| i.0).collect(), bytes);
        c.age_days = age;
        c.display_path = downloads.to_string_lossy().to_string();
        Some(c)
    };
    out.extend(mk("detect.installer", "Old installers in Downloads", "Setup files you already ran. They wait in the undo vault for 7 days, and you can download them again.", installers));
    out.extend(mk("detect.zip-duplicate", "Zip files next to an unpacked copy", "Each of these has an unpacked folder beside it, so the zip is a duplicate. They wait in the undo vault for 7 days.", zips));
    out
}

fn large_old_files(opts: &Options) -> Vec<Candidate> {
    let mut found: Vec<(PathBuf, u64)> = vec![];
    let roots = ["Downloads", "Documents", "Desktop", "Videos", "Pictures"].map(|r| opts.env.home.join(r));
    for root in roots.iter().filter(|r| r.is_dir()) {
        scan::walk_files(root, 4, &[".git", "node_modules"], &mut |p, m| {
            let size = platform::allocated_size(p, m);
            if size >= 500_000_000 && scan::age_days(p) >= 60 { found.push((p.to_path_buf(), size)); }
        });
    }
    found.into_iter().map(|(p, bytes)| {
        let name = p.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
        let days = scan::age_days(&p);
        let mut c = base(short_id("detect.large-old", &p.to_string_lossy()), "detect.large-old", Kind::LargeFile, format!("Large and untouched: {name}"),
                         format!("Over 500 MB and unchanged for {days} days. Only you know if it matters."), Tier::Yours, Regen::Never, Action::DeleteItem, vec![p.clone()], bytes);
        c.age_days = days;
        c.git = git::status(&p);
        c
    }).collect()
}
