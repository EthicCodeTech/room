use crate::platform;
use rayon::prelude::*;
use std::fs;
use std::path::Path;
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

/// Measures a file or folder by what it occupies on disk. Links and junctions are never followed.
pub fn measure(path: &Path) -> Measured {
    let Ok(meta) = fs::symlink_metadata(path) else { return Measured::default() };
    if platform::is_reparse_point(&meta) { return Measured::default(); }
    if meta.is_file() { return measure_file(path, &meta); }
    if !meta.is_dir() { return Measured::default(); }
    let Ok(entries) = fs::read_dir(path) else { return Measured::default() };
    let children: Vec<_> = entries.flatten().collect();
    children.par_iter().map(|e| measure(&e.path())).reduce(Measured::default, Measured::add)
}

fn measure_file(path: &Path, meta: &fs::Metadata) -> Measured {
    if platform::is_cloud_placeholder(meta) { return Measured { placeholders: 1, ..Default::default() }; }
    Measured { bytes: platform::allocated_size(path, meta), files: 1, placeholders: 0 }
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
