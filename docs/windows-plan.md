# Room for Windows: plan

Status: **in progress.** Decided: Rust engine + Tauri 2 shell (option A below), styled to match Windows 11 with the Cinnabar design system. A first build of the engine and app exists in [`windows/`](../windows). Target: ship together with Room 1.2 (see [v1.2-plan.md](v1.2-plan.md)).

**Design direction (decided):** each platform follows its own OS look, in Cinnabar's colours and type. On the Mac that is Liquid Glass. On Windows it is Windows 11: Mica backdrop, a left navigation pane, 4 px controls and 8 px surfaces, a 2 px focus ring, light and dark following the system. Sindoor stays the accent, Parkinsans the display face, JetBrains Mono the numbers.

**Risk call (decided):** cloud placeholders and offline files are handled by detection (they count as nothing and are never deleted blindly), not treated as a blocker. The two engines are allowed to differ in code; the shared catalog, fixtures and record schema keep them honest.

## 1. Goal and non-goals

Same promise as the Mac app: **find what is safe to remove, show exactly what will happen, clean only after approval, keep your own files in a 7-day undo vault.**

Non-goals for 1.2: registry cleaning, "optimizers", startup managers, anything that needs the user to trust us with system files. Room stays a disk-space tool.

Supported: Windows 11, and Windows 10 22H2. x64 and ARM64 builds.

## 2. The big decision: how to build it

| Option | What it is | For | Against |
| --- | --- | --- | --- |
| **A. Rust engine + Tauri 2 shell (recommended)** | New engine in Rust, UI in web tech inside WebView2, styled with the Cinnabar web tokens | Cinnabar is already a web design system. Small installer (about 5 to 10 MB). Rust is the right tool for fast, safe filesystem code. ARM64 works | Two engines (Swift on Mac, Rust on Windows) can drift apart |
| B. Swift on Windows + WinUI | Reuse `RoomCore` as is | One engine | `RoomCore` leans on Darwin APIs (`fstat`, bulk directory calls, Keychain, CryptoKit, volume IDs). WinUI bindings for Swift are young. Highest risk |
| C. C# / WinUI 3 or WPF | Fully native Windows app | Best Windows feel | Third codebase and a third language to staff |

**Recommendation: A**, with three rules that stop the two engines drifting apart:

1. **One catalog.** Move the rule catalog out of Swift source into a signed JSON file that both apps read (schema in section 5). Today the 18 rules are Swift literals.
2. **One set of conformance fixtures.** A folder of sample file trees plus the expected candidates, tiers and plans. Both engines must pass the same fixtures in CI.
3. **One decision-record schema** (the anonymized learning record). Same fields on both platforms.

Revisit in 1.3: if the Rust engine proves solid, the Mac app can adopt it through a Swift binding and we go down to one engine.

## 3. What carries over, and what changes

| Mac | Windows |
| --- | --- |
| Tiers: safe / rebuildable / yours | Same, unchanged |
| Regret scorer (logistic regression) | Port as is (about 100 lines). Same prior weights and same one-way "yours never gets less cautious" rule |
| Undo vault: same-volume rename into the app folder, hidden `.Room-Vault` on external drives | **Per-drive vault** `X:\.room-vault` on every drive, using `MoveFileExW` (an instant rename on the same volume). Hidden and marked not-content-indexed. Recycle Bin only as a last resort |
| Git guard | Same logic, shelling out to `git` |
| Path safety allow-list | New Windows list (section 4) |
| Liquid tank follows tilt (Apple silicon sensor) | `Windows.Devices.Sensors.Accelerometer` where present (many 2-in-1s). Still water elsewhere |
| Cinnabar Glass (Liquid Glass) | Mica / Acrylic backdrop in WebView2 plus the same Cinnabar tokens, light and dark |
| Gatekeeper warning | SmartScreen (section 8) |

## 4. Windows-specific engineering

**File locks.** Windows refuses to delete files that are open. Room never kills processes. A locked file is reported as "in use" and skipped. Where possible, use the Restart Manager API (`RmGetList`) to say *which app* holds it ("Close Teams, then try again"). Also add an "app is running" guard to rules, so Room won't suggest clearing a cache while its app is open (this is useful on the Mac too).

**Never follow reparse points.** Junctions, symlinks and mount points are not followed, the same as the Mac's "symlinks never followed". This is the Windows version of the rule that protects against deleting through a link into somewhere else.

**Cloud-synced folders (OneDrive, Dropbox, iCloud for Windows).** This is the biggest data-loss risk on Windows. Cloud-only "placeholder" files report a size but use no disk, and deleting one deletes it everywhere. Room must detect `FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS` / `OFFLINE`, never count placeholders as reclaimable, treat synced folders as `yours`, and say so: "Deleting this also removes it from OneDrive."

**Sizes on NTFS.** Count allocated size (`GetCompressedFileSize`, compression and sparse files), and de-duplicate hard links by file ID. `WinSxS` and installer caches are full of hard links, so naive scanning double counts them.

**Fast map.** Phase 1: parallel `FindFirstFileExW` with `FIND_FIRST_EX_LARGE_FETCH`, no elevation, one drive at a time. Phase 2 (optional, 1.3): read the NTFS MFT for near-instant maps, which needs administrator rights.

**Long paths.** Use the `\\?\` prefix everywhere internally and a long-path-aware manifest. Show normal paths in the UI.

**Elevation.** Room runs as a normal user. Rules needing admin (`C:\Windows\Temp`, Windows Update download cache, `Windows.old`) are marked "needs administrator" and run through a **separate small elevated helper** that accepts only the whitelisted command IDs (the same idea as the Mac's `CommandID` enum), one UAC prompt per cleanup. Never run the whole app elevated.

**Never touch:** `WinSxS` by hand (use the whitelisted `DISM /Online /Cleanup-Image /StartComponentCleanup`), `pagefile.sys`, `hiberfil.sys`, `System Volume Information`, `C:\Windows` except the whitelisted cache folders, the registry.

**Protected paths:** `C:\Windows`, `C:\Program Files*`, `C:\ProgramData` (except named caches), `C:\Users` as a whole, each user's profile root, `AppData` roots, and drive roots.

## 5. Catalog v2 (shared by both platforms)

```json
{
  "version": 2,
  "rules": [{
    "id": "cache.premiere-media",
    "title": "Premiere media cache",
    "why": "Previews and conformed audio. Premiere rebuilds them when you reopen a project.",
    "tier": "rebuildable", "regen": "hours",
    "platforms": ["mac", "win"],
    "paths": {
      "mac": ["~/Library/Application Support/Adobe/Common/Media Cache Files"],
      "win": ["%APPDATA%\\Adobe\\Common\\Media Cache Files"]
    },
    "action": "deleteContents",
    "guards": { "appRunning": ["Adobe Premiere Pro"] },
    "personas": ["video"],
    "minAgeMinutes": 1440
  }]
}
```

New fields versus today: `platforms`, per-platform `paths`, `guards.appRunning`, and `personas`. `tags` already exists. The file is signed with the pinned Ed25519 key the Mac app already supports (the key is not set yet, so signed updates are off today).

## 6. Windows rule list (first pass, each one verified on a real machine before it ships)

- **Everyone:** user temp (`%TEMP%`), thumbnail cache, Delivery Optimization cache, Recycle Bin (tier `yours`, shows size, never auto-selected), browser caches (Edge, Chrome, Firefox), Electron app caches (Teams, Slack, Discord, VS Code), DirectX shader cache, crash dumps.
- **Developers:** `node_modules` (existing detector), npm / pnpm / yarn / pip / uv / NuGet / Gradle / Cargo caches, Visual Studio `.vs` and `obj`/`bin` in stale projects, **Docker Desktop and WSL2 disk compaction**.
- **WSL2 / Docker:** deleting files inside Linux does not shrink `ext4.vhdx`. Offer "Compact" as a **whitelisted elevated command**: `wsl --shutdown`, then `Optimize-VHD` (Hyper-V available) or `diskpart` `compact vdisk`, with the sparse-disk option (`wsl --manage <distro> --set-sparse true`) offered as the long-term fix. Always show current vs expected size, and warn that it stops running distros.
- **System (admin):** Windows Update download cache, `Windows.old` (tier `yours`, with the 10-day rollback warning).

## 7. Architecture

```
room-core (Rust crate)        scanner, planner, scorer, vault, safety, catalog loader
  ├─ room-platform-win        FindFirstFileEx, MoveFileEx, Restart Manager, attributes, volumes
  ├─ room-platform-mac        (later, if the Mac app adopts it)
  └─ conformance/             shared fixtures run by both engines
room-win (Tauri 2)            UI shell, WebView2, Cinnabar tokens, OOBE, updater
room-elevated (small exe)     whitelisted admin commands only, launched through UAC on demand
```

## 8. Distribution and trust

- **Installer:** MSIX for the Microsoft Store (the Store signs it, so no SmartScreen warning for Store installs) plus a signed MSI / setup.exe for download, and a `winget` manifest.
- **Code signing:** an unsigned build triggers SmartScreen's "Windows protected your PC" screen, the same friction as the Mac's Open Anyway step. EV certificates no longer give instant reputation, so a plain OV certificate also starts with a warning that fades as downloads accumulate. Options to evaluate: Azure Trusted Signing (check that EthicCode's country and entity type are eligible), an OV certificate from a CA, or Store-only distribution. **Decision needed in week 1.** Costs and eligibility change, so verify at the time.
- **Updates:** Tauri's updater with signed update manifests. Updates are opt-in on first run.
- **Privacy:** same promises. No accounts, no uploads, optional local-only decision log.

## 9. Milestones (rough, one full-time engineer plus design help)

| Phase | Weeks | Outcome |
| --- | --- | --- |
| **W0: Spike** | 2 | Prove the risky parts: scan speed on a real 1 TB NTFS drive, vault move across three drives, OneDrive placeholder detection, Tauri shell with Cinnabar tokens and Mica. **Go / no-go on option A.** Decide signing route |
| **W1: Engine parity** | 3 to 4 | Catalog v2 + loader, scanner, planner, scorer, vault, safety, git guard. Conformance fixtures passing on Mac and Windows |
| **W2: App** | 3 to 4 | Overview, Review, Map, Vault, Settings, OOBE with the v1.2 work-type picker |
| **W3: Windows depth** | 2 to 3 | Elevated helper, WSL2 / Docker compaction, Restart Manager hints, OneDrive guard, long paths |
| **W4: Beta** | 2 to 3 | Signing and installers, winget, test matrix (Win 10 / 11, x64 / ARM64, HDD / SSD / external, OneDrive on/off), 20+ beta users |
| **Launch 1.2** | | Mac and Windows together |

Total roughly 12 to 16 weeks. This is an estimate, not a commitment. W0 will tighten it.

## 10. Risks

1. **Data loss through cloud placeholders or links.** Mitigation in section 4, plus conformance fixtures for each case.
2. **SmartScreen friction hurts first impressions.** Decide the signing route before beta.
3. **Two engines drift.** Shared catalog, fixtures and record schema; CI runs both.
4. **Antivirus flags bulk file moves.** Sign everything, avoid scripting engines, and move one folder at a time.
5. **WSL2 compaction harms a running distro.** Whitelist, confirm, and show the effect first.
