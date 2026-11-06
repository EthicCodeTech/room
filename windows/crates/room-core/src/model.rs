use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// How much a person should worry about deleting something.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Tier {
    /// A cache the app rebuilds by itself.
    Safe,
    /// Not your data, but getting it back costs time or bandwidth.
    Rebuildable,
    /// Might be your work or memories. Always your call.
    Yours,
}

impl Tier {
    pub const ALL: [Tier; 3] = [Tier::Safe, Tier::Rebuildable, Tier::Yours];
    pub fn title(self) -> &'static str {
        match self { Tier::Safe => "Safe", Tier::Rebuildable => "Rebuildable", Tier::Yours => "Yours" }
    }
}

/// Rough cost of getting something back after it is deleted.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Regen { Instant, Minutes, Hours, Never }

impl Regen {
    pub fn title(self) -> &'static str {
        match self {
            Regen::Instant => "Rebuilds instantly",
            Regen::Minutes => "Minutes to rebuild",
            Regen::Hours => "Hours to rebuild",
            Regen::Never => "Cannot be rebuilt",
        }
    }
}

/// The fixed set of commands a rule may trigger. A catalog can name them but never define new ones.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum CommandId { NpmCacheClean, PnpmStorePrune, UvCacheClean, DockerBuilderPrune, EmptyRecycleBin }

impl CommandId {
    /// The program and arguments. Fixed here, never read from data.
    pub fn steps(self) -> Vec<(&'static str, Vec<&'static str>)> {
        match self {
            CommandId::NpmCacheClean => vec![("npm", vec!["cache", "clean", "--force"])],
            CommandId::PnpmStorePrune => vec![("pnpm", vec!["store", "prune"])],
            CommandId::UvCacheClean => vec![("uv", vec!["cache", "clean"])],
            CommandId::DockerBuilderPrune => vec![("docker", vec!["builder", "prune", "-a", "-f"])],
            CommandId::EmptyRecycleBin => vec![],
        }
    }
    pub fn required_tool(self) -> Option<&'static str> {
        match self {
            CommandId::NpmCacheClean => Some("npm"),
            CommandId::PnpmStorePrune => Some("pnpm"),
            CommandId::UvCacheClean => Some("uv"),
            CommandId::DockerBuilderPrune => Some("docker"),
            CommandId::EmptyRecycleBin => None,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", tag = "type", content = "id")]
pub enum Action {
    /// Delete everything inside the folder, keep the folder.
    DeleteContents,
    /// Delete the matched item itself.
    DeleteItem,
    /// Run a fixed, whitelisted command.
    Command(CommandId),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum GitStatus { #[default] NotRepo, Pushed, NoRemote, Unpushed, Dirty }

impl GitStatus {
    pub fn key(self) -> &'static str {
        match self { GitStatus::NotRepo => "notRepo", GitStatus::Pushed => "pushed", GitStatus::NoRemote => "noRemote", GitStatus::Unpushed => "unpushed", GitStatus::Dirty => "dirty" }
    }
    pub fn label(self) -> &'static str {
        match self {
            GitStatus::NotRepo => "Not in a git repository",
            GitStatus::Pushed => "Everything is pushed",
            GitStatus::NoRemote => "Git repository with no remote",
            GitStatus::Unpushed => "Has unpushed commits",
            GitStatus::Dirty => "Has uncommitted changes",
        }
    }
    /// True when a copy of the work exists somewhere else.
    pub fn is_safe_copy_elsewhere(self) -> bool { matches!(self, GitStatus::Pushed | GitStatus::NotRepo) }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Kind { Rule, NodeModules, Installer, Duplicate, LargeFile, Command }

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Candidate {
    pub id: String,
    pub rule_id: String,
    pub kind: Kind,
    pub title: String,
    pub why: String,
    pub tier: Tier,
    pub regen: Regen,
    pub action: Action,
    pub targets: Vec<PathBuf>,
    pub display_path: String,
    /// What deleting would free, as measured on disk.
    pub bytes: u64,
    pub age_days: u32,
    pub preselected: bool,
    pub git: GitStatus,
    /// Extra caution shown to the user (cloud-synced folder, for example).
    pub note: Option<String>,
    /// Set when something stops this being cleaned right now (its app is open). Such items are never run.
    pub held_back: Option<String>,
    /// Only children untouched for this long are removed, so in-flight writes survive.
    pub min_age_minutes: Option<u32>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum DeletionPolicy {
    /// Gone now. Space is freed immediately.
    Immediate,
    /// Moved into the undo vault for N days. Space is freed when the vault is purged.
    Vault { days: u32 },
}

impl DeletionPolicy {
    pub const VAULT_DAYS: u32 = 7;
    /// Rule ids whose items are someone's files even though they count as rebuildable.
    pub const VAULTED_RULES: [&'static str; 2] = ["detect.installer", "detect.zip-duplicate"];

    pub fn default_for(c: &Candidate, vault_rebuildable: bool) -> DeletionPolicy {
        match c.tier {
            Tier::Yours => DeletionPolicy::Vault { days: Self::VAULT_DAYS },
            Tier::Rebuildable if vault_rebuildable || Self::VAULTED_RULES.contains(&c.rule_id.as_str()) => DeletionPolicy::Vault { days: Self::VAULT_DAYS },
            _ => DeletionPolicy::Immediate,
        }
    }
}
