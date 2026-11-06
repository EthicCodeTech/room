use crate::model::{Action, Regen, Tier};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Guards {
    /// Program names (`chrome.exe`). If one is running, the rule is held back.
    #[serde(default)]
    pub app_running: Vec<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Rule {
    pub id: String,
    pub title: String,
    pub why: String,
    pub tier: Tier,
    pub regen: Regen,
    pub paths: Vec<String>,
    pub action: Action,
    #[serde(default)]
    pub min_age_minutes: Option<u32>,
    /// Work types this rule matters to ("video", "gaming", ...). Empty means everyone.
    #[serde(default)]
    pub personas: Vec<String>,
    #[serde(default)]
    pub guards: Guards,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Catalog {
    pub version: u32,
    pub rules: Vec<Rule>,
}

impl Catalog {
    pub fn builtin() -> Catalog {
        serde_json::from_str(include_str!("catalog-windows.json")).expect("the built-in catalog is valid JSON")
    }
    pub fn rule(&self, id: &str) -> Option<&Rule> { self.rules.iter().find(|r| r.id == id) }
}
