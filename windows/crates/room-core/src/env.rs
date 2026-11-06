use std::path::{Path, PathBuf};

/// The handful of well-known folders rules refer to (`%LOCALAPPDATA%`, `~`, ...). A struct, not process
/// environment, so tests can point it at a sandbox.
#[derive(Clone, Debug)]
pub struct Env {
    pub home: PathBuf,
    pub local_app_data: PathBuf,
    pub app_data: PathBuf,
    pub temp: PathBuf,
    /// The drive Windows lives on (`C:\`). On other systems the root.
    pub system_drive: String,
}

impl Env {
    pub fn detect() -> Env {
        let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
        let local = std::env::var_os("LOCALAPPDATA").map(PathBuf::from)
            .or_else(dirs::data_local_dir).unwrap_or_else(|| home.join("AppData").join("Local"));
        let roaming = std::env::var_os("APPDATA").map(PathBuf::from)
            .or_else(dirs::data_dir).unwrap_or_else(|| home.join("AppData").join("Roaming"));
        Env {
            home,
            local_app_data: local,
            app_data: roaming,
            temp: std::env::temp_dir(),
            system_drive: std::env::var("SystemDrive").unwrap_or_else(|_| "C:".into()),
        }
    }

    /// A fake user folder for tests, laid out the way Windows lays out a profile.
    pub fn sandbox(root: &Path) -> Env {
        let home = root.join("home");
        Env {
            local_app_data: home.join("AppData").join("Local"),
            app_data: home.join("AppData").join("Roaming"),
            temp: home.join("AppData").join("Local").join("Temp"),
            home,
            system_drive: "C:".into(),
        }
    }

    /// Expands `%LOCALAPPDATA%`, `%APPDATA%`, `%TEMP%`, `%USERPROFILE%` and `~`, then globs. Both slash styles work.
    pub fn expand(&self, pattern: &str) -> Vec<PathBuf> {
        let mut p = pattern.to_string();
        for (key, value) in [
            ("%LOCALAPPDATA%", &self.local_app_data), ("%APPDATA%", &self.app_data), ("%TEMP%", &self.temp),
            ("%USERPROFILE%", &self.home),
        ] {
            p = p.replace(key, &value.to_string_lossy());
        }
        if let Some(rest) = p.strip_prefix("~") { p = format!("{}{}", self.home.to_string_lossy(), rest); }
        let normalized = p.replace('\\', "/");
        if normalized.contains(['*', '?', '[']) {
            let opts = glob::MatchOptions { case_sensitive: false, require_literal_separator: true, require_literal_leading_dot: false };
            return glob::glob_with(&normalized, opts).map(|it| it.flatten().collect()).unwrap_or_default();
        }
        let path = PathBuf::from(normalized);
        if path.exists() { vec![path] } else { vec![] }
    }

    /// Where projects usually live.
    pub fn default_project_roots(&self) -> Vec<PathBuf> {
        ["Projects", "source/repos", "dev", "code", "repos", "GitHub", "Documents/GitHub", "workspace", "src"]
            .iter().map(|r| self.home.join(r)).filter(|p| p.is_dir()).collect()
    }
}
