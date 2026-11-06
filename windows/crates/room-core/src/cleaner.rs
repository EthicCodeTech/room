use crate::decision::{record_for, DecisionLog, Outcome};
use crate::env::Env;
use crate::model::*;
use crate::vault::{remove_any, StashItem, Vault};
use crate::{platform, safety, scan};
use serde::Serialize;
use std::collections::HashSet;
use std::path::Path;
use std::time::{Duration, SystemTime};

/// What the user explicitly agreed to, beyond ticking the box.
#[derive(Default, Clone)]
pub struct Confirmations {
    /// `yours` candidates the user confirmed by name.
    pub yours: HashSet<String>,
    /// Candidates in a git repo whose work isn't backed up that the user confirmed anyway.
    pub unbacked_repo: HashSet<String>,
    /// Preselected items the user unticked (a learning signal).
    pub declined: Vec<Candidate>,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", tag = "kind", content = "detail")]
pub enum Status { Deleted, Vaulted(u32), Skipped(String), Failed(String) }

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ItemResult { pub id: String, pub title: String, pub bytes: u64, pub status: Status }

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Report { pub results: Vec<ItemResult>, pub free_before: u64, pub free_after: u64, pub measured_freed: u64, pub vaulted_bytes: u64 }

pub struct Cleaner<'a> { pub vault: &'a Vault, pub log: Option<&'a DecisionLog>, pub env: &'a Env, pub known_rules: &'a HashSet<String> }

impl Cleaner<'_> {
    /// Refuses unsafe work up front. Returns a reason, or None if it can proceed.
    pub fn block_reason(&self, c: &Candidate, conf: &Confirmations) -> Option<String> {
        if let Some(h) = &c.held_back { return Some(h.clone()); }
        if c.tier == Tier::Yours && !conf.yours.contains(&c.id) { return Some("Needs your explicit confirmation".into()); }
        if !matches!(c.action, Action::Command(_)) && c.targets.is_empty() { return Some("Nothing to delete".into()); }
        for t in &c.targets {
            if !safety::is_deletable(&t.to_string_lossy(), self.env) { return Some("Protected location".into()); }
            if let Ok(m) = std::fs::symlink_metadata(t) { if platform::is_reparse_point(&m) { return Some("It is a link, not a real folder".into()); } }
        }
        if c.tier == Tier::Yours && c.git != GitStatus::NotRepo && !c.git.is_safe_copy_elsewhere() && !conf.unbacked_repo.contains(&c.id) {
            return Some(format!("Not backed up: {}", c.git.label()));
        }
        None
    }

    pub fn execute(&self, items: &[Candidate], conf: &Confirmations, policy: &dyn Fn(&Candidate) -> DeletionPolicy, now: i64, progress: &dyn Fn(&str)) -> Report {
        let (before, _) = platform::disk_space(&self.env.home);
        let mut results = vec![];
        for c in items {
            progress(&c.title);
            let status = if let Some(reason) = self.block_reason(c, conf) { Status::Skipped(reason) } else { self.run_one(c, policy(c), now) };
            if matches!(status, Status::Deleted | Status::Vaulted(_)) { self.record(c, Outcome::Deleted, now); }
            results.push(ItemResult { id: c.id.clone(), title: c.title.clone(), bytes: c.bytes, status });
        }
        for d in &conf.declined { self.record(d, Outcome::Declined, now); }
        let (after, _) = platform::disk_space(&self.env.home);
        let vaulted = results.iter().filter(|r| matches!(r.status, Status::Vaulted(_))).map(|r| r.bytes).sum();
        Report { results, free_before: before, free_after: after, measured_freed: after.saturating_sub(before), vaulted_bytes: vaulted }
    }

    fn record(&self, c: &Candidate, outcome: Outcome, now: i64) {
        if let Some(log) = self.log { log.append(&record_for(c, outcome, self.known_rules, now)); }
    }

    fn run_one(&self, c: &Candidate, policy: DeletionPolicy, now: i64) -> Status {
        match c.action {
            Action::Command(id) => self.run_command(id),
            Action::DeleteContents | Action::DeleteItem => match policy {
                DeletionPolicy::Immediate => self.delete_now(c),
                DeletionPolicy::Vault { days } => {
                    let per = c.bytes / c.targets.len().max(1) as u64;
                    let payload: Vec<StashItem> = c.targets.iter().map(|t| StashItem { path: t.clone(), bytes: per, title: c.title.clone(), rule_id: c.rule_id.clone() }).collect();
                    match self.vault.stash(&payload, &c.title, days, now) {
                        Ok((_, failures)) if failures.len() == c.targets.len() => Status::Failed(failures[0].1.clone()),
                        Ok(_) => Status::Vaulted(days),
                        Err(e) => Status::Failed(e.to_string()),
                    }
                }
            },
        }
    }

    fn run_command(&self, id: CommandId) -> Status {
        if id == CommandId::EmptyRecycleBin {
            return match platform::empty_recycle_bin() { Ok(()) => Status::Deleted, Err(e) => Status::Failed(e) };
        }
        for (tool, args) in id.steps() {
            if let Err(e) = platform::run_quiet(tool, &args) { return Status::Failed(e); }
        }
        Status::Deleted
    }

    fn delete_now(&self, c: &Candidate) -> Status {
        let min_age = c.min_age_minutes.map(|m| Duration::from_secs(m as u64 * 60));
        let old_enough = |p: &Path| min_age.is_none_or(|age| scan::modified(p).and_then(|t| SystemTime::now().duration_since(t).ok()).map(|d| d >= age).unwrap_or(true));
        let (mut removed, mut failed, mut skipped_new) = (0, 0, 0);
        for t in &c.targets {
            if c.action == Action::DeleteContents {
                let Ok(rd) = std::fs::read_dir(t) else { continue };
                for child in rd.flatten() {
                    let p = child.path();
                    if !old_enough(&p) { skipped_new += 1; continue; }
                    if remove_any(&p) { removed += 1 } else { failed += 1 }
                }
            } else if !old_enough(t) { skipped_new += 1; }
            else if remove_any(t) { removed += 1 } else { failed += 1 }
        }
        if removed == 0 && failed > 0 { return Status::Failed("In use by another program. Close it and try again.".into()); }
        if removed == 0 && skipped_new > 0 { return Status::Skipped("Everything in it was changed in the last hour".into()); }
        Status::Deleted
    }

    pub fn restore(&self, id: &str, now: i64) -> Result<Vec<std::path::PathBuf>, crate::vault::VaultError> {
        let manifest = self.vault.list().into_iter().find(|m| m.id == id);
        let urls = self.vault.restore(id)?;
        if let (Some(log), Some(m)) = (self.log, manifest) {
            for e in &m.entries {
                let known = self.known_rules.contains(&e.rule_id) || e.rule_id.starts_with("detect.");
                log.append(&crate::decision::DecisionRecord {
                    v: 1, day: crate::decision::utc_day(now), rule_id: if known { e.rule_id.clone() } else { "custom".into() }, tier: Tier::Yours,
                    size_bucket: 63 - (e.bytes / 1_000_000).max(1).leading_zeros(), age_bucket: 0, git: "notRepo".into(), outcome: Outcome::Restored,
                    app_version: crate::APP_VERSION.into(),
                });
            }
        }
        Ok(urls)
    }
}
