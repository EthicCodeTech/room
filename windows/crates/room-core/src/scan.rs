use crate::platform;
use rayon::prelude::*;
use std::fs;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::SystemTime;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Measured {
    pub bytes: u64,
    pub files: u64,
    /// Cloud-only files: they show a size but use no disk, so they count as nothing.
    pub placeholders: u64,
}

impl Measured {
    fn add(self, o: Measured) -> Measured { Measured { bytes: self.bytes + o.bytes, files: self.files + o.files, placeholders: self.placeholders + o.placeholders } }
}

/// Live counters for a long walk, and a flag to stop it. Shared between the walker and whoever shows progress.
#[derive(Default)]
pub struct Progress { pub files: AtomicU64, pub bytes: AtomicU64, pub stop: AtomicBool }

impl Progress {
    fn saw(&self, bytes: u64) { self.files.fetch_add(1, Ordering::Relaxed); self.bytes.fetch_add(bytes, Ordering::Relaxed); }
    pub fn stopped(&self) -> bool { self.stop.load(Ordering::Relaxed) }
}

/// Measures a file or folder by what it occupies on disk. Links and junctions are never followed.
pub fn measure(path: &Path) -> Measured { measure_with(path, None) }

pub fn measure_with(path: &Path, prog: Option<&Progress>) -> Measured {
    let Ok(meta) = fs::symlink_metadata(path) else { return Measured::default() };
    if platform::is_reparse_point(&meta) { return Measured::default(); }
    if meta.is_file() { return measure_file(path, &meta, prog); }
    if !meta.is_dir() { return Measured::default(); }
    measure_dir(path, prog)
}

/// Uses the size and attributes that the directory listing already carries, so a file costs no extra system call.
fn measure_dir(dir: &Path, prog: Option<&Progress>) -> Measured {
    if prog.is_some_and(|p| p.stopped()) { return Measured::default(); }
    let Ok(rd) = fs::read_dir(dir) else { return Measured::default() };
    let entries: Vec<fs::DirEntry> = rd.flatten().collect();
    let one = |e: &fs::DirEntry| -> Measured {
        let Ok(meta) = e.metadata() else { return Measured::default() };
        if platform::is_reparse_point(&meta) { return Measured::default(); }
        if meta.is_dir() { measure_dir(&e.path(), prog) } else if meta.is_file() { measure_file(&e.path(), &meta, prog) } else { Measured::default() }
    };
    // Small folders aren't worth the cost of fanning out.
    if entries.len() < 24 { entries.iter().map(one).fold(Measured::default(), Measured::add) } else { entries.par_iter().map(one).reduce(Measured::default, Measured::add) }
}

pub(crate) fn measure_file(path: &Path, meta: &fs::Metadata, prog: Option<&Progress>) -> Measured {
    if platform::is_cloud_placeholder(meta) { return Measured { placeholders: 1, ..Default::default() }; }
    let bytes = platform::allocated_size_fast(path, meta);
    if let Some(p) = prog { p.saw(bytes); }
    Measured { bytes, files: 1, placeholders: 0 }
}

pub fn modified(path: &Path) -> Option<SystemTime> { fs::symlink_metadata(path).and_then(|m| m.modified()).ok() }

pub fn age_days(path: &Path) -> u32 {
    modified(path).and_then(|t| SystemTime::now().duration_since(t).ok()).map(|d| (d.as_secs() / 86_400) as u32).unwrap_or(0)
}

/// Visits files under `root` down to `max_depth`, skipping `skip` folder names, links and cloud placeholders.
pub fn walk_files(root: &Path, max_depth: usize, skip: &[&str], visit: &mut dyn FnMut(&Path, &fs::Metadata)) {
    fn go(dir: &Path, depth: usize, max: usize, skip: &[&str], visit: &mut dyn FnMut(&Path, &fs::Metadata)) {
        let Ok(entries) = fs::read_dir(dir) else { return };
        for e in entries.flatten() {
            let path = e.path();
            let Ok(meta) = fs::symlink_metadata(&path) else { continue };
            if platform::is_reparse_point(&meta) { continue; }
            if meta.is_dir() {
                let name = e.file_name().to_string_lossy().to_lowercase();
                if depth < max && !skip.contains(&name.as_str()) { go(&path, depth + 1, max, skip, visit); }
            } else if meta.is_file() && !platform::is_cloud_placeholder(&meta) {
                visit(&path, &meta);
            }
        }
    }
    go(root, 1, max_depth, skip, visit);
}
