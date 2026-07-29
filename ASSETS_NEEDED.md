# Asset Replacement Manifest

This document describes the asset situation for Thresher's Hope: what the game
ships with today, what is missing, and where external assets could be slotted
in by anyone who wants to reskin or extend the game.

## 1. Current State: Zero Asset Files Required

**The game is 100% procedurally drawn. There are no image, audio, font, or
model files in the repository, and none are needed to play.** Clone the repo,
run it with LÖVE 11.x, and everything renders.

Verified by scanning every Lua file for asset-loading call sites:

- No `love.graphics.newImage("path")` calls with file paths. Every
  `newImage(...)` call in the codebase takes an `ImageData` object that was
  generated in code via `love.image.newImageData(width, height)` and filled
  pixel-by-pixel:
  - Wall / door / ceiling / floor / stairs textures — `raycaster.lua`
    (`Raycaster.generateTextures`, line 145 onward)
  - Item, NPC, and decoration sprites — `sprites.lua`
    (`Sprites.generateTextures`, line 217 onward)
  - All 8 enemy textures — `enemies.lua` (`Enemies.createTexture`, line 274,
    dispatching to per-creature `_gen*` painters)
- No `love.audio.*`, `love.sound.*`, `newSource`, or `newSoundData` calls
  anywhere.
- No `love.graphics.newFont("file.ttf", ...)` calls. All fonts are
  `love.graphics.newFont(size)` — LÖVE's built-in default font.
- No `io.open`, `love.filesystem.read`, or `require` of any media path.
- No `.png` / `.ogg` / `.wav` / `.ttf` string literals in any source file.

The only binary in the repo is `docs/media/screenshot-sinking.png`, which is
README documentation, not a game asset.

## 2. The Audio Gap

**No audio system exists.** The game is completely silent: there is no sound
module, no mixer, no `love.audio` usage, and no hooks for sound playback. This
is the single largest asset gap.

A future audio pass would need (a) a small sound manager module and (b) sounds
for the events below. The list is derived from the actual game systems and the
two-phase state machine (`GAME_STATES.SINKING` / `GAME_STATES.SURVIVAL`,
`main.lua` line 80). File references point at the code that would trigger each
sound.

### Sinking phase (opening act)

| # | Event | Trigger point |
|---|-------|---------------|
| 1 | Hull groans / metal creaks (looping ambience while the ship goes down) | `sinking.lua` `Sinking.update` (line 243) while `Sinking.isActive()` |
| 2 | Rushing-water flood surge as sections flood stern-to-bow | `sinking.lua` section flooding in `update`; initial breaches seeded in `main.lua` (lines 360–397) |
| 3 | Warning klaxon at the 3 min / 1 min / 30 sec marks | `sinking.lua` time-based warnings (lines 267–273), surfaced in `main.lua` (lines 778–783) |
| 4 | Impact / settling rumble when the ship reaches the seafloor and the game transitions to survival | `main.lua` `startSurvivalPhase` (line 419) |

### Water and flooding

| # | Event | Trigger point |
|---|-------|---------------|
| 5 | Breach spray / inrushing water when a new breach opens | `flooding.lua` `Flooding.addBreach` (line 120) |
| 6 | Water-spread lapping as flooding creeps tile to tile | `flooding.lua` `Flooding.spread` (line 162) |
| 7 | Muffled underwater loop while submerged | `flooding.lua` `Flooding.getSubmergedOverlay` (line 312) |
| 8 | Swimming strokes / bubbles | `player.lua` `Player.setSwimming` (line 195) and swim bob constants (lines 19–23) |
| 9 | Pump / breach-sealed confirmation when a breach is removed | `flooding.lua` `Flooding.removeBreach` (line 133) |

### Mining

| # | Event | Trigger point |
|---|-------|---------------|
| 10 | Mining drill / pick loop while LMB is held on a wall | `mining.lua` `Mining.update` (line 331) while `Mining.isActive()` |
| 11 | Wall-break crumble on mine completion | `mining.lua` `Mining.setOnMineComplete` callback, wired in `main.lua` (line 275) |
| 12 | Hull-breach alarm when mining punctures the hull during the sinking phase | `main.lua` mine-complete handler (line 280 — mining a wall creates a breach) |
| 13 | Resource-drop clatter when mined items spawn | `sprites.lua` `Sprites.addItem` (line 960) via the mining callback |

### Combat

| # | Event | Trigger point |
|---|-------|---------------|
| 14 | Melee swing (whoosh) | `main.lua` `useHotbarItem` melee branch / `checkMeleeHit` (line 940) |
| 15 | Melee connect (impact) | `main.lua` `checkMeleeHit` hit branch (line 966) |
| 16 | Ranged weapon fire | `main.lua` `useHotbarItem` ranged branch (lines 989–1001) |
| 17 | Out-of-ammo dry click | `main.lua` `useHotbarItem` ammo check (line 990) |
| 18 | Projectile impact (wall or flesh) | `main.lua` projectile update loop (lines 1016–1052) |
| 19 | Enemy hurt | `main.lua` sprite damage application (line 1034 and melee at 967) |
| 20 | Enemy death | health-depleted removal in the same loops |
| 21 | Enemy attack landing on the player | `main.lua` enemy contact damage (line 724) |
| 22 | Per-enemy vocalizations (8 types: Crawler, Lurker, Swarm, Angler, Pressure Beast, Leviathan, Abyssal, Hydra) | `enemies.lua` `Enemies.TYPES` table (line 67), `Enemies.spawnEnemy` (line 1165) |
| 23 | Player hurt grunt | `survival.lua` `Survival.takeDamage` (line 249) |
| 24 | Player death sting | `main.lua` death check (lines 707–710) |

### Building, crafting, research

| # | Event | Trigger point |
|---|-------|---------------|
| 25 | Enter / exit build mode | `building.lua` `Building.enterBuildMode` / `exitBuildMode` (lines 270 / 275) |
| 26 | Cycle building selection | `building.lua` `Building.cycleType` (line 329) |
| 27 | Building placed (construction thunk) | `building.lua` `Building.place` (line 476) |
| 28 | Building removed (deconstruction) | `building.lua` `Building.remove` (line 508) |
| 29 | Invalid-placement error buzz | `building.lua` `Building.canPlace` failure (line 435) |
| 30 | Craft started | `crafting.lua` `Crafting.startCraft` (line 365) |
| 31 | Craft completed | `crafting.lua` `Crafting.update` completion (line 405) |
| 32 | Craft cancelled | `crafting.lua` `Crafting.cancelCraft` (line 438) |
| 33 | Research started | `tech.lua` `Tech.startResearch` (line 600) |
| 34 | Research completed | `tech.lua` `Tech.update` completion (line 630) |

### Power and survival

| # | Event | Trigger point |
|---|-------|---------------|
| 35 | Generator hum loop near powered buildings | `power.lua` `Power.isPowered` (line 442) / powered-set (line 473) |
| 36 | Brownout alarm when demand exceeds supply | `power.lua` brownout status (lines 234–238, `networkStatus == "brownout"`) |
| 37 | Low-oxygen alarm | `survival.lua` `Survival.getWarnings` (line 287) O2 warning |
| 38 | O2 refill hiss inside a habitat / near an O2 generator | `survival.lua` refill branch in `update` (line 124, `O2_REFILL_RATE`) |
| 39 | Starvation warning | `survival.lua` hunger warning in `getWarnings` |
| 40 | Pressure-damage creak at dangerous depth | `survival.lua` pressure damage in `update`; scaling from `depth.lua` `Depth.getPressureMultiplier` (line 255) |
| 41 | Eat / consume food | `survival.lua` `Survival.consumeFood` (line 274) |
| 42 | Heal / use consumable | `survival.lua` `Survival.heal` (line 265), hotbar use in `main.lua` |

### Doors, traversal, world

| # | Event | Trigger point |
|---|-------|---------------|
| 43 | Door slide open / close | `doors.lua` `Doors.interact` (line 68) and animation in `Doors.update` (line 108) |
| 44 | Footsteps (dry deck vs. shallow-water splash variants) | `player.lua` `Player.move` (line 136); water level from `flooding.lua` `Flooding.getLevelFast` (line 223) |
| 45 | Stairs / floor transition | `main.lua` stair use (line 1068) → `worldgen.lua` `changeFloor` (line 763) |

### Pickups, narrative, UI

| # | Event | Trigger point |
|---|-------|---------------|
| 46 | Item pickup chime | `main.lua` pickup handler (line 587) |
| 47 | Log discovered (narrative sting) | `narrative.lua` `Narrative.discoverLog` (line 327) |
| 48 | Codex viewer open / close | `narrative.lua` `Narrative.toggleViewer` (line 484) |
| 49 | Generic UI click (key/mouse menu interactions) | `main.lua` `love.keypressed` (line 2247) / `love.mousepressed` (line 2420) |
| 50 | On-screen message chirp | `main.lua` `showMessage` (line 633) / message queue (line 749 onward) |

### Ambient beds (looping)

| # | Event | Trigger point |
|---|-------|---------------|
| 51 | Base ambience: submarine interior drone (established base) | `atmosphere.lua` `Atmosphere.setBaseEstablished` (line 589) / presets (line 546) |
| 52 | Per-depth-zone ambience (shallows → abyss → trench, darker with depth) | `depth.lua` `Depth.getZoneForFloor` (line 218) / `Depth.getAtmospherePreset` (line 379) |
| 53 | Corruption-zone drone in corrupted areas | `corruption.lua` `Corruption.getLevel` (line 51) around the player |

**Total: 53 sound events** (45 one-shots / stingers, 8 loops or looping beds).

Suggested convention if assets are added: `assets/sfx/<category>_<event>.ogg`
and `assets/music/ambient_<zone>.ogg`, OGG Vorbis, loaded through a single
sound-manager module so the rest of the codebase stays free of file paths.

## 3. Visual Slots: Where an Image Could Substitute

Art replacement is **optional** — the procedural art is the shipped look —
but the code structure makes drop-in substitution meaningful in exactly the
places where a generated `ImageData` is converted to a texture. Each of these
call sites ends in `love.graphics.newImage(imageData)`; replacing that with
`love.graphics.newImage("your_file.png")` (matching the expected size) swaps
the art with no other code changes, because everything downstream only ever
handles the returned `Image`:

| Slot | Expected size | Construction site |
|------|---------------|-------------------|
| Wall textures (one per theme wall type) | `texWidth` x `texHeight` (64x64) | `raycaster.lua` `Raycaster.generateTextures`, `newImage` at line 176 |
| Door texture | 64x64 | `raycaster.lua` line 221 |
| Ceiling texture | 64x64 | `raycaster.lua` line 250 |
| Corrupted floor texture | 64x64 | `raycaster.lua` line 290 |
| Stairs up / stairs down textures | 64x64 | `raycaster.lua` lines 337 / 382 |
| Item and NPC billboard sprites | per-sprite `size` | `sprites.lua` `Sprites.generateTextures` (line 217), `newImage` calls at lines 283–862 |
| Enemy billboard sprites (8 creature types) | per-type `size` | `enemies.lua` `Enemies.createTexture` (line 274, `newImage` at line 308) |

Not applicable / no slot exists:

- **Title screen** — there is none. The game boots directly into the sinking
  phase (`gameState = GAME_STATES.SINKING`, `main.lua` line 85); there is no
  menu scene an image could replace.
- **First-person weapon overlay** — drawn with vector primitives inline in
  `main.lua` (line ~1627), not via a texture object; substituting an image
  would require restructuring that draw code, not a drop-in swap.
- **Fonts** — LÖVE's built-in default at multiple sizes; a `.ttf` could be
  passed to the `getFont` caches (e.g. `mining.lua` line 103,
  `narrative.lua` line 31) but nothing requires it.
- **HUD, water tint, fog, vignette, color grading** — computed effects
  (`atmosphere.lua`, `flooding.lua`, `corruption.lua`), not images.

If you add any media files, keep them out of commits unless they are yours to
license — this repository intentionally ships none.
