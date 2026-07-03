--[[
    Resource Definitions
    Defines all resource types for the underwater city builder raycaster.
    Maps wall tile types to mineable resources and provides loot tables.

    Basic resources (mined from walls):
      scrap_metal  - Wall type 1 - Common   - Basic construction
      crystal      - Wall type 2 - Uncommon - Electronics / power
      biomass      - Wall type 3 - Common   - Food / life support
      electronics  - Wall type 4 - Rare     - Advanced tech
      titanium     - Wall type 5 - Rare     - Hull / armor

    Advanced resources (crafted):
      composite    - scrap_metal + crystal
      circuit_board - electronics + crystal
      biofilter    - biomass + electronics
]]

local Resources = {}

-- Cached math functions for hot-path performance
local math_floor = math.floor
local math_random = math.random
local math_max = math.max
local math_min = math.min

-- =============================================================================
-- Rarity tiers
-- =============================================================================

Resources.RARITY = {
    common   = 1,
    uncommon = 2,
    rare     = 3,
    epic     = 4,
}

-- Reverse lookup: rarity number -> name
local rarityNames = {
    [1] = "Common",
    [2] = "Uncommon",
    [3] = "Rare",
    [4] = "Epic",
}

-- =============================================================================
-- Resource type definitions
-- =============================================================================

Resources.TYPES = {
    -- =========================================================================
    -- BASIC RESOURCES (mined from wall tiles)
    -- =========================================================================
    scrap_metal = {
        id          = "scrap_metal",
        name        = "Scrap Metal",
        color       = {0.6, 0.55, 0.5},
        rarity      = 1,  -- common
        wallType    = 1,
        mineTime    = 2.0,
        minYield    = 1,
        maxYield    = 3,
        description = "Corroded metal fragments. Basic construction material.",
    },

    crystal = {
        id          = "crystal",
        name        = "Crystal",
        color       = {0.4, 0.7, 0.9},
        rarity      = 2,  -- uncommon
        wallType    = 2,
        mineTime    = 3.0,
        minYield    = 1,
        maxYield    = 2,
        description = "Luminescent mineral formation. Used in electronics and power systems.",
    },

    biomass = {
        id          = "biomass",
        name        = "Biomass",
        color       = {0.3, 0.7, 0.4},
        rarity      = 1,  -- common
        wallType    = 3,
        mineTime    = 1.5,
        minYield    = 2,
        maxYield    = 4,
        description = "Organic matter from deep-sea life. Essential for food and life support.",
    },

    electronics = {
        id          = "electronics",
        name        = "Electronics",
        color       = {0.8, 0.7, 0.3},
        rarity      = 3,  -- rare
        wallType    = 4,
        mineTime    = 4.0,
        minYield    = 1,
        maxYield    = 2,
        description = "Salvaged circuitry and components. Required for advanced technology.",
    },

    titanium = {
        id          = "titanium",
        name        = "Titanium",
        color       = {0.7, 0.75, 0.8},
        rarity      = 3,  -- rare
        wallType    = 5,
        mineTime    = 5.0,
        minYield    = 1,
        maxYield    = 2,
        description = "Pressure-resistant alloy ore. Used in hull plating and armor.",
    },

    -- =========================================================================
    -- DEPTH-SPECIFIC RESOURCES (found as pickups in deeper biomes)
    -- =========================================================================
    coral = {
        id          = "coral",
        name        = "Coral Fragment",
        color       = {0.9, 0.4, 0.5},
        rarity      = 1,  -- common (in shallows)
        wallType    = nil,
        mineTime    = 0,
        minYield    = 0,
        maxYield    = 0,
        description = "Colorful coral polyps. Can be synthesized into biomass.",
    },

    rare_minerals = {
        id          = "rare_minerals",
        name        = "Rare Minerals",
        color       = {0.6, 0.3, 0.8},
        rarity      = 2,  -- uncommon
        wallType    = nil,
        mineTime    = 0,
        minYield    = 0,
        maxYield    = 0,
        description = "Unusual mineral deposits found at moderate depths. Refines into crystal or titanium.",
    },

    bioluminescent_flora = {
        id          = "bioluminescent_flora",
        name        = "Bioluminescent Flora",
        color       = {0.2, 0.9, 0.7},
        rarity      = 2,  -- uncommon
        wallType    = nil,
        mineTime    = 0,
        minYield    = 0,
        maxYield    = 0,
        description = "Glowing deep-sea plants with bioelectric properties. Converts to electronics or biomass.",
    },

    pressure_crystals = {
        id          = "pressure_crystals",
        name        = "Pressure Crystal",
        color       = {0.5, 0.4, 0.95},
        rarity      = 3,  -- rare
        wallType    = nil,
        mineTime    = 0,
        minYield    = 0,
        maxYield    = 0,
        description = "Crystals formed under extreme pressure. Yields high-quality crystal shards.",
    },

    abyssal_ore = {
        id          = "abyssal_ore",
        name        = "Abyssal Ore",
        color       = {0.2, 0.15, 0.4},
        rarity      = 4,  -- epic
        wallType    = nil,
        mineTime    = 0,
        minYield    = 0,
        maxYield    = 0,
        description = "Dense metallic ore from the deepest trenches. Rich in titanium and electronic-grade compounds.",
    },

    -- =========================================================================
    -- ADVANCED RESOURCES (crafted, no wall type)
    -- =========================================================================
    composite = {
        id          = "composite",
        name        = "Composite",
        color       = {0.55, 0.6, 0.65},
        rarity      = 2,  -- uncommon
        wallType    = nil,
        mineTime    = 0,
        minYield    = 0,
        maxYield    = 0,
        description = "Reinforced metal-crystal alloy. Strong and lightweight.",
        recipe      = {scrap_metal = 2, crystal = 1},
    },

    circuit_board = {
        id          = "circuit_board",
        name        = "Circuit Board",
        color       = {0.2, 0.6, 0.3},
        rarity      = 3,  -- rare
        wallType    = nil,
        mineTime    = 0,
        minYield    = 0,
        maxYield    = 0,
        description = "Precision electronic assembly. Core of all smart systems.",
        recipe      = {electronics = 1, crystal = 1},
    },

    biofilter = {
        id          = "biofilter",
        name        = "Biofilter",
        color       = {0.35, 0.65, 0.5},
        rarity      = 3,  -- rare
        wallType    = nil,
        mineTime    = 0,
        minYield    = 0,
        maxYield    = 0,
        description = "Bio-engineered filtration membrane. Purifies water and air.",
        recipe      = {biomass = 2, electronics = 1},
    },
}

-- =============================================================================
-- Pre-computed lookup tables (built once, used every frame)
-- =============================================================================

-- wallType number -> resource id
local wallTypeToResource = {}

-- Ordered list of all resource ids for deterministic iteration
local allResourceIds = {}

-- Build lookup tables from TYPES
for id, def in pairs(Resources.TYPES) do
    allResourceIds[#allResourceIds + 1] = id
    if def.wallType then
        wallTypeToResource[def.wallType] = id
    end
end

-- Sort for deterministic ordering (pairs order is not guaranteed in Lua)
table.sort(allResourceIds)

-- =============================================================================
-- Public API
-- =============================================================================

--- Get the resource id associated with a wall tile type.
-- @param wallType  Integer wall type (1-5).
-- @return Resource id string, or nil if the wall type has no resource.
function Resources.getForWallType(wallType)
    if not wallType then return nil end
    return wallTypeToResource[wallType]
end

--- Get the full definition for a resource by id.
-- @param resourceId  String resource identifier (e.g. "scrap_metal").
-- @return Resource definition table, or nil if not found.
function Resources.get(resourceId)
    if not resourceId then return nil end
    return Resources.TYPES[resourceId]
end

--- Roll a random yield amount for mining a resource.
-- Uses uniform distribution between minYield and maxYield (inclusive).
-- @param resourceId  String resource identifier.
-- @return Integer amount dropped, or 0 if resource is not mineable.
function Resources.rollYield(resourceId)
    local def = Resources.TYPES[resourceId]
    if not def then return 0 end
    if def.minYield <= 0 and def.maxYield <= 0 then return 0 end

    local lo = math_max(def.minYield, 1)
    local hi = math_max(def.maxYield, lo)
    return math_random(lo, hi)
end

--- Get all resource definitions as a table keyed by id.
-- @return The Resources.TYPES table (read-only intent).
function Resources.getAll()
    return Resources.TYPES
end

--- Get a sorted array of all resource ids.
-- Useful for UI lists and deterministic iteration.
-- @return Array of resource id strings, sorted alphabetically.
function Resources.getAllIds()
    return allResourceIds
end

--- Get the human-readable name for a rarity tier number.
-- @param rarityNum  Integer rarity value (1-4).
-- @return Rarity name string, or "Unknown" for invalid values.
function Resources.getRarityName(rarityNum)
    return rarityNames[rarityNum] or "Unknown"
end

--- Check whether a resource is mineable (has a wall type association).
-- @param resourceId  String resource identifier.
-- @return true if the resource can be mined from walls, false otherwise.
function Resources.isMineable(resourceId)
    local def = Resources.TYPES[resourceId]
    if not def then return false end
    return def.wallType ~= nil
end

--- Check whether a resource is craftable (has a recipe).
-- @param resourceId  String resource identifier.
-- @return true if the resource has a crafting recipe, false otherwise.
function Resources.isCraftable(resourceId)
    local def = Resources.TYPES[resourceId]
    if not def then return false end
    return def.recipe ~= nil
end

--- Get the crafting recipe for a resource.
-- @param resourceId  String resource identifier.
-- @return Recipe table {ingredientId = count, ...}, or nil if not craftable.
function Resources.getRecipe(resourceId)
    local def = Resources.TYPES[resourceId]
    if not def then return nil end
    return def.recipe
end

--- Get the mine time in seconds for a resource.
-- @param resourceId  String resource identifier.
-- @return Mine time in seconds, or 0 if not mineable.
function Resources.getMineTime(resourceId)
    local def = Resources.TYPES[resourceId]
    if not def then return 0 end
    return def.mineTime or 0
end

--- Get the color associated with a resource (for UI and world rendering).
-- @param resourceId  String resource identifier.
-- @return Color table {r, g, b} with values 0-1, or white {1,1,1} as fallback.
function Resources.getColor(resourceId)
    local def = Resources.TYPES[resourceId]
    if not def then return {1, 1, 1} end
    return def.color
end

return Resources
