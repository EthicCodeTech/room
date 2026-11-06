//! The undo vault. "Delete" for anything that might be someone's work moves it here first.
//! A same-drive move is an instant rename, so nothing is copied. Items on another drive stay on that drive, in a
//! hidden `.room-vault` folder at its root. Only a drive that can't hold one falls back to the Recycle Bin.
use crate::platform;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;

pub const DRIVE_FOLDER: &str = ".room-vault";

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Entry {
    pub original_path: String,
    pub stored_path: String,
    pub bytes: u64,
    pub title: String,
    pub rule_id: String,
    /// Drive holding this item, when it isn't the main vault's drive.
    #[serde(default)]
    pub volume: Option<String>,
    /// True when the drive couldn't hold a vault and the item went to the Recycle Bin instead.
    #[serde(default)]
    pub via_trash: Option<bool>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Manifest {
    pub id: String,
    pub label: String,
    pub created: i64,
    pub expires: i64,
    pub entries: Vec<Entry>,
}

impl Manifest {
    pub fn total_bytes(&self) -> u64 { self.entries.iter().map(|e| e.bytes).sum() }
    pub fn drive_names(&self) -> Vec<String> {
        let mut seen: Vec<String> = vec![];
        for v in self.entries.iter().filter_map(|e| e.volume.clone()) { if !seen.contains(&v) { seen.push(v); } }
        seen
    }
    pub fn uses_recycle_bin(&self) -> bool { self.entries.iter().any(|e| e.via_trash == Some(true)) }
}

#[derive(Debug, PartialEq)]
pub enum VaultError {
    NotFound,
    Gone,
    /// Part of the batch is on a drive that isn't connected.
    Partial { restored: usize, drives: Vec<String> },
    Other(String),
}

impl std::fmt::Display for VaultError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            VaultError::NotFound => write!(f, "That vault batch no longer exists."),
            VaultError::Gone => write!(f, "These files were already removed from the vault."),
            VaultError::Partial { restored, drives } => {
                let list = drives.join(", ");
                if *restored == 0 { write!(f, "Connect {list} to restore this.") } else { write!(f, "Restored {restored}. Connect {list} to put back the rest.") }
            }
            VaultError::Other(e) => write!(f, "{e}"),
        }
    }
}

/// How the vault asks about drives. A trait so tests can stand in for a second drive.
pub trait Volumes: Send + Sync {
    fn volume_root(&self, p: &Path) -> Option<PathBuf>;
    fn same_volume(&self, a: &Path, b: &Path) -> bool;
    fn to_recycle_bin(&self, p: &Path) -> Result<(), String>;
}

pub struct SystemVolumes;
impl Volumes for SystemVolumes {
    fn volume_root(&self, p: &Path) -> Option<PathBuf> { platform::volume_root(p) }
    fn same_volume(&self, a: &Path, b: &Path) -> bool { platform::same_volume(a, b) }
    fn to_recycle_bin(&self, p: &Path) -> Result<(), String> { trash::delete(p).map_err(|e| e.to_string()) }
}

pub struct StashItem { pub path: PathBuf, pub bytes: u64, pub title: String, pub rule_id: String }

pub struct Vault { dir: PathBuf, volumes: Arc<dyn Volumes> }

impl Vault {
    pub fn new(dir: PathBuf) -> Vault { Vault { dir, volumes: Arc::new(SystemVolumes) } }
    pub fn with_volumes(dir: PathBuf, volumes: Arc<dyn Volumes>) -> Vault { Vault { dir, volumes } }

    fn batch_dir(&self, id: &str) -> PathBuf { self.dir.join(id) }
    fn manifest_path(&self, id: &str) -> PathBuf { self.batch_dir(id).join("manifest.json") }

    fn write(&self, m: &Manifest) -> Result<(), VaultError> {
        fs::create_dir_all(self.batch_dir(&m.id)).map_err(|e| VaultError::Other(e.to_string()))?;
        let tmp = self.batch_dir(&m.id).join("manifest.json.tmp");
        fs::write(&tmp, serde_json::to_string_pretty(m).unwrap_or_default()).map_err(|e| VaultError::Other(e.to_string()))?;
        fs::rename(&tmp, self.manifest_path(&m.id)).map_err(|e| VaultError::Other(e.to_string()))
    }

    fn manifest(&self, id: &str) -> Option<Manifest> {
        fs::read_to_string(self.manifest_path(id)).ok().and_then(|t| serde_json::from_str(&t).ok())
    }

    /// Moves items into the vault. Returns the manifest plus any items that couldn't be moved.
    pub fn stash(&self, items: &[StashItem], label: &str, days: u32, now: i64) -> Result<(Manifest, Vec<(PathBuf, String)>), VaultError> {
        let id = uuid::Uuid::new_v4().to_string();
        fs::create_dir_all(self.batch_dir(&id)).map_err(|e| VaultError::Other(e.to_string()))?;
        let mut entries = vec![];
        let mut failures = vec![];
        for (index, item) in items.iter().enumerate() {
            let name = format!("{index}-{}", item.path.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default());
            let entry = |stored: String, volume: Option<String>, via_trash: Option<bool>| Entry {
                original_path: item.path.to_string_lossy().to_string(), stored_path: stored, bytes: item.bytes, title: item.title.clone(),
                rule_id: item.rule_id.clone(), volume, via_trash,
            };
            if self.volumes.same_volume(&item.path, &self.dir) {
                let dest = self.batch_dir(&id).join(&name);
                match fs::rename(&item.path, &dest) {
                    Ok(()) => entries.push(entry(dest.to_string_lossy().to_string(), None, None)),
                    Err(e) => failures.push((item.path.clone(), e.to_string())),
                }
            } else if let Some(root) = self.volumes.volume_root(&item.path).filter(|r| r != &PathBuf::from("/")) {
                match self.move_into_drive_vault(&item.path, &root, &id, &name) {
                    Ok(dest) => entries.push(entry(dest.to_string_lossy().to_string(), Some(root.to_string_lossy().to_string()), None)),
                    Err(_) => match self.volumes.to_recycle_bin(&item.path) {
                        Ok(()) => entries.push(entry(String::new(), None, Some(true))),
                        Err(e) => failures.push((item.path.clone(), e)),
                    },
                }
            } else {
                match self.volumes.to_recycle_bin(&item.path) {
                    Ok(()) => entries.push(entry(String::new(), None, Some(true))),
                    Err(e) => failures.push((item.path.clone(), e)),
                }
            }
        }
        let manifest = Manifest { id, label: label.into(), created: now, expires: now + days as i64 * 86_400, entries };
        self.write(&manifest)?;
        Ok((manifest, failures))
    }

    pub fn list(&self) -> Vec<Manifest> {
        let mut out: Vec<Manifest> = fs::read_dir(&self.dir).map(|rd| rd.flatten().filter_map(|e| self.manifest(&e.file_name().to_string_lossy())).collect()).unwrap_or_default();
        out.sort_by_key(|m| std::cmp::Reverse(m.created));
        out
    }

    pub fn total_bytes(&self) -> u64 { self.list().iter().map(|m| m.total_bytes()).sum() }

    /// True when every drive holding part of this batch is connected.
    pub fn is_available(&self, m: &Manifest) -> bool { m.entries.iter().all(|e| e.volume.as_deref().map(is_online).unwrap_or(true)) }

    /// Puts everything back where it came from. If the spot is taken, restores beside it as "name (restored)".
    /// Items on a drive that isn't plugged in stay in the vault until it is; the rest are restored now.
    pub fn restore(&self, id: &str) -> Result<Vec<PathBuf>, VaultError> {
        let manifest = self.manifest(id).ok_or(VaultError::NotFound)?;
        let (mut restored, mut remaining, mut waiting) = (vec![], vec![], vec![]);
        let mut first_error: Option<String> = None;
        for e in &manifest.entries {
            if let Some(v) = &e.volume {
                if !is_online(v) {
                    remaining.push(e.clone());
                    let name = Path::new(v).file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_else(|| v.clone());
                    if !waiting.contains(&name) { waiting.push(name); }
                    continue;
                }
            }
            if e.via_trash == Some(true) || !Path::new(&e.stored_path).exists() { continue; }          // nothing left to put back
            let mut target = PathBuf::from(&e.original_path);
            let step = (|| -> std::io::Result<PathBuf> {
                if let Some(parent) = target.parent() { fs::create_dir_all(parent)?; }
                if target.exists() {
                    let stem = target.file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_default();
                    let name = match target.extension() { Some(x) => format!("{stem} (restored).{}", x.to_string_lossy()), None => format!("{stem} (restored)") };
                    target = target.with_file_name(name);
                }
                fs::rename(&e.stored_path, &target)?;
                Ok(target.clone())
            })();
            match step { Ok(p) => restored.push(p), Err(err) => { remaining.push(e.clone()); first_error.get_or_insert(err.to_string()); } }
        }
        if remaining.is_empty() {
            let _ = fs::remove_dir_all(self.batch_dir(id));
            self.remove_drive_batches(id, manifest.entries.iter().filter_map(|e| e.volume.clone()).collect());
            if restored.is_empty() && !manifest.entries.is_empty() && manifest.entries.iter().all(|e| e.via_trash != Some(true)) { return Err(VaultError::Gone); }
            Ok(restored)
        } else {
            let mut rest = manifest.clone();
            rest.entries = remaining;
            self.write(&rest)?;
            match (waiting.is_empty(), first_error) {
                (true, Some(e)) => Err(VaultError::Other(e)),
                _ => Err(VaultError::Partial { restored: restored.len(), drives: waiting }),
            }
        }
    }

    /// Permanently deletes a batch. Returns false when part of it sits on a drive that isn't connected: that part is
    /// kept until the drive is back.
    pub fn purge(&self, id: &str) -> bool {
        let Some(m) = self.manifest(id) else { let _ = fs::remove_dir_all(self.batch_dir(id)); return true };
        let mut waiting = vec![];
        for e in &m.entries {
            if let Some(v) = &e.volume { if !is_online(v) { waiting.push(e.clone()); continue; } }
            if !e.stored_path.is_empty() { remove_any(Path::new(&e.stored_path)); }
        }
        self.remove_drive_batches(id, m.entries.iter().filter_map(|e| e.volume.clone()).filter(|v| is_online(v)).collect());
        if waiting.is_empty() { let _ = fs::remove_dir_all(self.batch_dir(id)); return true; }
        let mut rest = m.clone();
        rest.entries = waiting;
        let _ = self.write(&rest);
        false
    }

    pub fn purge_expired(&self, now: i64) -> usize {
        self.list().into_iter().filter(|m| m.expires <= now).filter(|m| self.purge(&m.id)).count()
    }

    fn move_into_drive_vault(&self, path: &Path, root: &Path, id: &str, name: &str) -> std::io::Result<PathBuf> {
        let folder = root.join(DRIVE_FOLDER);
        let dir = folder.join(id);
        fs::create_dir_all(&dir)?;
        platform::hide_folder(&folder);
        let dest = dir.join(name);
        if let Err(e) = fs::rename(path, &dest) {
            if fs::read_dir(&dir).map(|mut d| d.next().is_none()).unwrap_or(false) { self.remove_drive_batches(id, vec![root.to_string_lossy().to_string()]); }
            return Err(e);
        }
        Ok(dest)
    }

    /// Removes this batch's folder on each drive, and the drive's `.room-vault` once nothing is left in it.
    fn remove_drive_batches(&self, id: &str, volumes: Vec<String>) {
        let mut seen: Vec<String> = vec![];
        for v in volumes {
            if seen.contains(&v) { continue; }
            seen.push(v.clone());
            let folder = Path::new(&v).join(DRIVE_FOLDER);
            let _ = fs::remove_dir_all(folder.join(id));
            let left = fs::read_dir(&folder).map(|rd| rd.flatten().filter(|e| e.file_name() != "desktop.ini").count()).unwrap_or(0);
            if left == 0 { let _ = fs::remove_dir_all(&folder); }
        }
    }
}

/// A drive counts as connected when its vault folder is readable at the mount point we recorded.
fn is_online(volume: &str) -> bool { Path::new(volume).join(DRIVE_FOLDER).exists() }

/// Removes a file or folder, clearing the read-only flag first because Windows refuses to delete read-only files.
pub fn remove_any(p: &Path) -> bool {
    let Ok(meta) = fs::symlink_metadata(p) else { return true };
    if meta.is_dir() && !meta.file_type().is_symlink() {
        if fs::remove_dir_all(p).is_ok() { return true; }
        clear_readonly_tree(p);
        return fs::remove_dir_all(p).is_ok();
    }
    if fs::remove_file(p).is_ok() { return true; }
    let mut perms = meta.permissions();
    #[allow(clippy::permissions_set_readonly_false)]
    perms.set_readonly(false);
    let _ = fs::set_permissions(p, perms);
    fs::remove_file(p).is_ok()
}

fn clear_readonly_tree(p: &Path) {
    if let Ok(rd) = fs::read_dir(p) {
        for e in rd.flatten() {
            let path = e.path();
            if let Ok(m) = fs::symlink_metadata(&path) {
                if m.is_dir() && !m.file_type().is_symlink() { clear_readonly_tree(&path); }
                let mut perms = m.permissions();
                #[allow(clippy::permissions_set_readonly_false)]
                perms.set_readonly(false);
                let _ = fs::set_permissions(&path, perms);
            }
        }
    }
}
