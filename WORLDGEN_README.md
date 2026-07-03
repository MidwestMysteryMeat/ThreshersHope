# Procedural World Generation - Raycaster POC

This raycaster proof-of-concept now includes a procedural dungeon generation system adapted from the main game's `worldgen.lua`.

## Features

### 🎲 Procedural Generation
- **BSP (Binary Space Partitioning)** algorithm for room layout
- **Dynamic corridors** connecting rooms with L-shaped paths
- **Automatic door placement** at room entrances
- **Multi-floor dungeons** with stairs linking levels
- **Reproducible seeds** - same seed generates same dungeon

### 🏰 Biomes

The system includes 9 different biomes, each with unique characteristics:

| Biome | Theme | Wall Types | Room Count | Corridor Width | Ceiling |
|-------|-------|------------|------------|----------------|---------|
| `dungeon` | Stone Dungeon | Dark/Mossy Stone | 4-8 | 1 | ✓ |
| `cave` | Natural Cave | Wet/Mossy Walls | 3-6 | 2 | ✗ |
| `crypt` | Ancient Crypt | Blue-gray/Iron | 6-10 | 1 | ✓ |
| `mine` | Abandoned Mine | Brown/Stone | 8-12 | 1 | ✓ |
| `town` | Town Streets | Plaster/Wood | 5-9 | 3 | ✗ |
| `desert_ruins` | Desert Ruins | Sandstone | 4-7 | 2 | ✗ |
| `forest` | Deep Forest | Trees/Moss | 3-6 | 2 | ✗ |
| `void_sanctum` | Void Sanctum | Purple Stone | 3-5 | 2 | ✓ |
| `castle` | Castle Keep | Gray Blocks | 4-7 | 2 | ✓ |

### 🎮 Controls

| Key | Action |
|-----|--------|
| **G** | Toggle between procedural and static maps |
| **B** | Cycle through biomes (procedural mode only) |
| **P** | Regenerate current biome with new seed |
| **1-6** | Switch to static maps (town, desert, forest, etc.) |

## Technical Details

### Map Generation Parameters

```lua
WorldGen.generate(biomeId, {
    width = 48,        -- Grid width (default: 48)
    height = 48,       -- Grid height (default: 48)
    floors = 3,        -- Number of floors (default: 3)
    seed = os.time(),  -- Random seed (default: current time)
})
```

### Biome Configuration

Each biome defines:
- `wallTypes`: Array of wall texture IDs (1-5)
- `primaryWall`: Main wall type used for outer walls
- `secondaryWall`: Accent wall type for decoration
- `roomMinSize/roomMaxSize`: Min/max room dimensions
- `corridorWidth`: Width of connecting hallways
- `roomCount`: Min/max number of rooms per floor
- `hasCeiling`: Whether to render dark ceilings

### Generation Algorithm

1. **Initialize Grid**: Fill map with solid walls
2. **BSP Splitting**: Recursively divide map into containers
3. **Room Creation**: Place rooms within containers
4. **Corridor Carving**: Connect room centers with L-shaped paths
5. **Door Placement**: Add doors where corridors meet rooms
6. **Stair Placement**: Link floors with up/down stairs

## Integration with Main Game

This procedural system is designed to be compatible with the main game's world generation. The biome types correspond to regions in the main game:

- `dungeon` → Generic stone dungeons
- `cave` → Natural cave systems (Dwarven Mountains)
- `crypt` → Burial sites (Holy Dominion)
- `mine` → Mining operations (Gnomish Isles)
- `desert_ruins` → Calidar wastelands temples
- `forest` → Elven forest clearings
- `void_sanctum` → Covenant sanctums (Shadowfen)
- `castle` → Imperial fortresses

## Future Enhancements

Planned additions from the main game:
- [ ] **NPCs & Enemies** - Procedural spawn based on biome
- [ ] **Loot Tables** - Item spawns matching dungeon type
- [ ] **Traps & Hazards** - Floor-specific challenges
- [ ] **Boss Rooms** - Special large chambers on final floors
- [ ] **Corruption System** - Dynamic environmental hazards
- [ ] **Biome-Specific Mechanics** - Unique features per biome type
- [ ] **Quest Integration** - Dungeon objectives and rewards

## Performance

At 1280×800 resolution:
- **Generation time**: < 100ms for 48×48×3 dungeon
- **Memory footprint**: ~2MB per full dungeon
- **FPS impact**: None (generation happens once on load)

The BSP algorithm scales well to larger maps (up to 128×128 tested).

## Examples

**Small Crypt** (many small chambers):
```lua
WorldGen.generate("crypt", {width = 32, height = 32, floors = 5})
```

**Large Cave System** (fewer, bigger rooms):
```lua
WorldGen.generate("cave", {width = 64, height = 64, floors = 2})
```

**Massive Castle** (huge halls):
```lua
WorldGen.generate("castle", {width = 96, height = 96, floors = 4})
```

---

**Note**: This is a proof-of-concept. The full world generation system in the main game includes region-based biome distribution, chunk loading, infinite terrain, and hollow earth integration.
