# Hyperframes Composition Brief: Room

## Objective
Create a short launch-style brag video for Room, in the Cinnabar design language.

## Output
- Composition directory: `brag-output/composition/`
- Rendered video: `brag-output/brag.mp4`
- Format: landscape, 1920x1080
- Duration: 22.4s

## Source Material
- Project root: /Users/mrtag08/Projects/galaxys25/Room
- Primary files read: README.md, docs/cinnabar-glass.md, Brand/README.md, Sources/RoomCore/DesignTokens.swift, Sources/Room/Screens/* (copy), Sources/RoomCore/Catalog.swift (item titles)
- Product name: Room
- Tagline / strongest claim: "Room makes space on your Mac, and tells you exactly what it will do first."
- Key UI moments to recreate: Review list with reasons, git guard row, action bar + Delete, liquid tank, undo vault
- Copy that must appear verbatim:
  - Your Mac is full.
  - Room tells you first.
  - Room can free 38.4 GB without touching your files.
  - It is not backed up
  - Changed your mind? Undo here.
  - Anything of yours that you delete waits here for 7 days.
  - Built on Cinnabar

## Creative Direction
- Tone preset: polished
- Creative direction: quiet premium product film in Cinnabar
- Angle: Room tells you first. Trust is the brag: it shows its work, waits for approval, and keeps an undo vault.
- Hook: "Your Mac is full." with the sindoor tank nearly full.
- Outro / punchline: doorway mark, "Makes space on your Mac. Tells you first."
- Avoid: generic SaaS language, abstract filler, gradients and glows on content (Cinnabar rule: flat only; glass only on action bar/toast), more than one sindoor focal point per view, recolouring the doorknob dot.

## Visual Identity
- Background: #0B0B0D (Obsidian). Cards #16161A / #1A1A1F. Hairlines #232328, strong #2A2A30.
- Text: #F7F7F5, soft #D4D4D8, muted #A1A1AA, faint #8A8A93
- Accent: #F2542D sindoor (text on dark #FF7A57). State: success #22C55E, pending #EAB308.
- Display font: Parkinsans 700 (tracking -0.03em), headings 600. Data: JetBrains Mono 400/500. Fonts shipped in `assets/fonts/` (from Sources/Room/Resources/Fonts).
- Radius scale 6/12/16/20/24. Hairline 1px. Ease cubic-bezier(.2,0,0,1), base 0.2s, panel 0.3s.
- Logo: `assets/brand/room-mark-dark.svg`, `room-lockup-dark.svg`.

## Storyboard
Use `brag-plan.md` as the contract.
1. Hook: 0-4.0s: "Your Mac is full." + sindoor tank 94%
2. Review/approve/clean: 4.0-13.1s: recreated Room window, rows, ticks, Delete, 31.2 GB back
3. Undo vault: 13.1-17.5s
4. Outro: 17.5-22.4s: doorway mark, wordmark, tagline

## Audio
- Audio role: warm bed with sparse professional accents
- Music: assets/music/happy-beats-business-moves-vol-12-by-ende-dot-app.mp3, volume 0.30, fade out last 2s
- Music cue guidance: bundled preset (assets/music/...music-cues.json). Strong cues 8.74, 13.11, 18.56. Beat grid for rows/ticks.
- Audio-reactive treatment: subtle; `assets/audio-data.js` (bass/treble/amp per frame at 30fps) drives tank liquid lift and doorknob halo. No visualizer graphics.
- SFX: clicks on ticks and Delete/Undo, card sound on first row, soft bong on payoff, drop at scene 3, one bell for the logo. Low HF risk, 0.45-0.7 volume.
- Audio files copied to `brag-output/composition/assets/`.

## Hyperframes Instructions
Use hyperframes-core, -animation, -creative, -keyframes, -cli. Run `npx hyperframes check` before render. Keep all text readable; show real Room copy and UI. Keep within 22.4s.
