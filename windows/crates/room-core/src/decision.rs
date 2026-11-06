use crate::model::{Candidate, Tier};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::fs::OpenOptions;
use std::io::Write;
use std::path::PathBuf;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Outcome { Deleted, Declined, Restored }

/// One anonymized learning example. By construction it holds no paths, names or contents: only a closed-set
/// rule id, coarse buckets and the outcome. It never leaves this PC.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DecisionRecord {
    pub v: u32,
    pub day: String,
    pub rule_id: String,
    pub tier: Tier,
    pub size_bucket: u32,
    pub age_bucket: u32,
    pub git: String,
    pub outcome: Outcome,
    pub app_version: String,
}

const DETECTORS: [&str; 4] = ["detect.node_modules", "detect.installer", "detect.zip-duplicate", "detect.large-old"];

pub fn record_for(c: &Candidate, outcome: Outcome, known_rules: &HashSet<String>, now_secs: i64) -> DecisionRecord {
    let known = known_rules.contains(&c.rule_id) || DETECTORS.contains(&c.rule_id.as_str());
    let mb = (c.bytes / 1_000_000).max(1);
    DecisionRecord {
        v: 1, day: utc_day(now_secs), rule_id: if known { c.rule_id.clone() } else { "custom".into() }, tier: c.tier,
        size_bucket: 63 - mb.leading_zeros(), age_bucket: (c.age_days / 30).min(60), git: c.git.key().into(),
        outcome, app_version: crate::APP_VERSION.into(),
    }
}

/// `YYYY-MM-DD` in UTC without a date library (Howard Hinnant's civil-from-days).
pub fn utc_day(secs: i64) -> String {
    let z = secs.div_euclid(86_400) + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + if m <= 2 { 1 } else { 0 };
    format!("{y:04}-{m:02}-{d:02}")
}

pub struct DecisionLog { path: PathBuf }

impl DecisionLog {
    pub fn new(path: PathBuf) -> DecisionLog { DecisionLog { path } }
    pub fn append(&self, r: &DecisionRecord) {
        if let Some(dir) = self.path.parent() { let _ = std::fs::create_dir_all(dir); }
        if let (Ok(line), Ok(mut f)) = (serde_json::to_string(r), OpenOptions::new().create(true).append(true).open(&self.path)) {
            let _ = writeln!(f, "{line}");
        }
    }
    pub fn load(&self) -> Vec<DecisionRecord> {
        std::fs::read_to_string(&self.path).map(|t| t.lines().filter_map(|l| serde_json::from_str(l).ok()).collect()).unwrap_or_default()
    }
}
