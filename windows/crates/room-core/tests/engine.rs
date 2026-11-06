use room_core::cleaner::{Cleaner, Confirmations, Status};
use room_core::decision::{utc_day, DecisionLog, DecisionRecord, Outcome};
use room_core::discover::{discover, Options};
use room_core::env::Env;
use room_core::model::*;
use room_core::planner::plan;
use room_core::scorer::{restore_rates, Scorer};
use room_core::vault::{StashItem, Vault, VaultError, Volumes, DRIVE_FOLDER};
use room_core::{format_bytes, safety};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;

fn windows_env() -> Env {
    Env { home: PathBuf::from(r"C:\Users\Ada"), local_app_data: PathBuf::from(r"C:\Users\Ada\AppData\Local"), app_data: PathBuf::from(r"C:\Users\Ada\AppData\Roaming"),
          temp: PathBuf::from(r"C:\Users\Ada\AppData\Local\Temp"), system_drive: "C:".into() }
}

fn file(dir: &Path, rel: &str, bytes: usize) -> PathBuf {
    let p = dir.join(rel);
    fs::create_dir_all(p.parent().unwrap()).unwrap();
    fs::write(&p, vec![7u8; bytes]).unwrap();
    p
}

fn cand(id: &str, tier: Tier, targets: Vec<PathBuf>, bytes: u64, rule: &str) -> Candidate {
    Candidate { id: id.into(), rule_id: rule.into(), kind: Kind::Rule, title: format!("Test {id}"), why: "why".into(), tier, regen: Regen::Instant, action: Action::DeleteItem,
                display_path: String::new(), targets, bytes, age_days: 0, preselected: tier == Tier::Safe, git: GitStatus::NotRepo, note: None, held_back: None, min_age_minutes: None }
}

// ---- safety (Windows paths, tested on any OS) ----

#[test]
fn windows_safety_allows_profile_contents_and_blocks_system_places() {
    let env = windows_env();
    for ok in [r"C:\Users\Ada\AppData\Local\Temp\x", r"c:\users\ada\.gradle\caches", r"C:\Users\Ada\Projects\app\node_modules", r"D:\Videos\Raw\clip.mov", r"E:\work\old"] {
        assert!(safety::is_deletable(ok, &env), "{ok} should be deletable");
    }
    for bad in [r"C:\", r"C:\Windows", r"C:\Windows\System32\drivers", r"C:\Program Files\Thing", r"C:\Users", r"C:\Users\Ada", r"C:\Users\Ada\Documents",
                r"C:\Users\Ada\Desktop", r"C:\Users\Ada\AppData\Local", r"C:\Users\Ada\AppData\Roaming", r"D:\", r"D:\Videos", r"D:\$Recycle.Bin\x", r"D:\System Volume Information\x",
                r"C:\Users\Ada\..\Bob\x", "", "/"] {
        assert!(!safety::is_deletable(bad, &env), "{bad} must be protected");
    }
    assert!(safety::is_deletable(r"\\?\C:\Users\Ada\AppData\Local\Temp\x", &env), "extended-length prefix is understood");
}

#[test]
fn cloud_folders_are_recognised() {
    assert_eq!(safety::in_cloud_folder(Path::new("home/OneDrive - Acme/Docs/a.psd")), Some("OneDrive"));
    assert_eq!(safety::in_cloud_folder(Path::new("home/Dropbox/a")), Some("Dropbox"));
    assert_eq!(safety::in_cloud_folder(Path::new("home/Projects/a")), None);
}

#[test]
fn bytes_read_like_people_say_them() {
    assert_eq!(format_bytes(0), "0 bytes");
    assert_eq!(format_bytes(31_764_480), "31.8 MB");
    assert_eq!(format_bytes(2_068_938_752), "2.1 GB");
    assert_eq!(format_bytes(494_000_000_000), "494 GB");
    assert_eq!(utc_day(0), "1970-01-01");
    assert_eq!(utc_day(1_793_953_238), "2026-11-06");
}

// ---- vault, with a pretend second drive ----

struct FakeDrive { drive: PathBuf }
impl Volumes for FakeDrive {
    fn volume_root(&self, p: &Path) -> Option<PathBuf> { p.starts_with(&self.drive).then(|| self.drive.clone()) }
    fn same_volume(&self, a: &Path, b: &Path) -> bool { a.starts_with(&self.drive) == b.starts_with(&self.drive) }
    fn to_recycle_bin(&self, _: &Path) -> Result<(), String> { Err("no recycle bin in tests".into()) }
}

fn vault_with_drive(root: &Path) -> (Vault, PathBuf) {
    let drive = root.join("drive");
    fs::create_dir_all(&drive).unwrap();
    (Vault::with_volumes(root.join("app").join("Vault"), Arc::new(FakeDrive { drive: drive.clone() })), drive)
}

fn item(p: &Path) -> StashItem { StashItem { path: p.to_path_buf(), bytes: 2048, title: "Clip".into(), rule_id: "detect.installer".into() } }

#[test]
fn drive_items_stay_on_the_drive_and_come_back() {
    let dir = tempfile::tempdir().unwrap();
    let (vault, drive) = vault_with_drive(dir.path());
    let f = file(&drive, "render.mov", 2048);
    let (m, fails) = vault.stash(&[item(&f)], "Clip", 7, 1000).unwrap();
    assert!(fails.is_empty());
    let e = &m.entries[0];
    assert_eq!(e.volume.as_deref(), Some(drive.to_str().unwrap()));
    assert!(e.stored_path.contains(DRIVE_FOLDER), "kept in the drive's own vault, not copied anywhere");
    assert!(!f.exists());
    vault.restore(&m.id).unwrap();
    assert!(f.exists());
    assert!(!drive.join(DRIVE_FOLDER).exists(), "an empty vault leaves nothing behind");
    assert!(vault.list().is_empty());
}

#[test]
fn main_drive_items_go_to_the_central_vault() {
    let dir = tempfile::tempdir().unwrap();
    let (vault, _) = vault_with_drive(dir.path());
    let f = file(dir.path(), "home/Downloads/setup.msi", 2048);
    let (m, _) = vault.stash(&[item(&f)], "Installers", 7, 1000).unwrap();
    assert!(m.entries[0].volume.is_none());
    assert_eq!(m.expires, 1000 + 7 * 86_400);
    vault.restore(&m.id).unwrap();
    assert!(f.exists());
}

#[test]
fn a_taken_spot_restores_beside_it() {
    let dir = tempfile::tempdir().unwrap();
    let (vault, _) = vault_with_drive(dir.path());
    let f = file(dir.path(), "home/a.zip", 100);
    let (m, _) = vault.stash(&[item(&f)], "z", 7, 0).unwrap();
    fs::write(&f, b"new").unwrap();
    let back = vault.restore(&m.id).unwrap();
    assert_eq!(back[0].file_name().unwrap(), "a (restored).zip");
    assert_eq!(fs::read(&f).unwrap(), b"new");
}

#[test]
fn an_unplugged_drive_keeps_its_batch_until_it_is_back() {
    let dir = tempfile::tempdir().unwrap();
    let (vault, drive) = vault_with_drive(dir.path());
    let f = file(&drive, "b.mov", 2048);
    let (m, _) = vault.stash(&[item(&f)], "Clip", 7, 0).unwrap();
    let away = dir.path().join("drive-away");
    fs::rename(&drive, &away).unwrap();                                    // unplug
    assert!(!vault.is_available(&m));
    assert!(!vault.purge(&m.id), "can't delete what we can't reach");
    assert!(matches!(vault.restore(&m.id), Err(VaultError::Partial { restored: 0, .. })));
    assert_eq!(vault.purge_expired(1_000_000_000), 0);
    assert_eq!(vault.list().len(), 1, "still listed");
    fs::rename(&away, &drive).unwrap();                                    // plug back in
    assert!(vault.is_available(&m));
    vault.restore(&m.id).unwrap();
    assert!(f.exists());
}

#[test]
fn purging_removes_the_drive_copy_and_tidies_up() {
    let dir = tempfile::tempdir().unwrap();
    let (vault, drive) = vault_with_drive(dir.path());
    let (m, _) = vault.stash(&[item(&file(&drive, "a.mov", 100))], "Clip", 7, 0).unwrap();
    assert!(vault.purge(&m.id));
    assert!(!drive.join(DRIVE_FOLDER).exists());
    assert!(vault.list().is_empty());
}

// ---- cleaner ----

fn cleaner<'a>(vault: &'a Vault, log: &'a DecisionLog, env: &'a Env, rules: &'a HashSet<String>) -> Cleaner<'a> { Cleaner { vault, log: Some(log), env, known_rules: rules } }

#[test]
fn the_cleaner_enforces_tiers_confirmations_and_the_vault() {
    let dir = tempfile::tempdir().unwrap();
    let env = Env::sandbox(dir.path());
    let (vault, _) = vault_with_drive(dir.path());
    let log = DecisionLog::new(dir.path().join("app").join("decisions.jsonl"));
    let rules: HashSet<String> = ["cache.spotify".to_string()].into();
    let c = cleaner(&vault, &log, &env, &rules);
    let cache = file(&env.home, "AppData/Local/Spotify/Data/blob", 4096).parent().unwrap().to_path_buf();
    let mine = file(&env.home, "Downloads/precious.bin", 4096);
    let outside = file(dir.path(), "elsewhere/keep.txt", 10);
    let items = vec![
        { let mut x = cand("safe", Tier::Safe, vec![cache.clone()], 4096, "cache.spotify"); x.action = Action::DeleteContents; x },
        cand("yours", Tier::Yours, vec![mine.clone()], 4096, "detect.large-old"),
        cand("protected", Tier::Safe, vec![outside.clone()], 10, "cache.spotify"),
        { let mut x = cand("held", Tier::Safe, vec![], 5, "cache.spotify"); x.held_back = Some("Close Chrome to include this.".into()); x },
    ];
    let policy = |c: &Candidate| DeletionPolicy::default_for(c, false);
    let r = c.execute(&items, &Confirmations::default(), &policy, 1000, &|_| {});
    assert_eq!(r.results[0].status, Status::Deleted);
    assert!(!cache.join("blob").exists() && cache.exists(), "contents removed, folder kept");
    assert_eq!(r.results[1].status, Status::Skipped("Needs your explicit confirmation".into()));
    assert!(mine.exists());
    assert_eq!(r.results[2].status, Status::Skipped("Protected location".into()));
    assert!(outside.exists());
    assert_eq!(r.results[3].status, Status::Skipped("Close Chrome to include this.".into()));

    let mut conf = Confirmations::default();
    conf.yours.insert("yours".into());
    let r2 = c.execute(&items[1..2], &conf, &policy, 1000, &|_| {});
    assert_eq!(r2.results[0].status, Status::Vaulted(7));
    assert!(!mine.exists());
    let batch = vault.list().remove(0);
    c.restore(&batch.id, 2000).unwrap();
    assert!(mine.exists(), "restored exactly");
    let kinds: Vec<Outcome> = log.load().iter().map(|r| r.outcome).collect();
    assert_eq!(kinds, vec![Outcome::Deleted, Outcome::Deleted, Outcome::Restored]);
    assert!(log.load().iter().all(|r| !serde_json::to_string(r).unwrap().contains("Ada")), "records carry no names");
}

#[test]
fn installers_and_zips_are_vaulted_and_caches_are_not() {
    let rb = |rule: &str| cand("x", Tier::Rebuildable, vec![], 1, rule);
    assert_eq!(DeletionPolicy::default_for(&rb("detect.installer"), false), DeletionPolicy::Vault { days: 7 });
    assert_eq!(DeletionPolicy::default_for(&rb("detect.zip-duplicate"), false), DeletionPolicy::Vault { days: 7 });
    assert_eq!(DeletionPolicy::default_for(&rb("detect.node_modules"), false), DeletionPolicy::Immediate);
    assert_eq!(DeletionPolicy::default_for(&rb("detect.node_modules"), true), DeletionPolicy::Vault { days: 7 });
    assert_eq!(DeletionPolicy::default_for(&cand("c", Tier::Safe, vec![], 1, "cache.x"), true), DeletionPolicy::Immediate);
}

#[test]
fn recent_files_survive_a_cache_clean() {
    let dir = tempfile::tempdir().unwrap();
    let env = Env::sandbox(dir.path());
    let (vault, _) = vault_with_drive(dir.path());
    let rules = HashSet::new();
    let c = Cleaner { vault: &vault, log: None, env: &env, known_rules: &rules };
    let temp = file(&env.home, "AppData/Local/Temp/in-use.tmp", 10).parent().unwrap().to_path_buf();
    let mut t = cand("t", Tier::Safe, vec![temp.clone()], 10, "cache.user-temp");
    t.action = Action::DeleteContents; t.min_age_minutes = Some(60);
    let r = c.execute(&[t], &Confirmations::default(), &|c| DeletionPolicy::default_for(c, false), 0, &|_| {});
    assert!(temp.join("in-use.tmp").exists(), "touched in the last hour, so left alone");
    assert!(matches!(r.results[0].status, Status::Skipped(_)));
}

// ---- discovery ----

#[test]
fn discovery_finds_caches_stale_projects_installers_and_big_old_files() {
    let dir = tempfile::tempdir().unwrap();
    let env = Env::sandbox(dir.path());
    file(&env.home, "AppData/Local/CrashDumps/a.dmp", 50_000);
    file(&env.home, "Projects/old-app/package.json", 10);
    file(&env.home, "Projects/old-app/node_modules/dep/index.js", 60_000);
    file(&env.home, "Projects/fresh-app/package.json", 10);
    file(&env.home, "Projects/fresh-app/node_modules/dep/index.js", 60_000);
    file(&env.home, "Downloads/tool-setup.msi", 40_000);
    file(&env.home, "Downloads/pack.zip", 30_000);
    fs::create_dir_all(env.home.join("Downloads/pack")).unwrap();
    for p in ["Projects/old-app", "Projects/old-app/package.json"] {
        let t = std::time::SystemTime::now() - std::time::Duration::from_secs(200 * 86_400);
        fs::File::open(env.home.join(p)).unwrap().set_modified(t).unwrap();
    }
    let old = std::time::SystemTime::now() - std::time::Duration::from_secs(30 * 86_400);
    fs::File::open(env.home.join("Downloads/tool-setup.msi")).unwrap().set_modified(old).unwrap();
    let mut opts = Options::new(env.clone());
    opts.min_bytes = 1;
    opts.check_running_apps = false;
    let found = discover(&opts, &|_| {});
    let by = |rule: &str| found.iter().filter(|c| c.rule_id == rule).collect::<Vec<_>>();
    assert_eq!(by("cache.crash-dumps").len(), 1);
    assert_eq!(by("cache.crash-dumps")[0].tier, Tier::Safe);
    let nm = by("detect.node_modules");
    assert_eq!(nm.len(), 1, "only the stale project");
    assert!(nm[0].title.contains("old-app"));
    assert_eq!(by("detect.installer").len(), 1);
    assert_eq!(by("detect.zip-duplicate").len(), 1);
    assert!(found.windows(2).all(|w| w[0].bytes >= w[1].bytes), "largest first");
}

#[test]
fn work_types_only_switch_on_their_own_rules() {
    let dir = tempfile::tempdir().unwrap();
    let env = Env::sandbox(dir.path());
    file(&env.home, "AppData/Roaming/Adobe/Common/Media Cache Files/a.cfa", 50_000);
    let mut opts = Options::new(env);
    opts.min_bytes = 1; opts.check_running_apps = false;
    assert_eq!(discover(&opts, &|_| {}).iter().filter(|c| c.rule_id == "cache.premiere-media").count(), 1, "no choice yet means everyone's rules");
    opts.work_types = vec!["dev".into()];
    assert!(discover(&opts, &|_| {}).iter().all(|c| c.rule_id != "cache.premiere-media"));
    opts.work_types = vec!["video".into()];
    assert_eq!(discover(&opts, &|_| {}).iter().filter(|c| c.rule_id == "cache.premiere-media").count(), 1);
}

// ---- model and planner ----

#[test]
fn the_model_starts_cautious_and_never_gets_less_careful_about_your_files() {
    let scorer = Scorer::new(None);
    let rates = HashMap::new();
    let safe = cand("s", Tier::Safe, vec![], 1_000_000, "cache.x");
    let yours = cand("y", Tier::Yours, vec![], 1_000_000, "detect.large-old");
    assert!(scorer.regret(&safe, &rates) < 0.2);
    assert!(scorer.regret(&yours, &rates) >= 0.5);
    // Teach it that "yours" things are always fine to delete: the clamp still holds.
    let mut learner = Scorer::new(None);
    let rec = DecisionRecord { v: 1, day: "2026-01-01".into(), rule_id: "detect.large-old".into(), tier: Tier::Yours, size_bucket: 9, age_bucket: 12, git: "notRepo".into(), outcome: Outcome::Deleted, app_version: "t".into() };
    learner.retrain(&vec![rec.clone(); 200]);
    assert!(learner.regret(&yours, &rates) >= 0.5);
    assert_eq!(learner.model.trained_on, 200);
    let restored = DecisionRecord { outcome: Outcome::Restored, ..rec };
    assert!(restore_rates(&[restored])["detect.large-old"] > 0.99);
}

#[test]
fn the_planner_uses_safe_items_first_and_widens_only_when_it_must() {
    let scorer = Scorer::new(None);
    let items = vec![cand("rb", Tier::Rebuildable, vec![], 10_000_000_000, "detect.node_modules"), cand("safe", Tier::Safe, vec![], 2_000_000_000, "cache.x"),
                     cand("yours", Tier::Yours, vec![], 50_000_000_000, "detect.large-old")];
    let rates = HashMap::new();
    let small = plan(&scorer, &rates, 1_000_000_000, &items, &[Tier::Safe, Tier::Rebuildable]);
    assert_eq!(small.item_ids, vec!["safe"]);
    let bigger = plan(&scorer, &rates, 5_000_000_000, &items, &[Tier::Safe, Tier::Rebuildable]);
    assert!(bigger.reaches_goal && bigger.item_ids.contains(&"rb".to_string()) && !bigger.item_ids.contains(&"yours".to_string()));
    let huge = plan(&scorer, &rates, 100_000_000_000, &items, &[Tier::Safe, Tier::Rebuildable]);
    assert!(!huge.reaches_goal && huge.shortfall > 0, "never reaches for yours on its own");
}
