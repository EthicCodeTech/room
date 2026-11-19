use crate::model::{Candidate, Tier};
use crate::scorer::Scorer;
use serde::Serialize;
use std::collections::{HashMap, HashSet};

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Plan {
    pub item_ids: Vec<String>,
    pub goal_bytes: u64,
    pub guaranteed_bytes: u64,
    pub reaches_goal: bool,
    pub shortfall: u64,
    pub total_regret: f64,
}

/// Picks the cheapest, lowest-regret set of actions that reaches a goal. In stages: safe items alone first, and only
/// if they can't reach the goal does it widen to the next tier, so a lower-risk tier is never skipped for a bigger one.
pub fn plan(scorer: &Scorer, rates: &HashMap<String, f64>, goal: u64, candidates: &[Candidate], allowed: &[Tier]) -> Plan {
    let mut best = Plan { item_ids: vec![], goal_bytes: goal, guaranteed_bytes: 0, reaches_goal: goal == 0, shortfall: goal, total_regret: 0.0 };
    for stage in Tier::ALL.iter().filter(|t| allowed.contains(t)) {
        let pool: Vec<&Candidate> = candidates.iter().filter(|c| c.tier <= *stage && allowed.contains(&c.tier) && c.bytes > 0 && c.held_back.is_none()).collect();
        best = select(scorer, rates, goal, &pool);
        if best.reaches_goal { return best; }
    }
    best
}

fn select(scorer: &Scorer, rates: &HashMap<String, f64>, goal: u64, pool: &[&Candidate]) -> Plan {
    let mut scored: Vec<(&Candidate, f64)> = pool.iter().map(|c| (*c, scorer.regret(c, rates))).collect();
    // Best value first: most guaranteed space per unit of regret.
    scored.sort_by(|a, b| (b.0.bytes as f64 / (0.05 + b.1)).partial_cmp(&(a.0.bytes as f64 / (0.05 + a.1))).unwrap_or(std::cmp::Ordering::Equal));
    let mut chosen: Vec<(&Candidate, f64)> = vec![];
    let mut total = 0u64;
    for entry in scored { if total >= goal { break; } total += entry.0.bytes; chosen.push(entry); }
    // Drop anything that turned out redundant, highest regret first.
    let mut by_regret: Vec<_> = chosen.iter().map(|(c, r)| (c.id.clone(), c.bytes, *r)).collect();
    by_regret.sort_by(|a, b| b.2.partial_cmp(&a.2).unwrap_or(std::cmp::Ordering::Equal));
    let mut dropped = HashSet::new();
    for (id, bytes, _) in by_regret { if total - bytes >= goal { total -= bytes; dropped.insert(id); } }
    chosen.retain(|(c, _)| !dropped.contains(&c.id));
    chosen.sort_by_key(|c| std::cmp::Reverse(c.0.bytes));
    Plan { item_ids: chosen.iter().map(|(c, _)| c.id.clone()).collect(), goal_bytes: goal, guaranteed_bytes: total, reaches_goal: total >= goal,
           shortfall: goal.saturating_sub(total), total_regret: chosen.iter().map(|c| c.1).sum() }
}
