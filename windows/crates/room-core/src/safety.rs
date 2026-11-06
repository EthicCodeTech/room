//! Path safety. Works on normalized strings (lowercase, forward slashes) so the Windows rules can be tested anywhere.
use crate::env::Env;
use std::path::Path;

pub fn normalize(path: &str) -> String {
    let mut p = path.replace('\\', "/");
    for prefix in ["//?/unc/", "//?/"] { if let Some(rest) = p.strip_prefix(prefix) { p = rest.to_string(); break; } }
    while p.len() > 3 && p.ends_with('/') { p.pop(); }
    p.to_lowercase()
}

fn drive_of(p: &str) -> Option<&str> {
    let b = p.as_bytes();
    if b.len() >= 2 && b[0].is_ascii_alphabetic() && b[1] == b':' { Some(&p[..2]) } else { None }
}

/// Folders that are never deletable as a whole, even though they sit inside the user's profile.
fn protected(env: &Env) -> Vec<String> {
    let home = normalize(&env.home.to_string_lossy());
    let mut v = vec![home.clone()];
    for sub in ["desktop", "documents", "downloads", "pictures", "music", "videos", "onedrive", "appdata", "appdata/local", "appdata/roaming",
                "appdata/local/programs", "appdata/locallow", ".ssh", ".config", ".gnupg"] {
        v.push(format!("{home}/{sub}"));
    }
    v.push(normalize(&env.local_app_data.to_string_lossy()));
    v.push(normalize(&env.app_data.to_string_lossy()));
    v
}

const SYSTEM_NAMES: [&str; 6] = ["$recycle.bin", "system volume information", "windows", "program files", "program files (x86)", "programdata"];

/// True when Room may remove this path. Allowed: inside the user profile (never the profile's own folders), or at
/// least two levels deep on a drive other than the system drive.
pub fn is_deletable(path: &str, env: &Env) -> bool {
    let p = normalize(path);
    if p.is_empty() || p == "/" || p.contains("/../") || p.ends_with("/..") { return false; }
    if protected(env).contains(&p) { return false; }
    let home = normalize(&env.home.to_string_lossy());
    if p.starts_with(&format!("{home}/")) { return true; }
    let system = env.system_drive.to_lowercase();
    if let Some(drive) = drive_of(&p) {
        if drive == system { return false; }
        let rest: Vec<&str> = p[2..].split('/').filter(|s| !s.is_empty()).collect();
        if rest.len() < 2 { return false; }
        return !rest.iter().any(|s| SYSTEM_NAMES.contains(s));
    }
    // Unix-style absolute path (macOS/Linux dev builds): external volumes only.
    p.starts_with("/volumes/") && p.split('/').filter(|s| !s.is_empty()).count() >= 3
}

/// Cloud-synced folders. Deleting inside them also deletes the file everywhere.
pub fn in_cloud_folder(path: &Path) -> Option<&'static str> {
    for comp in path.components() {
        let c = comp.as_os_str().to_string_lossy().to_lowercase();
        if c.starts_with("onedrive") { return Some("OneDrive"); }
        if c == "dropbox" { return Some("Dropbox"); }
        if c == "google drive" || c == "my drive" { return Some("Google Drive"); }
        if c == "iclouddrive" || c == "icloud drive" { return Some("iCloud Drive"); }
    }
    None
}
