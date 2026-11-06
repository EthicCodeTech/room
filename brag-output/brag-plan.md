# Brag Plan: Room

## What is this app?
Room is a macOS 26 disk-space tool that finds what is safe to remove, shows exactly what it will do and why, and cleans only after you approve, with every removal going to a 7-day undo vault first.

## The angle
"Tells you first." Every other cleaner is a button that deletes. Room's brag is trust: it shows its work (ranked items, a reason for each, a git guard on unpushed work), waits for your yes, and keeps an undo vault. The video is the app's own calm confidence, styled in Cinnabar (Obsidian + one sindoor dot, flat graphite, hairlines, Parkinsans + JetBrains Mono), not a hype reel.

## Hook (first 2-3 seconds)
"Your Mac is full." Big Parkinsans on Obsidian beside Room's liquid tank, nearly full of sindoor liquid, sloshing once. Mono readout: 4.2 GB free.

## Key moments (the middle)
- Review rows arrive one by one, each with a mono reason line and a tier chip. A fourth row is flagged by the git guard: "It is not backed up" and stays unticked.
- A cursor ticks three safe rows, the glass action bar rises, the sindoor "Delete 3 items" button is clicked.
- The tank drains, the counter lands "31.2 GB back."
- Undo vault: "Anything you delete waits here for 7 days." Cursor hits Undo and a row slides back.

## Outro / punchline
Doorway mark with its single sindoor doorknob, "room" wordmark, then: "Makes space on your Mac. Tells you first." Small mono: "Built on Cinnabar · EthicCode".

## User flow worth showing
Review (see items + reasons) → approve (tick, Delete) → space returns, vault holds the undo.

## Tone
- Preset: polished
- Creative direction: quiet premium product film in Cinnabar (flat Obsidian/Graphite, hairlines, one sindoor accent)
- Interpretation: few scenes, long holds, soft crossfades, one accent color, no jokes. Confidence through restraint.

## Format: landscape — 1920x1080
## Duration: 22.4s

## Visual identity (from the project: Sources/RoomCore/DesignTokens.swift, docs/cinnabar-glass.md)
- Background: Obsidian #0B0B0D
- Cards: Graphite #16161A / raised #1A1A1F, hairline #232328 (strong #2A2A30)
- Accent: Sindoor #F2542D (text on dark #FF7A57), used for one primary thing per view (90/10)
- Text: Paper #F7F7F5, soft #D4D4D8, muted #A1A1AA
- State colours only for state: success #22C55E, pending #EAB308
- Display font: Parkinsans (700 display, 600 headings)
- Body font: Parkinsans 400/500; data in JetBrains Mono
- Strongest visual element: the liquid tank in sindoor; the Review list; the doorway mark
- Cinnabar rules kept: flat surfaces, borders over shadows, glass only on the control layer (action bar, toast), never recolour the dot

## Share copy (draft)
Room makes space on your Mac and tells you exactly what it will do first. Every removal goes to a 7-day undo vault. Built on Cinnabar.

## Audio direction
- Role: warm bed with sparse professional accents
- Music: happy-beats-business-moves-vol-12 (polished/cinematic fit, 109.96 BPM)
- Music treatment: starts at 0s, volume 0.30, 0.6s fade-in, fade out across the last 2s
- Music cue guidance: bundled preset read (vol-12). Strong cues used: 8.74s (headline swap), 13.11s (Review to Vault), 18.56s (logo lands). Beat grid for row reveals: 4.91, 5.34, 6.00, 6.56; cursor ticks at 9.29, 9.83, 10.37.
- Audio-reactive treatment: subtle; bass lifts the tank liquid and logo glow slightly, treble adds a soft sindoor halo on the doorknob. No waveform or equalizer visuals.
- SFX posture: sparse, motion-matched, low-HF-risk picks (clicks, soft impacts, one bong)
- Audio-coupled moments: row arrivals, three ticks, Delete click, payoff, Undo click, logo landing
- Restraint rule: nothing loud, no stacked hits, music never above 0.35

## Storyboard

### Scene 1 — Hook — 4.0s
Obsidian. Left: "Your Mac is full." (settles by 0.9s, holds to 3.6s). Right: the tank, a rounded hairline vessel with sindoor liquid at 94%, one slosh, mono "4.2 GB free" beneath.
Sequential/interaction: none
Audio intent: quiet, uncomfortable stillness under a warm bed
Audio-coupled idea: tank slosh breathes with bass
Music: bed fades in
Transition mood: soft → Scene 2

### Scene 2 — Review → approve → clean — 9.1s (4.0 to 13.1)
Left column headline "Room tells you first." (holds to 8.3), then at 8.74 swaps to "You approve. Then it cleans." Right: a Room window recreated in Cinnabar. Top: "Room can free 38.4 GB without touching your files." Four rows slide in one by one: Xcode DerivedData 14.2 GB, Simulator caches 9.8 GB, Docker build cache 7.1 GB, and a flagged "Old project · node_modules" with "It is not backed up: 2 unpushed commits". Cursor ticks the first three, the glass action bar rises, cursor clicks "Delete 3 items". Rows collapse, toast "31.2 GB back." with mono counter.
Sequential/interaction: yes. Rows at 4.91 / 5.34 / 6.00 / 6.56 (rows are UI, readable text held in headline); cursor ticks at 9.29 / 9.83 / 10.37; Delete click at 11.46.
Audio intent: precise, tactile, satisfied
Audio-coupled idea: card sound on first row, tick clicks, click on Delete, soft bong on payoff
Transition mood: soft crossfade → Scene 3

### Scene 3 — Undo vault — 4.4s (13.1 to 17.5)
Left headline "Nothing is lost for 7 days." Right: vault card listing the three removed items with sizes and "7 days left". Cursor presses Undo on "Simulator caches" and it slides back with a sindoor dot ("restored").
Sequential/interaction: yes, one simulated click
Audio intent: reassurance
Transition mood: slow crossfade → Scene 4

### Scene 4 — Outro — 4.9s (17.5 to 22.4)
Doorway mark draws in, sindoor knob lands at 18.56. Wordmark "room". "Makes space on your Mac. Tells you first." then mono "Built on Cinnabar · EthicCode". Hold, then fade with the music.
Audio intent: warm landing, then silence
Audio-coupled idea: single bell on the knob landing
Transition mood: fade out

**Music mood for this video:** warm, clean, polished
**Audio summary:** Warm bed from 0s, one precise click rhythm through the approve flow, one bell on the doorknob, music fading out with the last frame.

## Music cue guidance
Track: vol-12, 109.96 BPM. Strong cues locked: 8.74, 13.11, 18.56 (each within 0.15s). Beat grid used for sequential row/tick reveals. Cues are timing hints only; readability wins.

## Voiceover script (portrait Reels cut, Kokoro af_heart, brag-reels-voice-v3.mp4)
- 0.0s: soft impact hit (hook sound)
- 0.5s: Is your Mac storage full again?
- 2.4s: Most cleaners just start deleting.
- 4.6s: Room shows you everything first. Every item, with a reason.
- 8.9s: You choose. Nothing is touched until you say so.
- 11.75s: Thirty one gigabytes, back.
- 13.6s: Everything waits in an undo vault. Changed your mind? One tap.
- 19.0s: That's Room, by Ethic Code.
- 20.75s: Try it now. (on screen, not spoken: ethiccode.in/room)
Music ducks to 50% under the voice.
