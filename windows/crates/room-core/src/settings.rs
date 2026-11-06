use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

/// Stored as JSON. Every field has a default so older files keep working after an update.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Settings {
    pub stale_project_days: u32,
    /// Also keep node_modules and other rebuildable folders in the undo vault (caches are always removed directly).
    pub vault_rebuildable: bool,
    pub project_roots: Vec<PathBuf>,
    /// What the user said they do most on this PC. Empty until they choose.
    pub work_types: Vec<String>,
    pub onboarded: bool,
    pub appearance: String,
}

impl Default for Settings {
    fn default() -> Settings {
        Settings { stale_project_days: 60, vault_rebuildable: false, project_roots: vec![], work_types: vec![], onboarded: false, appearance: "system".into() }
    }
}

impl Settings {
    pub fn load(path: &Path) -> Settings { std::fs::read_to_string(path).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default() }
    pub fn save(&self, path: &Path) {
        if let Some(dir) = path.parent() { let _ = std::fs::create_dir_all(dir); }
        if let Ok(t) = serde_json::to_string_pretty(self) { let _ = std::fs::write(path, t); }
    }
}
