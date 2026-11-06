# Room for Windows

The Windows version of Room. Same promise as the Mac app: find what is safe to remove, show exactly what will happen, clean only after approval, and keep your own files in a 7-day undo vault.

```
crates/room-core   the engine (Rust): rules, scanner, scoring model, planner, undo vault, safety rails
app/src-tauri      the app shell (Rust + Tauri 2, WebView2)
app/ui             the interface (plain HTML, CSS and JS, no build step) in Windows 11 style with Cinnabar colours and type
```

Design: Windows 11 structure (Mica backdrop, navigation pane, 4 px controls, 8 px surfaces, a 2 px focus ring) in Cinnabar's palette and type (sindoor accent, Parkinsans headings, JetBrains Mono numbers). Windows 10 gets acrylic, anything else a solid background.

## Build

The Windows build runs in CI (`.github/workflows/windows.yml`) on real Windows machines, for x64 and ARM64. To build locally on Windows with Rust and Node installed:

```bash
cd windows/app
npm ci
npx tauri build
```

The engine and its tests run on any OS:

```bash
cd windows
cargo test -p room-core
```

To preview the interface without Windows or Rust, serve `app/ui` with any static server. It uses a pretend backend (`mock.js`) when it isn't running inside the app.

## Status

Built, not yet tested on real Windows hardware beyond CI. The first-run work-type picker, Overview, Review, Map, Vault and Settings are in. Not yet: the Ask screen (it needs an on-device model, which Windows doesn't ship), Docker/WSL2 disk compaction, administrator-only rules, signed installers. See [docs/windows-plan.md](../docs/windows-plan.md).
