use crate::model::GitStatus;
use crate::platform;
use std::path::{Path, PathBuf};

/// Nearest enclosing git repository root, if any.
pub fn repo_root(path: &Path) -> Option<PathBuf> {
    let mut dir = if path.is_dir() { path } else { path.parent()? };
    loop {
        if dir.join(".git").exists() { return Some(dir.to_path_buf()); }
        dir = dir.parent()?;
    }
}

/// Is the work inside this path backed up? Never mutates anything.
pub fn status(path: &Path) -> GitStatus {
    let Some(root) = repo_root(path) else { return GitStatus::NotRepo };
    let r = root.to_string_lossy().to_string();
    let git = |args: &[&str]| -> Option<String> {
        let mut full = vec!["-C", r.as_str()];
        full.extend_from_slice(args);
        platform::run_quiet("git", &full).ok()
    };
    match git(&["status", "--porcelain"]) {
        None => return GitStatus::Dirty, // can't tell, so assume the worst
        Some(out) if !out.trim().is_empty() => return GitStatus::Dirty,
        _ => {}
    }
    if git(&["remote"]).map(|o| o.trim().is_empty()).unwrap_or(true) { return GitStatus::NoRemote; }
    match git(&["rev-list", "--count", "@{u}..HEAD"]) {
        Some(n) if n.trim() == "0" => GitStatus::Pushed,
        _ => GitStatus::Unpushed,
    }
}
