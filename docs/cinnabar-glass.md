# Cinnabar Glass (proposed extension)

Room mixes macOS Liquid Glass with Cinnabar. This is a deliberate exception to Cinnabar 3.5 rule 2
("Flat only. No gradients, no glows") and to the "Borders over shadows" elevation rule. It is not part of the
published design system. Promote it into Cinnabar only if you want it there.

## Rules
1. **Content stays flat.** Cards, tables and text use Graphite, hairlines and sindoor exactly as specified.
2. **Glass is the control layer.** Navigation, the action bar, the inspector, dialogs, toasts and segmented
   controls float above content as glass. There must be real content underneath for it to refract.
3. **Sindoor tints glass only for the one primary action in a view.** The 90/10 rule still holds.
4. **Hairlines stay.** Glass edges keep a 1px `--line`, so depth still comes from borders more than shadows.
5. **Motion answers actions.** Glass morphs when state changes (selection moves, items appear). Nothing loops.
6. **Legibility first.** Text on glass sits on a `--graphite` backing at 55 to 78% opacity.

## What stays the same
Palette, type (Parkinsans, JetBrains Mono for data), radius and spacing scales, the sindoor dot meaning,
copy rules, haptics, and the destructive rose button (flat, never glass).

## New pieces
- **Selection thumb:** a glass bead that morphs between nav sections, with the sindoor dot ("you are here") inside it.
- **Liquid tank:** used space as sindoor liquid. It fills as the disk fills, sloshes once when the level changes,
  and a marker previews where cleaning will land. The marker sits above the glass so its text is never distorted.

## Light theme
Cards `#FFFFFF` on `#F7F7F5` with `#E4E4E7` borders, as the spec says. The selected segmented pill swaps to
obsidian with paper text. Light neutrals not in the spec are derived and checked for WCAG AA in `ContrastTests`.

## Water that follows the Mac
The liquid tank reads the MacBook's built-in accelerometer, so it behaves like water in a container: it stays level
as the laptop tilts, keeps its volume exactly, and sloshes when the Mac is moved.

- **No public API.** CoreMotion is iOS only. Room reads the sensor processor's HID service (`AppleSPUHIDDevice`,
  product `accel`). This is undocumented and could change in a macOS update, and it is not App Store safe.
  Every failure ends in a still tank.
- **No special permission.** It opens without admin rights. The driver is switched on only while the tank is on screen
  and the window is active, and restored when it leaves.
- **One-time calibration.** The sensor's axes are not documented, so Room learns which axis runs across the screen
  from a "lower the left edge" gesture. Until then the tank stays still, never wrong-way.
- **Model.** Water volume is conserved at every angle. The surface chases the apparent gravity through a damped
  spring (damping ratio about 0.35), so it overshoots about 30% and settles in under two seconds.
- **Roll only.** It models left and right tilt and sideways acceleration. Forward and back tilt and the lid angle are not modelled.
- **Cost.** A calm tank sleeps its render loop; the sensor runs at 100 Hz only while the Overview is visible.
- **Reduced Motion** keeps the water level.
