# Room: handover document

Written 8 November 2026 for the next agent (another Claude account) taking over this repository. It is meant to be read top to bottom once, then used as a reference. Everything stated here was true when it was written; where something is unverified it says so.

## 0. The 60-second version

- **Room** is a disk-space cleaner by **EthicCode**, built on the **Cinnabar** design system. It finds what is safe to remove, shows exactly what it will do, cleans only after approval, and keeps anything that might be the user's own in a 7-day **undo vault**.
- **macOS app**: done and released as **v1.0.0** (GitHub release, website page). Later improvements (external-drive vault, plain-words assistant) are on branch `v1.2-dev`, **not yet released**.
- **Windows app**: built from scratch this session (Rust engine + Tauri 2 shell + plain HTML/CSS/JS UI), built by GitHub Actions, tested by two friends on real PCs. It is **unsigned**, so Smart App Control blocks it on some PCs.
- **Microsoft Store**: the app "Room: Disk Cleaner" was submitted as an MSIX and is **in certification** at Partner Center (as of 2026-11-08). The Store signs MSIX packages, which is the intended fix for Smart App Control.
- **Nothing is waiting to be committed.** All work is committed on branch `v1.2-dev` of `EthicCodeTech/room`, and the website repo is committed and pushed. `main` of the Room repo is untouched since the v1.0.0 universal build.
- **Don't** merge `v1.2-dev` to `main`, cut a release, or change the website without the user saying so. See section 10 for what is waiting on the user.

## 1. People, places, repos

| Thing | Where |
| --- | --- |
| The user | Owner of EthicCode (India). Communicates casually, sometimes in Hinglish with friends. Wants plain, friendly, direct answers. Tests on a real Mac and, via friends or their own HP laptop, on Windows. |
| Room repo (public) | `github.com/EthicCodeTech/room`, local `/Users/mrtag08/Projects/galaxys25/Room`. Working branch `v1.2-dev`. `main` = v1.0.0 universal build. |
| Website repo | `github.com/EthicCodeTech/ethiccode.in`, local `/Users/mrtag08/Projects/ethiccode.in`. Static site built by `scripts/build.js` from `src/` into `public_html/`. **Pushing `main` deploys** (Cloudflare, live in 1 to 3 minutes). |
| Room page | `https://ethiccode.in/room/` (source `src/apps/room/index.html`), privacy page `https://ethiccode.in/room/privacy/` (source `src/apps/room/privacy/index.html`). |
| The user's local file server | `http://10.0.0.109:6903` (Flask, source in `~/Downloads/SERVER/server.py`, runs on the user's Mac). `POST /upload` with form field `file`; no login; never overwrites (adds `_1`, `_2`). Used to hand test builds to friends. |
| Scratch folder | `/private/tmp/claude-501/-Users-mrtag08-Projects-galaxys25/<session>/scratchpad` (may not exist for you). |

Standing rules from the user and the environment (follow them):
- Global `~/.claude/CLAUDE.md`: **credentials, tokens and connection strings go in `.env` files with a `.gitignore` entry**, never hardcoded or committed. There are no secrets in either repo today.
- Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` (use your own model's line if your instructions say otherwise).
- Never move the user's real mouse; do not click macOS permission dialogs; do not enter passwords or credentials; do not change system settings.
- Always use `</dev/null` on `gh` commands (one hung once waiting on stdin).
- The user decides about anything outward-facing: pushing to `main`, releases, publishing, spending money, deleting files on their server.
- Write plainly. No em dashes in product copy. Never the word "AI" in user-visible product text on the Mac assistant.

## 2. What Room is

Room finds what is safe to remove on a computer (caches, temp files, build output, old installers, stale `node_modules`, simulators), shows a size map of everything else, and cleans only after the user approves.

Core ideas, identical on both platforms:
- **Three risk tiers.** `safe` (caches apps rebuild by themselves), `rebuildable` (not user data, but costs time or bandwidth to get back), `yours` (might be the user's work; never touched without a named confirmation, never preselected).
- **Undo vault.** Items that might be the user's (installers, zips, anything `yours`) are moved, not deleted, and wait 7 days. Space returns only when the vault is purged. Caches are deleted directly because they come back by themselves. A setting ("Keep rebuildable folders in the vault too") also vaults `node_modules` and similar.
- **Safety rails.** Path allow-lists (system folders refused), links/junctions never followed, a **git guard** (a project with uncommitted or unpushed work is flagged and needs an extra confirmation), cloud-synced folders treated as `yours`.
- **Regret model.** A tiny logistic regression (11 features) ranks suggestions. It starts from hand-set weights, learns only on the device from the user's deleted/declined/restored choices, and can make Room more cautious about `yours` items but never less. The planner ("How much room do you need?") picks the lowest-regret set that reaches a goal, safe items first.
- **Privacy.** No accounts, no telemetry. The anonymized decision log (rule id, rough size/age buckets, outcome; no paths or names) stays on the device and nothing uploads it.
- **Brand.** Cinnabar tokens: sindoor `#F2542D`, obsidian `#0B0B0D`, Parkinsans (display), JetBrains Mono (numbers). The logo is a door with a sindoor knob on a 48-unit grid.

Why it exists as a product: friendly, trustworthy alternative to aggressive "cleaner" tools. Positioning line: "Know what it will do before it does it."

## 3. Repository layout

```
Room/
  Package.swift, Sources/, Tests/, scripts/, Brand/   macOS app (Swift)
  windows/                                            Windows app (Rust + web UI)
    crates/room-core/                                 engine, portable, tested on any OS
    app/src-tauri/                                    Tauri 2 shell, NSIS installer, MSIX manifest
    app/ui/                                           interface (no build step)
  docs/                                               plans and design notes (this file lives here)
  .github/workflows/windows.yml                       Windows CI
  dist/                                               build output (gitignored)
```

Docs in `docs/`: `HANDOFF.md` (this), `v1.2-plan.md`, `windows-plan.md`, `how-it-works.md`, `cinnabar-glass.md`, `screenshots/`.

## 4. macOS app: what exists

Swift/SwiftUI, macOS 26 or later, SwiftPM. Targets: `RoomCore` (engine), `Room` (app), `RoomCoreTests` (Swift Testing). Xcode 27 toolchain required (the Command Line Tools alone lack the SwiftUI macro plugin).

**Commands** (run in `Room/`):
- `scripts/test.sh` runs the tests (**129 tests** at last run, all passing).
- `scripts/bundle.sh release` builds `dist/Room.app`, **universal (arm64 + x86_64)** for release, native for debug. Ad-hoc signed.
- `scripts/package.sh` builds `dist/Room-1.0.0.dmg` and `.zip` (dmg via `dmgbuild` in the venv `.build/dmgvenv`, settings in `scripts/dmg-settings.py`).
- Debug-only dev switches (`Sources/Room/Dev.swift`): `ROOM_SECTION`, `ROOM_APPEARANCE`, `ROOM_DEV_MAPSAMPLE`, `ROOM_DEV_SETTINGS`.

**Screens**: Overview (free-space tank, goal planner), Review (tiered suggestions, details, confirm sheet that splits "removed now" from "vaulted"), Map (treemap), Vault, Growth, Ask (assistant), Settings. Menu-bar icon.

**Branding and installer (done)**: icon built with an Icon Composer `.icon` bundle compiled by `actool` (absolute path required) with light and dark appearances (`Brand/Room.icon`); menu bar template icons; DMG with an adaptive transparent background (1x/2x TIFF) and no readme inside; website favicons for light and dark.

**Vault (macOS)**: `Sources/RoomCore/Vault.swift`. Same-volume items are renamed into the vault (instant). **Items on an external drive stay on that drive** in a hidden `.Room-Vault` folder at its root (instant rename, no copy). If a drive is unplugged its batch stays listed ("not connected") until it returns; a read-only drive is never touched; there is a Trash fallback only when a drive cannot hold a vault. `DeletionPolicy.default(for:vaultRebuildable:)` decides direct delete vs vault.

**Assistant (macOS)** (`Sources/RoomCore/Advisor.swift`, `Assistant.swift`): three modes in Settings: Off, On-device (Apple Foundation Models, default), Claude (user's own Anthropic API key in the Keychain; only a redacted summary is sent). A layer called `Assistant` sits in front: it routes questions in code (off-topic, "largest", "what grew", "safe to delete"), gives the model a **plain-sentence fact sheet with no ids or byte counts**, cleans the output (ids to titles, raw bytes to "2.1 GB"), and falls back to the built-in answer if the output still looks like data. This fixed the real bug where the on-device model printed ids like `cache.gradle#089a2801` and answered "2+2" with an item dump.

**Gatekeeper**: the Mac app is ad-hoc signed and **not notarized**, so users must do Privacy & Security -> Open Anyway once. The website and README document this with real screenshots.

**Releases**: v1.0.0 on GitHub (dmg + zip, SHA-256 in the notes). The tag was moved several times during the session (`git tag -f`, force-push the tag, `gh release upload --clobber`). The released build is the universal one **without** the external-vault and assistant fixes (those are on `v1.2-dev` only).

## 5. Windows app: what exists

**Stack and why**: Rust engine + Tauri 2 (WebView2) + plain HTML/CSS/JS UI, because Cinnabar is a web design system, the installer stays tiny (~1.5 MB setup, ~3.9 MB exe), and Rust suits fast filesystem work. The Mac keeps Swift; the two engines are kept honest by shared ideas (same tiers, prior weights, vault design) and by tests. Decision made by the user.

**Engine** `windows/crates/room-core/` (17 tests; run with `cargo test -p room-core`, also runs on macOS):
- `model.rs` (tiers, candidates, deletion policy), `catalog.rs` + `catalog-windows.json` (24 rules incl. browsers, Discord, Slack, VS Code, Spotify, shader caches, npm/pip/uv/NuGet/Gradle/Cargo/Unity caches, Premiere/DaVinci/Lightroom caches, Hugging Face, Recycle Bin), `discover.rs` (rules plus detectors for stale `node_modules`, old installers, zip duplicates, large old files; cloud-synced folders raised to `yours`; "app is running" guard holds a rule back), `scan.rs` (measure, progress counters and stop flag; **uses the size from the directory listing, no per-file open**; exact size only for compressed/sparse files), `map.rs` (one-walk nested tree, drives, places), `vault.rs` (**per-drive vault** `X:\.room-vault`, offline-drive handling, same logic as Mac), `cleaner.rs` (confirmations, git guard, minimum-age protection, Recycle Bin command), `scorer.rs`/`planner.rs`/`decision.rs` (port of the Mac model), `safety.rs` (string-based Windows path rules, testable anywhere), `platform.rs` (the only Windows-specific code: cloud placeholders, reparse points, allocated size, volume roots, Recycle Bin, hidden folders), `git.rs`.
- Catalog rules carry `personas` (work types) and `guards.appRunning`. Rules with no persona apply to everyone; if the user chose work types, persona rules switch on only for those.

**App shell** `windows/app/src-tauri/src/lib.rs`: Tauri commands (`scan`, `make_plan`, `preview_clean`, `clean`, vault commands, `map_tree`, `map_cancel`, `known_places`, `list_drives`, `set_window_theme`, `reveal`, `save_settings`). Emits `scan-progress`, `clean-progress`, `map-progress`. Applies **Mica** (Windows 11) or acrylic (Windows 10) matching the app theme via `window-vibrancy`, and re-applies when Windows switches light/dark. Folder picker via `tauri-plugin-dialog`.

**UI** `windows/app/ui/` (`index.html`, `app.css`, `app.js`, `icons.js`, `personas.js`, `mock.js`): Windows 11 structure (collapsible navigation pane, inset rounded content sheet, 8/14/18/20 px radii, Fluent motion) in Cinnabar colours and type. Screens: Overview (animated water-tank free-space card, goal planner), Review (filter, details card that closes on outside click, confirm dialog with explicit ticks for `yours` and unbacked git repos), Map (nested **treemap** with folder headers, merged "N smaller items" block, **list view**, drive free-space bar, Refresh, Stop, "Choose a folder", quick places, live scan progress), Vault, Settings, and a first-run **work-type picker** (13 multi-select cards with Lucide icons). `mock.js` is a pretend backend loaded only when not running inside Tauri, so the UI can be previewed in any browser: serve `windows/app/ui` with `python3 -m http.server`.

**Work types** (ids in `personas.js` match catalog `personas`): dev, mobile, gamedev, data, video, audio, photo, design, 3d, gaming, trading, streaming, everyday.

**Installer (NSIS)**: `windows/app/src-tauri/installer/` has a copy of Tauri's stock template with Room branding (dark Cinnabar welcome/finish/header pages, Room wording, `MUI_FORCECLASSICCONTROLS` so finish-page check box labels are readable), `hooks.nsh` (the uninstaller **never deletes the undo vault**; it tells the user where it is), and `make-assets.py` (regenerates `sidebar.bmp` 164x314 and `header.bmp` 150x57; needs Pillow and `rsvg-convert`). Per-user install, no admin prompt. Config keys in `tauri.conf.json` are exact: the schema rejects unknown fields. **Not yet visually verified on a real PC** beyond the user reporting that the last page text was black (fixed with classic controls; re-check). The installer sidebar still has a thin orange left edge (the user asked for it to be removed only from the Store images).

**CI** `.github/workflows/windows.yml` (push to `main`/`v1.2-dev` touching `windows/**`, plus manual): `test` job on `windows-latest` (cargo test + clippy `-D warnings`), then `build` for **x64** (`windows-latest`) and **ARM64** (`windows-11-arm`, `continue-on-error`). Each produces `Room-1.2.0-<arch>-setup.exe`, `-portable.exe`, `SHA256SUMS`, and the **MSIX** (`Room-1.2.0-<arch>.msix`, built with `makeappx`). Artifacts named `room-windows-x64` and `room-windows-arm64`. Download with `gh run download <id> --dir dist/windows </dev/null`. Wait for a run with `gh run watch <id> --exit-status` in the background; do not poll.

**Windows facts learned the hard way**: `File::open` cannot open a directory on Windows (use the `filetime` crate in tests); `cargo check --target x86_64-pc-windows-msvc` type-checks the engine on a Mac but the Tauri app's build script needs `llvm-rc`, so the full Windows build happens only in CI; do not rely on the browser view-transition API for navigation (it can stall; navigation now never depends on it); per-file `GetCompressedFileSizeW` made large scans very slow, which is why sizes now come from the directory listing; hundreds of tiny treemap blocks need merging or the map becomes dots.

## 6. Microsoft Store

- **Partner Center product**: "Room: Disk Cleaner" (the name "Room" was taken). Store ID `9PDVVQ5J76VD`, link `https://apps.microsoft.com/detail/9PDVVQ5J76VD`.
- **Package identity** (public, used in `windows/app/src-tauri/msix/AppxManifest.xml`): Name `EthicCodeTechnologies.RoomDiskCleaner`, Publisher `CN=DE45280B-BB51-4073-8EE8-7B6468AC817A`, PublisherDisplayName `EthicCode Technologies`, PFN `EthicCodeTechnologies.RoomDiskCleaner_kyg14ayjf3zmr`.
- **Submitted**: x64 and ARM64 `.msix` (version `1.2.0.0`), category Utilities + tools, age rating all ages (IARC 3+), free, Windows 10/11 Desktop only. Restricted capabilities declared: `runFullTrust` and `unvirtualizedResources` (the latter with `desktop6:FileSystemWriteVirtualization=disabled` so Windows does not redirect Room's deletes in other apps' AppData folders to a private copy). Justification text for both was entered (500-character limit per box). Store listing text, five screenshots (sample data, generated from the UI preview), poster and box art were provided to the user (`dist/store-assets/`, `dist/store-screenshots/`, both gitignored).
- **Status**: In certification (usually a few hours, up to 3 business days). **Risks**: Microsoft may question `unvirtualizedResources` (if so remove it and find another way to clean other apps' caches), and may reject the full-trust justification at first. An unsigned MSIX cannot be installed locally without Developer Mode.
- **Why the Store**: Smart App Control only allows apps signed by a trusted CA or known to Microsoft, and there is no per-app bypass. The Store signs MSIX packages itself, so no certificate purchase is needed. Whether Smart App Control then lets a Store-signed Win32 package run is **expected but not yet confirmed**.
- **Privacy policy** (required by the Store): `https://ethiccode.in/room/privacy/` (live).

## 7. Distribution state

| Channel | State |
| --- | --- |
| Mac download | GitHub release v1.0.0 (universal dmg + zip, notarization not done) |
| Website page | `ethiccode.in/room`, Mac only; says "Apple silicon & Intel", 4.5 MB. **No Windows download button yet.** |
| Windows direct download | None public. Test builds go to the user's local server and to friends by hand. Unsigned. |
| Windows Store | In certification |
| Privacy page | Live |

## 8. Decisions already made (do not reopen without the user)

1. Windows = Rust + Tauri (chosen over Swift-on-Windows and WinUI).
2. Each platform follows its own OS look in Cinnabar's colours and type (Liquid Glass on Mac, Windows 11 Mica/Fluent on Windows).
3. **No on-device AI model on Windows.** The user briefly asked for it, then said "nah, don't". The unfinished work (a `candle`-based runner and a Rust port of the assistant) was reverted and deleted. The Mac assistant stays as is.
4. Cloud placeholders and offline files are handled by detection, not treated as a blocker.
5. Store route = MSIX via Partner Center (not "EXE or MSI app", which would need our own certificate).
6. Mac and Windows should be treated as one product for v1.2 ("for everyone").

## 9. Plans and ideas on file

- `docs/v1.2-plan.md`: Room 1.2 for Mac and Windows. **First-run work-type picker is built on Windows, not on the Mac.** Mac still needs it, plus catalog v2 (shared signed JSON with per-platform paths and personas), auto-update (Sparkle on Mac), accessibility pass, a shared `personas.json` feeding both OOBE screens.
- `docs/windows-plan.md`: the Windows plan. Not yet built from it: elevated helper for admin-only rules (Windows Update cache, `Windows.old`; ask for UAC only at that moment, a separate small elevated exe with whitelisted commands), WSL2/Docker VHDX compaction, Restart Manager hints ("close Teams, then try again"), MFT-based fast map.
- Correction on record: emptying the user's own Recycle Bin does **not** need admin rights; the app already does it as a normal user.
- Feedback from the user's two Windows testers is implemented except: **Mac map has the same 60-item cap and no list view** (the Windows fixes should be ported), and the Windows installer art has not been re-checked after the finish-page colour fix.

## 10. Open items, waiting on the user or unverified

1. **Smart App Control** blocks unsigned Windows builds. Fix path: the Store (in progress) and/or a code-signing certificate (RSA, not ECC). Azure Artifact Signing lists only US/Canada/EU/UK organisations and US/Canada individuals, so India is probably not eligible (verify).
2. **Store certification outcome** (section 6). If rejected or questioned, adjust the manifest and re-upload from CI artifacts.
3. **Merge `v1.2-dev` into `main` and release** (suggest v1.0.1 for Mac: external-drive vault, assistant fix). Not done; the user must say so. When releasing, update the checksums in the release notes.
4. **Website**: add the Windows download (Store link, plus the direct installer once signing exists) and refresh copy. Do not advertise the unsigned installer publicly.
5. **Apple notarization** (needs an Apple Developer ID, about 99 USD/year) would remove the Open Anyway step. Not purchased.
6. **LICENSE**: none chosen; the repo is public.
7. **Public commit email**: older commits carry the user's personal address; the user was asked whether that is acceptable and has not answered.
8. **Unverified on real hardware**: Intel Macs; the Mac dmg installer window and Dock icon in dark mode; Windows Mica rendering details; the NSIS installer's look and behaviour after the last two changes; whether Store-installed Room can actually delete other apps' AppData files (this is the key test for `unvirtualizedResources`).
9. **Claude model id**: `ClaudeAdvisor` in `Sources/RoomCore/Advisor.swift` hard-codes `claude-sonnet-5`. Valid ids may differ (for example `claude-sonnet-5-5`); never tested with a real key. Do not change without testing.
10. The user's friends reported earlier that the scan of a large Windows drive was slow; the fix (no per-file open, live progress, Stop) shipped in the last build but **real timings were not reported back**.
11. `brag-output/share-copy-reels.txt` in the Room repo is an unrelated untracked file; leave it alone.

## 11. How to continue, practically

```bash
cd /Users/mrtag08/Projects/galaxys25/Room
git switch v1.2-dev                       # all current work
scripts/test.sh                           # Mac: 129 tests
(cd windows && cargo test -p room-core)   # Windows engine: 17 tests
# Preview the Windows UI anywhere:
(cd windows/app/ui && python3 -m http.server 8765)   # then open http://127.0.0.1:8765/
# Rust toolchain on this Mac: export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
# Trigger a Windows build: push to v1.2-dev (paths windows/** or the workflow file), then:
gh run list --workflow=windows.yml --branch v1.2-dev --limit 1 </dev/null
gh run download <id> --dir dist/windows </dev/null
```

Mac release recipe used repeatedly: `scripts/package.sh`, commit, `git tag -f -a -m "Room 1.0.0" v1.0.0`, push main and force-push the tag, `gh release upload v1.0.0 dist/Room-1.0.0.dmg dist/Room-1.0.0.zip --clobber --repo EthicCodeTech/room </dev/null`, then edit the notes with fresh SHA-256 values.

Mac gotchas learned: `actool` needs an absolute path to the `.icon` bundle; a dynamic light/dark app icon needs **group-level** `hidden-specializations` in the Icon Composer document (layer-level ones are ignored); asset-catalog dark appearances do not work for macOS app icons; detach stale mounted volumes (`hdiutil detach -force`) before capturing a new dmg or you will screenshot the old one; real project names must not appear in sample data or tests in the public repo.

Website deploy: edit under `src/apps/room/`, `git push origin main` in `/Users/mrtag08/Projects/ethiccode.in`, and poll the live URL for the new text.

## 12. Test machines and hand-off of builds

- The user's Mac runs everything on macOS 26 (Tahoe, Darwin 27).
- Windows testers: two friends on real PCs (one HP laptop, Windows 11 x64). They test unsigned builds with Smart App Control off or in evaluation mode.
- To hand a build to testers, upload to the user's local server (section 1) or send the file directly. CI artifact names: `Room-1.2.0-x64-setup.exe`, `Room-1.2.0-x64-portable.exe`, and the `.msix` files for the Store.
