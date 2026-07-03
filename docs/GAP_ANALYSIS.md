# Thresher's Hope — Gap Analysis

_Date: 2026-07-02. Basis: 25 Lua modules (all syntax-clean), boot-verified,
render bug fixed. Keyword-verified claims._

## State after the 2026-07-02 pass

The project was shelved (its folder was literally labeled "do not work on") with
a bug that made it look broken: **the 3D environment rendered pure black while the
HUD showed fine.** Root cause: `Atmosphere.drawVignette` composited a black-with-
alpha vignette canvas in `"multiply"` blend mode; multiply ignores alpha and
multiplied the whole screen center by `(0,0,0)`, blacking out the world. Fixed by
switching that draw to alpha blending. The world now renders (see README shot).

## What's already here (strong foundation — don't rebuild)

Hand-written DDA raycaster (walls, textured, sky/floor/ceiling, doors, stairs),
procedural BSP worldgen with 9 biomes, real-time flooding/water simulation with
hull breaches, atmosphere system (fog/vignette/disturbance/desaturation/color
grading), mining, building, crafting, power grid, tech tree, crew, enemies +
AI, depth/pressure, corruption, doors, sprites, a narrative/lore layer, minimap,
and two game phases (sinking → survival).

## Gaps (verified absent), ranked

### 1. Audio — zero sound calls in the entire codebase — HIGH, cheap
No `love.audio`/`newSource` anywhere. A sinking-ship survival game is carried by
sound: creaking hull, rushing water, the mining laser, alarms, ambient deep-sea
dread. Freesound/Kenney packs + a ~20-line sound manager. Biggest felt win.

### 2. Save/load — none — HIGH
No persistence (`love.filesystem.write` unused). A survival game needs to survive
a quit. Serialize player + map + inventory + phase state to a save file.

### 3. Phase arc connection — MEDIUM
`GAME_STATES` has SINKING and SURVIVAL but they aren't stitched into one
progression. Define the transition (escape the wreck → establish the colony) so
the two halves read as one game.

### 4. Balance & tuning pass — MEDIUM
Timers, resource yields, enemy difficulty, O2/pressure drain are untuned. Needs a
playtest loop now that the world is visible.

### 5. Renderer polish — LOW (nice-to-have)
The raycaster is column-based CPU rendering. Sprite billboards and floor casting
exist; potential adds: colored lighting per light source, distance dithering, a
proper first-person tool animation set. Optional.

## Genre ideas worth borrowing

- **Barotrauma / Subnautica**: oxygen management (O2 stat exists) driving tension;
  creature threats scaling with depth (depth system exists).
- **FTL**: the sinking phase as a tight escape-room timer with branching exits.

## Suggested sequencing

1. Audio + save/load (the two "make it a real game" gaps)
2. Connect the sinking → survival arc
3. Balance pass
4. Renderer polish
