//! A tiny logistic regression: P(the user would regret deleting this). Starts from hand-set weights and learns, on
//! this PC only, from what the user deletes, declines and restores. Same model and prior as the macOS app.
use crate::decision::{DecisionRecord, Outcome};
use crate::model::{Candidate, GitStatus, Regen, Tier};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

pub type Features = HashMap<String, f64>;

pub fn features(c: &Candidate, rule_restore_rate: f64) -> Features {
    let mut v = Features::new();
    v.insert("tier.rebuildable".into(), (c.tier == Tier::Rebuildable) as u8 as f64);
    v.insert("tier.yours".into(), (c.tier == Tier::Yours) as u8 as f64);
    v.insert("regen.minutes".into(), (c.regen == Regen::Minutes) as u8 as f64);
    v.insert("regen.hours".into(), matches!(c.regen, Regen::Hours | Regen::Never) as u8 as f64);
    v.insert("size.log".into(), ((c.bytes.max(1) as f64 / 1e6).log10().max(0.0)) / 4.0);   // 1 MB -> 0, 10 GB -> 1
    v.insert("age.years".into(), (c.age_days as f64 / 365.0).min(3.0));
    match c.git {
        GitStatus::Dirty => { v.insert("git.dirty".into(), 1.0); }
        GitStatus::Unpushed => { v.insert("git.unpushed".into(), 1.0); }
        GitStatus::NoRemote => { v.insert("git.noRemote".into(), 1.0); }
        GitStatus::Pushed => { v.insert("git.pushed".into(), 1.0); }
        GitStatus::NotRepo => {}
    }
    v.insert("history.restoreRate".into(), rule_restore_rate);
    v
}

fn record_features(r: &DecisionRecord, restore_rate: f64) -> Features {
    let mut v = Features::new();
    v.insert("tier.rebuildable".into(), (r.tier == Tier::Rebuildable) as u8 as f64);
    v.insert("tier.yours".into(), (r.tier == Tier::Yours) as u8 as f64);
    v.insert("size.log".into(), (r.size_bucket as f64 / 13.0).clamp(0.0, 1.0));            // 2^13 MB is about 8 GB
    v.insert("age.years".into(), (r.age_bucket as f64 / 12.0).min(3.0));
    let key = match r.git.as_str() { "dirty" => Some("git.dirty"), "unpushed" => Some("git.unpushed"), "noRemote" => Some("git.noRemote"), "pushed" => Some("git.pushed"), _ => None };
    if let Some(k) = key { v.insert(k.into(), 1.0); }
    v.insert("history.restoreRate".into(), restore_rate);
    v
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct RegretModel {
    pub bias: f64,
    pub weights: HashMap<String, f64>,
    pub trained_on: usize,
}

impl RegretModel {
    pub fn prior() -> RegretModel {
        let w = [("tier.rebuildable", 0.8), ("tier.yours", 2.6), ("regen.minutes", 0.3), ("regen.hours", 0.9), ("size.log", 0.2), ("age.years", -0.4),
                 ("git.dirty", 2.4), ("git.unpushed", 2.2), ("git.noRemote", 1.6), ("git.pushed", -1.0), ("history.restoreRate", 3.0)];
        RegretModel { bias: -2.4, weights: w.iter().map(|(k, v)| (k.to_string(), *v)).collect(), trained_on: 0 }
    }

    pub fn predict(&self, f: &Features) -> f64 {
        let z = self.bias + f.iter().map(|(k, x)| self.weights.get(k).copied().unwrap_or(0.0) * x).sum::<f64>();
        1.0 / (1.0 + (-z).exp())
    }

    /// Plain SGD with a pull toward the prior, so a handful of examples can't wreck sane behaviour.
    pub fn fitted(&self, examples: &[(Features, f64, f64)]) -> RegretModel {
        if examples.is_empty() { return self.clone(); }
        let (epochs, lr, l2) = (40, 0.15, 0.02);
        let prior = RegretModel::prior();
        let mut m = self.clone();
        for _ in 0..epochs {
            for (f, y, w) in examples {
                let g = (m.predict(f) - y) * w;
                m.bias -= lr * (g + l2 * (m.bias - prior.bias));
                for (k, x) in f {
                    let cur = m.weights.get(k).copied().unwrap_or(0.0);
                    let p = prior.weights.get(k).copied().unwrap_or(0.0);
                    m.weights.insert(k.clone(), cur - lr * (g * x + l2 * (cur - p)));
                }
            }
        }
        m.trained_on = self.trained_on + examples.len();
        m
    }
}

pub fn restore_rates(records: &[DecisionRecord]) -> HashMap<String, f64> {
    let mut seen: HashMap<&str, (u32, u32)> = HashMap::new();
    for r in records {
        let e = seen.entry(r.rule_id.as_str()).or_default();
        match r.outcome { Outcome::Deleted => e.0 += 1, Outcome::Restored => e.1 += 1, Outcome::Declined => {} }
    }
    seen.into_iter().map(|(k, (d, r))| (k.to_string(), if d + r == 0 { 0.0 } else { r as f64 / (d + r) as f64 })).collect()
}

pub struct Scorer { pub model: RegretModel }

impl Scorer {
    pub fn new(model: Option<RegretModel>) -> Scorer { Scorer { model: model.unwrap_or_else(RegretModel::prior) } }

    pub fn regret(&self, c: &Candidate, rates: &HashMap<String, f64>) -> f64 {
        let p = self.model.predict(&features(c, rates.get(&c.rule_id).copied().unwrap_or(0.0)));
        // One-way safety: learning may make us MORE cautious about the yours tier, never less.
        if c.tier == Tier::Yours { p.max(0.5) } else { p }
    }

    /// restored -> regret; declined -> mild regret; deleted -> fine.
    pub fn retrain(&mut self, records: &[DecisionRecord]) {
        let rates = restore_rates(records);
        let examples: Vec<_> = records.iter().map(|r| {
            let f = record_features(r, rates.get(&r.rule_id).copied().unwrap_or(0.0));
            match r.outcome { Outcome::Restored => (f, 1.0, 1.0), Outcome::Declined => (f, 1.0, 0.5), Outcome::Deleted => (f, 0.0, 1.0) }
        }).collect();
        self.model = self.model.fitted(&examples);
    }
}
