--[[
    Theme System
    Different visual themes for various locations
]]

local Themes = {}

-- Texture definitions per theme
-- Each theme has wall textures, sky, floor, and atmosphere settings
Themes.definitions = {
    --===========================================
    -- DUNGEON: Dark stone corridors
    --===========================================
    dungeon = {
        name = "Dungeon",
        walls = {
            {0.4, 0.35, 0.3},   -- 1: Dark stone
            {0.3, 0.4, 0.3},    -- 2: Mossy stone
            {0.5, 0.4, 0.35},   -- 3: Brown brick
            {0.35, 0.35, 0.4},  -- 4: Blue-gray stone
            {0.25, 0.25, 0.25}, -- 5: Dark iron
        },
        sky = {
            top = {0.02, 0.02, 0.05},     -- Nearly black
            bottom = {0.08, 0.08, 0.12},  -- Slightly lighter
        },
        floor = {
            near = {0.25, 0.2, 0.15},     -- Brown dirt
            far = {0.1, 0.08, 0.06},      -- Fades to dark
        },
        fog = {
            density = 0.12,
            color = {0.05, 0.05, 0.08},
        },
        ambient = 0.3,  -- Low light
        doorColor = {0.45, 0.3, 0.2},  -- Wooden door
    },

    --===========================================
    -- TOWN: Bright medieval streets
    --===========================================
    town = {
        name = "Town",
        walls = {
            {0.85, 0.8, 0.7},   -- 1: Plaster/stucco
            {0.6, 0.45, 0.3},   -- 2: Wood planks
            {0.7, 0.4, 0.35},   -- 3: Red brick
            {0.5, 0.5, 0.55},   -- 4: Cobblestone
            {0.4, 0.55, 0.4},   -- 5: Painted green
        },
        sky = {
            top = {0.4, 0.6, 0.9},        -- Blue sky
            bottom = {0.7, 0.8, 0.95},    -- Lighter horizon
        },
        floor = {
            near = {0.5, 0.45, 0.4},      -- Cobblestone
            far = {0.4, 0.38, 0.35},      -- Slightly darker
        },
        fog = {
            density = 0.03,
            color = {0.7, 0.75, 0.85},
        },
        ambient = 0.9,  -- Bright daylight
        doorColor = {0.5, 0.35, 0.2},  -- Oak door
    },

    --===========================================
    -- DESERT: Calidar wastelands
    --===========================================
    desert = {
        name = "Desert Ruins",
        walls = {
            {0.85, 0.75, 0.55},  -- 1: Sandstone
            {0.7, 0.6, 0.45},    -- 2: Clay brick
            {0.9, 0.85, 0.7},    -- 3: Pale limestone
            {0.6, 0.5, 0.4},     -- 4: Dried mud
            {0.5, 0.55, 0.6},    -- 5: Glassed sand (special)
        },
        sky = {
            top = {0.95, 0.85, 0.6},      -- Hot hazy sky
            bottom = {1.0, 0.95, 0.8},    -- Bright horizon
        },
        floor = {
            near = {0.9, 0.8, 0.6},       -- Sand
            far = {0.85, 0.75, 0.55},     -- Distant sand
        },
        fog = {
            density = 0.05,
            color = {0.95, 0.9, 0.75},    -- Heat haze
        },
        ambient = 1.0,  -- Harsh sunlight
        doorColor = {0.6, 0.5, 0.35},  -- Weathered wood
    },

    --===========================================
    -- FOREST: Elven woodland
    --===========================================
    forest = {
        name = "Forest",
        walls = {
            {0.4, 0.5, 0.35},    -- 1: Living tree
            {0.55, 0.45, 0.3},   -- 2: Dead wood
            {0.35, 0.45, 0.35},  -- 3: Moss-covered
            {0.5, 0.4, 0.3},     -- 4: Bark
            {0.6, 0.55, 0.45},   -- 5: Birch
        },
        sky = {
            top = {0.2, 0.35, 0.2},       -- Canopy filtered
            bottom = {0.4, 0.55, 0.35},   -- Green-tinted light
        },
        floor = {
            near = {0.3, 0.35, 0.2},      -- Forest floor
            far = {0.2, 0.25, 0.15},      -- Dark undergrowth
        },
        fog = {
            density = 0.08,
            color = {0.3, 0.4, 0.3},      -- Green mist
        },
        ambient = 0.6,  -- Dappled light
        doorColor = {0.4, 0.5, 0.35},  -- Living wood door
    },

    --===========================================
    -- VOID: Covenant sanctum (special/creepy)
    --===========================================
    void = {
        name = "Void Sanctum",
        walls = {
            {0.15, 0.1, 0.2},    -- 1: Dark purple stone
            {0.1, 0.15, 0.2},    -- 2: Blue-black
            {0.2, 0.15, 0.25},   -- 3: Violet
            {0.05, 0.05, 0.1},   -- 4: Near black
            {0.3, 0.2, 0.4},     -- 5: Ethereal purple
        },
        sky = {
            top = {0.0, 0.0, 0.02},       -- Absolute void
            bottom = {0.1, 0.05, 0.15},   -- Faint purple glow
        },
        floor = {
            near = {0.1, 0.08, 0.15},     -- Dark stone
            far = {0.02, 0.02, 0.05},     -- Fades to nothing
        },
        fog = {
            density = 0.15,
            color = {0.1, 0.05, 0.15},    -- Purple void fog
        },
        ambient = 0.25,  -- Minimal light
        doorColor = {0.2, 0.15, 0.3},  -- Void-touched door
    },

    --===========================================
    -- UNDERWATER: Ocean floor / sunken wreck
    --===========================================
    underwater = {
        name = "Ocean Floor",
        walls = {
            {0.2, 0.35, 0.4},    -- 1: Corroded metal (scrap_metal)
            {0.3, 0.5, 0.55},    -- 2: Crystal formation (crystal)
            {0.25, 0.4, 0.3},    -- 3: Bio-encrusted rock (biomass)
            {0.35, 0.4, 0.45},   -- 4: Sediment stone (electronics)
            {0.4, 0.45, 0.5},    -- 5: Titanium ore vein (titanium)
        },
        sky = {
            top = {0.0, 0.02, 0.08},      -- Deep dark water above
            bottom = {0.02, 0.08, 0.15},   -- Slightly brighter mid-water
        },
        floor = {
            near = {0.15, 0.2, 0.25},     -- Sandy ocean floor
            far = {0.05, 0.08, 0.12},     -- Fades into dark water
        },
        fog = {
            density = 0.10,
            color = {0.02, 0.08, 0.15},    -- Deep ocean blue
        },
        ambient = 0.35,
        doorColor = {0.3, 0.35, 0.4},  -- Corroded hatch
    },

    --===========================================
    -- WRECK: Sunken ship interior
    --===========================================
    wreck = {
        name = "Sunken Wreck",
        walls = {
            {0.3, 0.3, 0.35},    -- 1: Rusted hull plates
            {0.25, 0.28, 0.3},   -- 2: Corroded bulkhead
            {0.35, 0.3, 0.25},   -- 3: Wooden paneling (waterlogged)
            {0.2, 0.22, 0.28},   -- 4: Flooded machinery
            {0.4, 0.38, 0.35},   -- 5: Brass fittings
        },
        sky = {
            top = {0.0, 0.01, 0.05},      -- Ceiling/dark water
            bottom = {0.02, 0.05, 0.1},    -- Dimly lit interior
        },
        floor = {
            near = {0.2, 0.18, 0.15},     -- Rusted deck plates
            far = {0.08, 0.07, 0.06},     -- Dark corners
        },
        fog = {
            density = 0.18,
            color = {0.03, 0.05, 0.08},    -- Murky water fog
        },
        ambient = 0.2,
        doorColor = {0.35, 0.3, 0.25},  -- Rusted hatch
    },

    --===========================================
    -- HABITAT: Player-built underwater base
    --===========================================
    habitat = {
        name = "Habitat Module",
        walls = {
            {0.6, 0.65, 0.7},    -- 1: Clean alloy panels
            {0.5, 0.55, 0.6},    -- 2: Reinforced glass
            {0.55, 0.6, 0.55},   -- 3: Life support conduit
            {0.45, 0.5, 0.55},   -- 4: Storage panel
            {0.65, 0.6, 0.55},   -- 5: Warm lighting panel
        },
        sky = {
            top = {0.1, 0.12, 0.18},      -- Ceiling with lights
            bottom = {0.2, 0.25, 0.3},    -- Ambient glow
        },
        floor = {
            near = {0.35, 0.38, 0.4},     -- Clean floor plates
            far = {0.25, 0.28, 0.3},      -- Slightly darker
        },
        fog = {
            density = 0.03,
            color = {0.3, 0.35, 0.4},      -- Clean air, slight haze
        },
        ambient = 0.8,
        doorColor = {0.5, 0.55, 0.6},  -- Airlock door
    },

    --===========================================
    -- CASTLE: Imperial fortress
    --===========================================
    castle = {
        name = "Castle",
        walls = {
            {0.6, 0.6, 0.65},    -- 1: Gray stone blocks
            {0.5, 0.5, 0.55},    -- 2: Darker stone
            {0.7, 0.65, 0.6},    -- 3: Warm stone
            {0.4, 0.4, 0.45},    -- 4: Slate
            {0.55, 0.4, 0.35},   -- 5: Brick accent
        },
        sky = {
            top = {0.5, 0.55, 0.7},       -- Overcast
            bottom = {0.65, 0.7, 0.8},    -- Gray horizon
        },
        floor = {
            near = {0.45, 0.42, 0.4},     -- Stone floor
            far = {0.35, 0.33, 0.32},     -- Darker distance
        },
        fog = {
            density = 0.04,
            color = {0.5, 0.55, 0.6},
        },
        ambient = 0.7,
        doorColor = {0.4, 0.3, 0.25},  -- Heavy oak door
    },
}

-- Get theme by name (with fallback)
function Themes.get(themeName)
    return Themes.definitions[themeName] or Themes.definitions.dungeon
end

-- Get list of available themes
function Themes.getList()
    local list = {}
    for name, theme in pairs(Themes.definitions) do
        table.insert(list, {id = name, name = theme.name})
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

return Themes
