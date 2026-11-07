use crate::{platform, scan};
use rayon::prelude::*;
use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};

#[derive(Clone, Copy, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum NodeKind { Dir, File, /// Many files lumped together: "[27 files]".
    Files, /// Many small items lumped together.
    Other }

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TreeNode {
    pub name: String,
    pub path: String,
    pub bytes: u64,
    pub kind: NodeKind,
    /// Files inside (for folders) or lumped together (for `Files`).
    pub files: u64,
    pub children: Vec<TreeNode>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Drive { pub name: String, pub path: String, pub free: u64, pub total: u64 }

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Place { pub name: String, pub path: String }

/// Sizes of a folder and what is inside it, in one walk. `depth` levels of folders keep their children
/// (the top level also lists its files); anything deeper is summed. Links are not followed, so a junction can't loop.
/// Stops early, returning what it has, when `cancel` is set.
pub fn tree(dir: &Path, depth: usize, max_children: usize, cancel: &AtomicBool) -> TreeNode {
    let mut node = walk(dir, depth.max(1), true, max_children, cancel);
    node.name = dir.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_else(|| dir.to_string_lossy().to_string());
    node.path = dir.to_string_lossy().to_string();
    node
}

fn walk(dir: &Path, depth: usize, top: bool, max_children: usize, cancel: &AtomicBool) -> TreeNode {
    let mut node = TreeNode { name: dir.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default(), path: dir.to_string_lossy().to_string(),
                              bytes: 0, kind: NodeKind::Dir, files: 0, children: vec![] };
    if cancel.load(Ordering::Relaxed) { return node; }
    let Ok(rd) = fs::read_dir(dir) else { return node };
    let entries: Vec<_> = rd.flatten().collect();
    enum Item { Dir(TreeNode), File(PathBuf, String, u64) }
    let items: Vec<Item> = entries.par_iter().filter_map(|e| {
        let path = e.path();
        let meta = fs::symlink_metadata(&path).ok()?;
        if platform::is_reparse_point(&meta) { return None; }
        let name = e.file_name().to_string_lossy().to_string();
        if meta.is_dir() {
            if depth > 1 { Some(Item::Dir(walk(&path, depth - 1, false, max_children, cancel))) }
            else {
                let m = scan::measure(&path);
                Some(Item::Dir(TreeNode { name, path: path.to_string_lossy().to_string(), bytes: m.bytes, kind: NodeKind::Dir, files: m.files, children: vec![] }))
            }
        } else if meta.is_file() && !platform::is_cloud_placeholder(&meta) {
            let size = platform::allocated_size(&path, &meta);
            Some(Item::File(path, name, size))
        } else { None }
    }).collect();

    let mut files: Vec<(PathBuf, String, u64)> = vec![];
    for it in items {
        match it { Item::Dir(d) => { node.bytes += d.bytes; node.files += d.files; node.children.push(d); } Item::File(p, n, s) => files.push((p, n, s)) }
    }
    let file_bytes: u64 = files.iter().map(|f| f.2).sum();
    node.bytes += file_bytes;
    node.files += files.len() as u64;
    if top {
        // The top level lists its files one by one (the biggest ones), lumping the small rest.
        files.sort_by_key(|f| std::cmp::Reverse(f.2));
        let keep = files.len().min(300);
        let rest: Vec<_> = files.split_off(keep);
        for (p, n, s) in files { node.children.push(TreeNode { name: n, path: p.to_string_lossy().to_string(), bytes: s, kind: NodeKind::File, files: 1, children: vec![] }); }
        if !rest.is_empty() {
            node.children.push(TreeNode { name: format!("{} smaller files", rest.len()), path: String::new(), bytes: rest.iter().map(|f| f.2).sum(), kind: NodeKind::Files, files: rest.len() as u64, children: vec![] });
        }
    } else if !files.is_empty() {
        node.children.push(TreeNode { name: format!("[{} files]", files.len()), path: String::new(), bytes: file_bytes, kind: NodeKind::Files, files: files.len() as u64, children: vec![] });
    }
    node.children.retain(|c| c.bytes > 0);
    node.children.sort_by_key(|c| std::cmp::Reverse(c.bytes));
    if node.children.len() > max_children {
        let rest: Vec<TreeNode> = node.children.split_off(max_children);
        node.children.push(TreeNode { name: format!("{} smaller items", rest.len()), path: String::new(), bytes: rest.iter().map(|c| c.bytes).sum(), kind: NodeKind::Other,
                                      files: rest.iter().map(|c| c.files).sum(), children: vec![] });
    }
    node
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

/// Folders worth jumping straight to.
pub fn places(env: &crate::env::Env) -> Vec<Place> {
    let mut v = vec![Place { name: "Home".into(), path: env.home.to_string_lossy().to_string() }];
    for (name, p) in [("Downloads", dirs::download_dir()), ("Documents", dirs::document_dir()), ("Desktop", dirs::desktop_dir()), ("Videos", dirs::video_dir()), ("Pictures", dirs::picture_dir())] {
        if let Some(p) = p.filter(|p| p.is_dir()) { v.push(Place { name: name.into(), path: p.to_string_lossy().to_string() }); }
    }
    v.push(Place { name: "AppData (Local)".into(), path: env.local_app_data.to_string_lossy().to_string() });
    for root in env.default_project_roots().into_iter().take(1) { v.push(Place { name: "Projects".into(), path: root.to_string_lossy().to_string() }); }
    v.retain(|p| Path::new(&p.path).is_dir());
    v
}
