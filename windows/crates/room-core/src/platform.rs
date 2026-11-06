//! The only place that knows about Windows. Everything has a portable fallback so the engine runs (and is tested) anywhere.
use std::fs::Metadata;
use std::path::{Path, PathBuf};

/// Cloud "placeholder" files report a size but occupy no disk, and deleting one deletes it everywhere.
#[cfg(windows)]
pub fn is_cloud_placeholder(meta: &Metadata) -> bool {
    use std::os::windows::fs::MetadataExt;
    const OFFLINE: u32 = 0x1000;
    const RECALL_ON_OPEN: u32 = 0x0004_0000;
    const RECALL_ON_DATA_ACCESS: u32 = 0x0040_0000;
    meta.file_attributes() & (OFFLINE | RECALL_ON_OPEN | RECALL_ON_DATA_ACCESS) != 0
}
#[cfg(not(windows))]
pub fn is_cloud_placeholder(_: &Metadata) -> bool { false }

/// Symlinks, junctions and other reparse points are never followed.
#[cfg(windows)]
pub fn is_reparse_point(meta: &Metadata) -> bool {
    use std::os::windows::fs::MetadataExt;
    meta.file_attributes() & 0x400 != 0 || meta.file_type().is_symlink()
}
#[cfg(not(windows))]
pub fn is_reparse_point(meta: &Metadata) -> bool { meta.file_type().is_symlink() }

/// Space the file occupies on disk (compression and sparse files counted correctly).
#[cfg(windows)]
pub fn allocated_size(path: &Path, meta: &Metadata) -> u64 {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::GetCompressedFileSizeW;
    let wide: Vec<u16> = path.as_os_str().encode_wide().chain(std::iter::once(0)).collect();
    let mut high: u32 = 0;
    let low = unsafe { GetCompressedFileSizeW(wide.as_ptr(), &mut high) };
    if low == u32::MAX && std::io::Error::last_os_error().raw_os_error() != Some(0) { return meta.len(); }
    ((high as u64) << 32) | low as u64
}
#[cfg(unix)]
pub fn allocated_size(_: &Path, meta: &Metadata) -> u64 { use std::os::unix::fs::MetadataExt; meta.blocks() * 512 }
#[cfg(not(any(windows, unix)))]
pub fn allocated_size(_: &Path, meta: &Metadata) -> u64 { meta.len() }

/// Root of the drive holding `path` (`D:\`), or the mount point on other systems.
#[cfg(windows)]
pub fn volume_root(path: &Path) -> Option<PathBuf> {
    use std::path::{Component, Prefix};
    match path.components().next()? {
        Component::Prefix(p) => match p.kind() {
            Prefix::Disk(d) | Prefix::VerbatimDisk(d) => Some(PathBuf::from(format!("{}:\\", d as char))),
            _ => None,
        },
        _ => None,
    }
}
#[cfg(not(windows))]
pub fn volume_root(path: &Path) -> Option<PathBuf> {
    let s = path.to_string_lossy();
    let rest = s.strip_prefix("/Volumes/")?;
    Some(PathBuf::from(format!("/Volumes/{}", rest.split('/').next()?)))
}

#[cfg(windows)]
pub fn same_volume(a: &Path, b: &Path) -> bool {
    match (volume_root(a), volume_root(b)) { (Some(x), Some(y)) => x.to_string_lossy().eq_ignore_ascii_case(&y.to_string_lossy()), _ => false }
}
#[cfg(unix)]
pub fn same_volume(a: &Path, b: &Path) -> bool {
    use std::os::unix::fs::MetadataExt;
    match (a.metadata(), b.metadata()) { (Ok(x), Ok(y)) => x.dev() == y.dev(), _ => false }
}
#[cfg(not(any(windows, unix)))]
pub fn same_volume(_: &Path, _: &Path) -> bool { false }

/// Hides a folder from Explorer and from Windows Search.
#[cfg(windows)]
pub fn hide_folder(path: &Path) {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::SetFileAttributesW;
    let wide: Vec<u16> = path.as_os_str().encode_wide().chain(std::iter::once(0)).collect();
    unsafe { SetFileAttributesW(wide.as_ptr(), 0x2 | 0x2000) }; // HIDDEN | NOT_CONTENT_INDEXED
}
#[cfg(not(windows))]
pub fn hide_folder(_: &Path) {}

/// Free and total bytes of the drive holding `path`.
pub fn disk_space(path: &Path) -> (u64, u64) {
    let probe = if path.exists() { path.to_path_buf() } else { PathBuf::from(".") };
    (fs4::available_space(&probe).unwrap_or(0), fs4::total_space(&probe).unwrap_or(0))
}

/// Windows only: bytes in the Recycle Bin and a way to empty it.
#[cfg(windows)]
pub fn recycle_bin_bytes() -> u64 {
    use windows_sys::Win32::UI::Shell::{SHQueryRecycleBinW, SHQUERYRBINFO};
    let mut info = SHQUERYRBINFO { cbSize: std::mem::size_of::<SHQUERYRBINFO>() as u32, i64Size: 0, i64NumItems: 0 };
    let hr = unsafe { SHQueryRecycleBinW(std::ptr::null(), &mut info) };
    if hr == 0 { info.i64Size.max(0) as u64 } else { 0 }
}
#[cfg(not(windows))]
pub fn recycle_bin_bytes() -> u64 { 0 }

#[cfg(windows)]
pub fn empty_recycle_bin() -> Result<(), String> {
    use windows_sys::Win32::UI::Shell::{SHEmptyRecycleBinW, SHERB_NOCONFIRMATION, SHERB_NOPROGRESSUI, SHERB_NOSOUND};
    let hr = unsafe { SHEmptyRecycleBinW(std::ptr::null_mut(), std::ptr::null(), SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND) };
    // S_OK, or S_FALSE when it was already empty.
    if hr == 0 || hr == 1 { Ok(()) } else { Err(format!("Windows could not empty the Recycle Bin (code {hr:#x})")) }
}
#[cfg(not(windows))]
pub fn empty_recycle_bin() -> Result<(), String> { Err("The Recycle Bin only exists on Windows".into()) }

/// Runs a fixed program without flashing a console window.
pub fn run_quiet(tool: &str, args: &[&str]) -> Result<String, String> {
    use std::process::Command;
    #[cfg(windows)]
    let mut cmd = { use std::os::windows::process::CommandExt; let mut c = Command::new("cmd"); c.arg("/C").arg(tool).args(args); c.creation_flags(0x0800_0000); c };
    #[cfg(not(windows))]
    let mut cmd = { let mut c = Command::new(tool); c.args(args); c };
    let mut child = cmd.stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::piped()).spawn().map_err(|e| e.to_string())?;
    let started = std::time::Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) if started.elapsed().as_secs() > 900 => { let _ = child.kill(); return Err("Timed out".into()); }
            Ok(None) => std::thread::sleep(std::time::Duration::from_millis(100)),
            Err(e) => return Err(e.to_string()),
        }
    }
    let out = child.wait_with_output().map_err(|e| e.to_string())?;
    let text = String::from_utf8_lossy(&out.stdout).to_string() + &String::from_utf8_lossy(&out.stderr);
    if out.status.success() { Ok(text) } else { Err(text.chars().rev().take(200).collect::<String>().chars().rev().collect()) }
}

/// True when a program is on the PATH.
pub fn tool_exists(tool: &str) -> bool {
    #[cfg(windows)]
    { run_quiet("where", &[tool]).is_ok() }
    #[cfg(not(windows))]
    { std::process::Command::new("which").arg(tool).output().map(|o| o.status.success()).unwrap_or(false) }
}

/// True when a program (`chrome.exe`) is running.
pub fn is_process_running(program: &str) -> bool {
    #[cfg(windows)]
    {
        let filter = format!("IMAGENAME eq {program}");
        run_quiet("tasklist", &["/FI", &filter, "/NH"]).map(|o| o.to_lowercase().contains(&program.to_lowercase())).unwrap_or(false)
    }
    #[cfg(not(windows))]
    { std::process::Command::new("pgrep").arg("-xi").arg(program.trim_end_matches(".exe")).output().map(|o| o.status.success()).unwrap_or(false) }
}
