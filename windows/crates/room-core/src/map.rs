use crate::{platform, scan};
use rayon::prelude::*;
use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MapNode { pub name: String, pub path: String, pub bytes: u64, pub is_dir: bool }

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Drive { pub name: String, pub path: String, pub free: u64, pub total: u64 }

/// Sizes of everything directly inside `dir`, largest first. Links are not followed, so a junction can't loop the map.
pub fn children(dir: &Path, limit: usize) -> Vec<MapNode> {
    let Ok(rd) = fs::read_dir(dir) else { return vec![] };
    let entries: Vec<_> = rd.flatten().collect();
    let mut nodes: Vec<MapNode> = entries.par_iter().filter_map(|e| {
        let path = e.path();
        let meta = fs::symlink_metadata(&path).ok()?;
        if platform::is_reparse_point(&meta) { return None; }
        Some(MapNode { name: e.file_name().to_string_lossy().to_string(), path: path.to_string_lossy().to_string(), bytes: scan::measure(&path).bytes, is_dir: meta.is_dir() })
    }).collect();
    nodes.sort_by_key(|n| std::cmp::Reverse(n.bytes));
    if nodes.len() > limit {
        let rest: u64 = nodes[limit..].iter().map(|n| n.bytes).sum();
        let count = nodes.len() - limit;
        nodes.truncate(limit);
        nodes.push(MapNode { name: format!("{count} smaller items"), path: String::new(), bytes: rest, is_dir: false });
    }
    nodes.retain(|n| n.bytes > 0);
    nodes
}

/// The drives a person can pick to map.
pub fn drives() -> Vec<Drive> {
    #[cfg(windows)]
    let roots: Vec<PathBuf> = (b'A'..=b'Z').map(|l| PathBuf::from(format!("{}:\\", l as char))).filter(|p| p.exists()).collect();
    #[cfg(not(windows))]
    let roots: Vec<PathBuf> = { let mut v = vec![PathBuf::from("/")]; if let Ok(rd) = fs::read_dir("/Volumes") { v.extend(rd.flatten().map(|e| e.path())); } v };
    roots.into_iter().map(|p| {
        let (free, total) = platform::disk_space(&p);
        Drive { name: p.to_string_lossy().trim_end_matches(['\\', '/']).to_string(), path: p.to_string_lossy().to_string(), free, total }
    }).filter(|d| d.total > 0).collect()
}
