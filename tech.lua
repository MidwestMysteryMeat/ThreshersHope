--[[
    Tech Tree System
    Manages a 5-branch, 28-tech research tree for an underwater city builder
    raycaster. Each branch has 5 tiers, plus 3 cross-branch techs.

    Branches:
      1. Engineering  - Structural hull and pressure resistance
      2. Life Support - Oxygen, food, atmosphere recycling
      3. Power        - Energy generation and distribution
      4. Defense      - Turrets, shields, fortifications
      5. Science      - Scanning, mapping, precursor research

    Cross-branch techs require techs from multiple branches.
]]

local Tech = {}

-- Cached math functions for hot-path performance
local math_floor = math.floor
local math_min   = math.min
local math_max   = math.max

-- =============================================================================
-- Branch names (ordered for UI)
-- =============================================================================

local BRANCHES = {
    "engineering",
    "life_support",
    "power",
    "defense",
    "science",
}

-- Display names
local BRANCH_NAMES = {
    engineering  = "Engineering",
    life_support = "Life Support",
    power        = "Power",
    defense      = "Defense",
    science      = "Science",
}

-- Branch colors for UI
local BRANCH_COLORS = {
    engineering  = {0.8, 0.6, 0.3},
    life_support = {0.3, 0.8, 0.5},
    power        = {0.9, 0.8, 0.2},
    defense      = {0.8, 0.3, 0.3},
    science      = {0.4, 0.6, 0.9},
}

-- =============================================================================
-- Tech tree definitions (28 total)
-- =============================================================================

Tech.TREE = {
    -- =========================================================================
    -- ENGINEERING BRANCH (Tier 1-5)
    -- =========================================================================
    basic_hull = {
        id           = "basic_hull",
        name         = "Basic Hull Plating",
        branch       = "engineering",
        tier         = 1,
        cost         = { scrap_metal = 10 },
        researchTime = 15,
        requires     = {},
        unlocks      = { "hull_repair", "basic_walls" },
        description  = "Salvaged steel panels reinforced with spot welds. Enough to keep the water out -- barely.",
    },
    reinforced_hull = {
        id           = "reinforced_hull",
        name         = "Reinforced Hull",
        branch       = "engineering",
        tier         = 2,
        cost         = { scrap_metal = 20, crystal = 5 },
        researchTime = 30,
        requires     = { "basic_hull" },
        unlocks      = { "pressure_doors", "reinforced_walls" },
        description  = "Double-layered hull with crystal-bonded seams. Withstands moderate pressure differentials.",
    },
    pressure_hull = {
        id           = "pressure_hull",
        name         = "Pressure Hull",
        branch       = "engineering",
        tier         = 3,
        cost         = { scrap_metal = 30, titanium = 10, crystal = 10 },
        researchTime = 60,
        requires     = { "reinforced_hull" },
        unlocks      = { "deep_corridors", "airlock_mk2" },
        description  = "Titanium-composite hull rated for mid-depth operations. Standard CG spec, pre-incident.",
    },
    deep_hull = {
        id           = "deep_hull",
        name         = "Deep Pressure Hull",
        branch       = "engineering",
        tier         = 4,
        cost         = { titanium = 25, crystal = 15, electronics = 10 },
        researchTime = 90,
        requires     = { "pressure_hull" },
        unlocks      = { "abyss_access", "structural_integrity_field" },
        description  = "Multi-layer titanium shell with active pressure compensation. Rated to 500 meters.",
    },
    titan_hull = {
        id           = "titan_hull",
        name         = "Titan-Class Hull",
        branch       = "engineering",
        tier         = 5,
        cost         = { titanium = 40, crystal = 25, electronics = 20, composite = 10 },
        researchTime = 150,
        requires     = { "deep_hull" },
        unlocks      = { "trench_access", "megastructures" },
        description  = "The pinnacle of human pressure engineering. Rated beyond 1000 meters -- deeper than any vessel was meant to go.",
    },

    -- =========================================================================
    -- LIFE SUPPORT BRANCH (Tier 1-5)
    -- =========================================================================
    basic_o2 = {
        id           = "basic_o2",
        name         = "Basic O2 Extraction",
        branch       = "life_support",
        tier         = 1,
        cost         = { scrap_metal = 8, biomass = 5 },
        researchTime = 15,
        requires     = {},
        unlocks      = { "o2_generator" },
        description  = "Electrolysis unit that cracks seawater into breathable oxygen. Crude but functional.",
    },
    recycler = {
        id           = "recycler",
        name         = "Air Recycler",
        branch       = "life_support",
        tier         = 2,
        cost         = { scrap_metal = 15, biomass = 10, electronics = 5 },
        researchTime = 30,
        requires     = { "basic_o2" },
        unlocks      = { "recycler_building", "co2_scrubber" },
        description  = "Carbon-dioxide scrubber with algae-based regeneration. Extends oxygen supply significantly.",
    },
    hydroponics = {
        id           = "hydroponics",
        name         = "Hydroponics Bay",
        branch       = "life_support",
        tier         = 3,
        cost         = { biomass = 20, crystal = 10, electronics = 8 },
        researchTime = 55,
        requires     = { "recycler" },
        unlocks      = { "hydroponics_bay", "food_production" },
        description  = "Pressurized growing chambers using bioluminescent light. Produces edible kelp and algae supplements.",
    },
    biofilter_mk2 = {
        id           = "biofilter_mk2",
        name         = "Biofilter Mk.II",
        branch       = "life_support",
        tier         = 4,
        cost         = { biomass = 25, electronics = 15, biofilter = 5 },
        researchTime = 85,
        requires     = { "hydroponics" },
        unlocks      = { "advanced_medbay", "water_purifier_mk2" },
        description  = "Second-generation biological membrane filter. Removes toxins, parasites, and deep-water contaminants.",
    },
    closed_loop = {
        id           = "closed_loop",
        name         = "Closed-Loop Ecosystem",
        branch       = "life_support",
        tier         = 5,
        cost         = { biomass = 35, electronics = 20, biofilter = 10, circuit_board = 5 },
        researchTime = 140,
        requires     = { "biofilter_mk2" },
        unlocks      = { "self_sustaining_habitat", "population_cap_increase" },
        description  = "Fully self-sustaining life support. Zero external input required. The base becomes its own biosphere.",
    },

    -- =========================================================================
    -- POWER BRANCH (Tier 1-5)
    -- =========================================================================
    basic_gen = {
        id           = "basic_gen",
        name         = "Salvage Generator",
        branch       = "power",
        tier         = 1,
        cost         = { scrap_metal = 12, electronics = 3 },
        researchTime = 15,
        requires     = {},
        unlocks      = { "generator_building" },
        description  = "Diesel generator salvaged from the wreck. Loud, smoky, unreliable -- but it makes power.",
    },
    solar_cell = {
        id           = "solar_cell",
        name         = "Bioluminescent Solar Cell",
        branch       = "power",
        tier         = 2,
        cost         = { crystal = 12, biomass = 8, electronics = 5 },
        researchTime = 30,
        requires     = { "basic_gen" },
        unlocks      = { "solar_array", "power_storage" },
        description  = "Photovoltaic cells tuned to deep-sea bioluminescence. Minimal output, but silent and self-sustaining.",
    },
    thermal_gen = {
        id           = "thermal_gen",
        name         = "Thermal Generator",
        branch       = "power",
        tier         = 3,
        cost         = { titanium = 12, crystal = 15, electronics = 10 },
        researchTime = 60,
        requires     = { "solar_cell" },
        unlocks      = { "thermal_plant", "power_grid_mk2" },
        description  = "Harvests energy from hydrothermal vents. Requires proximity to volcanic fissures.",
    },
    fusion_core = {
        id           = "fusion_core",
        name         = "Micro Fusion Core",
        branch       = "power",
        tier         = 4,
        cost         = { titanium = 20, electronics = 20, crystal = 15, circuit_board = 5 },
        researchTime = 100,
        requires     = { "thermal_gen" },
        unlocks      = { "fusion_reactor", "energy_weapons" },
        description  = "Compact deuterium fusion reactor. Clean, powerful, and terrifyingly experimental at this depth.",
    },
    quantum_gen = {
        id           = "quantum_gen",
        name         = "Quantum Vacuum Generator",
        branch       = "power",
        tier         = 5,
        cost         = { electronics = 30, crystal = 30, circuit_board = 10, composite = 10 },
        researchTime = 160,
        requires     = { "fusion_core" },
        unlocks      = { "quantum_reactor", "unlimited_power_grid" },
        description  = "Extracts energy from quantum vacuum fluctuations. The precursor ruins contained schematics for this. Somehow they knew.",
    },

    -- =========================================================================
    -- DEFENSE BRANCH (Tier 1-5)
    -- =========================================================================
    basic_turret = {
        id           = "basic_turret",
        name         = "Makeshift Turret",
        branch       = "defense",
        tier         = 1,
        cost         = { scrap_metal = 15, electronics = 3 },
        researchTime = 15,
        requires     = {},
        unlocks      = { "turret_building" },
        description  = "Repurposed deck-mount with salvaged ammunition. Fires slowly but deters the smaller creatures.",
    },
    laser_turret = {
        id           = "laser_turret",
        name         = "Focused Beam Turret",
        branch       = "defense",
        tier         = 2,
        cost         = { crystal = 15, electronics = 10, scrap_metal = 8 },
        researchTime = 35,
        requires     = { "basic_turret" },
        unlocks      = { "laser_turret_building", "targeting_system" },
        description  = "Crystal-focused thermal beam. Effective against organic threats. Inefficient in murky water.",
    },
    emp_field = {
        id           = "emp_field",
        name         = "EMP Field Generator",
        branch       = "defense",
        tier         = 3,
        cost         = { electronics = 20, crystal = 12, circuit_board = 5 },
        researchTime = 60,
        requires     = { "laser_turret" },
        unlocks      = { "emp_building", "stun_field" },
        description  = "Electromagnetic pulse emitter. Disrupts bioelectric organisms in a wide radius.",
    },
    shield_gen = {
        id           = "shield_gen",
        name         = "Pressure Shield",
        branch       = "defense",
        tier         = 4,
        cost         = { titanium = 15, crystal = 20, electronics = 15, composite = 5 },
        researchTime = 90,
        requires     = { "emp_field" },
        unlocks      = { "shield_building", "bubble_shield" },
        description  = "Generates a localized pressure differential that repels physical threats. Also stabilizes hull breaches.",
    },
    fortress = {
        id           = "fortress",
        name         = "Fortress Protocol",
        branch       = "defense",
        tier         = 5,
        cost         = { titanium = 30, electronics = 25, crystal = 20, circuit_board = 8, composite = 8 },
        researchTime = 150,
        requires     = { "shield_gen" },
        unlocks      = { "fortress_mode", "leviathan_deterrent" },
        description  = "Total base defense integration. All systems coordinate automatically. Even the leviathans hesitate.",
    },

    -- =========================================================================
    -- SCIENCE BRANCH (Tier 1-5)
    -- =========================================================================
    basic_scan = {
        id           = "basic_scan",
        name         = "Basic Scanner",
        branch       = "science",
        tier         = 1,
        cost         = { electronics = 5, scrap_metal = 5 },
        researchTime = 12,
        requires     = {},
        unlocks      = { "scanner_building", "resource_detection" },
        description  = "Repurposed SONAR display showing nearby terrain and resource deposits.",
    },
    sonar = {
        id           = "sonar",
        name         = "Active Sonar Array",
        branch       = "science",
        tier         = 2,
        cost         = { electronics = 12, crystal = 8, scrap_metal = 5 },
        researchTime = 28,
        requires     = { "basic_scan" },
        unlocks      = { "sonar_building", "creature_tracking" },
        description  = "Multi-ping sonar system. Maps terrain in real-time and tracks large fauna. They can hear it too.",
    },
    deep_scan = {
        id           = "deep_scan",
        name         = "Deep Resonance Scanner",
        branch       = "science",
        tier         = 3,
        cost         = { electronics = 18, crystal = 15, titanium = 5 },
        researchTime = 55,
        requires     = { "sonar" },
        unlocks      = { "deep_scanner", "anomaly_detection" },
        description  = "Low-frequency resonance mapper. Penetrates rock and sediment to reveal hidden chambers and deposits.",
    },
    mapping = {
        id           = "mapping",
        name         = "Full Cartographic Suite",
        branch       = "science",
        tier         = 4,
        cost         = { electronics = 22, crystal = 18, circuit_board = 8 },
        researchTime = 80,
        requires     = { "deep_scan" },
        unlocks      = { "full_map_reveal", "navigation_beacon" },
        description  = "Comprehensive bathymetric mapping system. Reveals entire floor layouts and marks points of interest.",
    },
    precursor_tech = {
        id           = "precursor_tech",
        name         = "Precursor Decryption",
        branch       = "science",
        tier         = 5,
        cost         = { electronics = 30, crystal = 25, circuit_board = 12, composite = 5 },
        researchTime = 180,
        requires     = { "mapping" },
        unlocks      = { "precursor_artifacts", "ascent_protocol" },
        description  = "The symbols on the ruins are not random. They are instructions. This technology decodes them -- and what they reveal changes everything.",
    },

    -- =========================================================================
    -- CROSS-BRANCH TECHS (require techs from multiple branches)
    -- =========================================================================
    advanced_materials = {
        id           = "advanced_materials",
        name         = "Advanced Materials",
        branch       = "engineering",
        tier         = 3,
        cost         = { titanium = 15, crystal = 15, electronics = 10 },
        researchTime = 70,
        requires     = { "reinforced_hull", "thermal_gen" },
        unlocks      = { "composite_crafting", "advanced_buildings" },
        description  = "Cross-disciplinary material science combining hull metallurgy with thermal treatment. Unlocks composite fabrication.",
    },
    deep_exploration = {
        id           = "deep_exploration",
        name         = "Deep Exploration Suite",
        branch       = "science",
        tier         = 4,
        cost         = { titanium = 20, electronics = 20, crystal = 15, biofilter = 5 },
        researchTime = 100,
        requires     = { "deep_scan", "pressure_hull", "biofilter_mk2" },
        unlocks      = { "deep_expeditions", "trench_survey" },
        description  = "Integrated exploration package: deep hull, advanced scanners, and life support rated for extended abyss operations.",
    },
    colony_mastery = {
        id           = "colony_mastery",
        name         = "Colony Mastery",
        branch       = "engineering",
        tier         = 5,
        cost         = { titanium = 30, electronics = 25, crystal = 20, biomass = 20, composite = 10, circuit_board = 8 },
        researchTime = 200,
        requires     = { "titan_hull", "closed_loop", "quantum_gen", "fortress", "precursor_tech" },
        unlocks      = { "endgame_buildings", "surface_signal", "colony_victory" },
        description  = "The culmination of all research. With this, the colony is self-sufficient, defended, and capable of signaling the surface. Or going deeper.",
    },
}

-- =============================================================================
-- Pre-computed lookup tables
-- =============================================================================

-- Branch -> ordered array of tech ids (sorted by tier)
local branchTechs = {}
for _, branchId in ipairs(BRANCHES) do
    branchTechs[branchId] = {}
end

-- Populate branch tech lists
for techId, tech in pairs(Tech.TREE) do
    local branch = tech.branch
    if branchTechs[branch] then
        branchTechs[branch][#branchTechs[branch] + 1] = techId
    end
end

-- Sort each branch by tier, then alphabetically within tier
for _, branchId in ipairs(BRANCHES) do
    table.sort(branchTechs[branchId], function(a, b)
        local ta = Tech.TREE[a]
        local tb = Tech.TREE[b]
        if ta.tier ~= tb.tier then
            return ta.tier < tb.tier
        end
        return a < b
    end)
end

-- All tech ids sorted for deterministic iteration
local allTechIds = {}
for techId in pairs(Tech.TREE) do
    allTechIds[#allTechIds + 1] = techId
end
table.sort(allTechIds)

-- =============================================================================
-- Module-local state
-- =============================================================================

local researched    = {}    -- { [techId] = true }
local currentResearch = {
    techId   = nil,
    elapsed  = 0,
    duration = 0,
}

-- =============================================================================
-- Internal helpers
-- =============================================================================

--- Check if all prerequisites for a tech are met.
--- @param techId string
--- @return boolean
local function prereqsMet(techId)
    local tech = Tech.TREE[techId]
    if not tech then return false end
    if not tech.requires or #tech.requires == 0 then return true end

    for _, reqId in ipairs(tech.requires) do
        if not researched[reqId] then
            return false
        end
    end
    return true
end

--- Check if the player has enough resources for a tech's cost.
--- @param cost table  { resourceId = amount, ... }
--- @param inventory table  { resourceId = amount, ... }
--- @return boolean
local function canAfford(cost, inventory)
    if not cost or not inventory then return false end

    for resourceId, amount in pairs(cost) do
        local have = inventory[resourceId] or 0
        if have < amount then
            return false
        end
    end
    return true
end

--- Deduct a tech's cost from an inventory table (mutates inventory).
--- Caller must verify canAfford first.
--- @param cost table
--- @param inventory table
local function deductCost(cost, inventory)
    for resourceId, amount in pairs(cost) do
        inventory[resourceId] = (inventory[resourceId] or 0) - amount
    end
end

-- =============================================================================
-- Public API -- Lifecycle
-- =============================================================================

--- Reset all research state.
function Tech.init()
    researched = {}
    currentResearch.techId   = nil
    currentResearch.elapsed  = 0
    currentResearch.duration = 0
end

-- =============================================================================
-- Public API -- Queries
-- =============================================================================

--- Get the ordered list of branch identifiers.
--- @return table  Array of branch id strings.
function Tech.getBranches()
    return BRANCHES
end

--- Get the display name for a branch.
--- @param branchId string
--- @return string
function Tech.getBranchName(branchId)
    return BRANCH_NAMES[branchId] or branchId
end

--- Get the UI color for a branch.
--- @param branchId string
--- @return table  {r, g, b}
function Tech.getBranchColor(branchId)
    return BRANCH_COLORS[branchId] or {0.5, 0.5, 0.5}
end

--- Get the techs within a branch, ordered by tier.
--- @param branchId string
--- @return table  Array of tech id strings.
function Tech.getTechsInBranch(branchId)
    return branchTechs[branchId] or {}
end

--- Get a single tech definition.
--- @param techId string
--- @return table|nil
function Tech.getTech(techId)
    return Tech.TREE[techId]
end

--- Get all tech ids in sorted order.
--- @return table
function Tech.getAllTechIds()
    return allTechIds
end

--- Check if a tech has been researched.
--- @param techId string
--- @return boolean
function Tech.isResearched(techId)
    return researched[techId] == true
end

--- Determine whether a tech can be researched right now.
--- Checks: not already researched, prerequisites met, resources available,
--- and no other research in progress.
--- @param techId string
--- @param inventory table  { resourceId = amount, ... }
--- @param researchedTechs table|nil  Optional override for researched set.
--- @return boolean  canResearch
--- @return string   reason (human-readable) if canResearch is false
function Tech.canResearch(techId, inventory, researchedTechs)
    local tech = Tech.TREE[techId]
    if not tech then
        return false, "Unknown technology."
    end

    -- Use provided set or internal state
    local resSet = researchedTechs or researched
    if resSet[techId] then
        return false, "Already researched."
    end

    -- Check prerequisites
    if tech.requires then
        for _, reqId in ipairs(tech.requires) do
            if not resSet[reqId] then
                local reqTech = Tech.TREE[reqId]
                local reqName = reqTech and reqTech.name or reqId
                return false, "Requires: " .. reqName
            end
        end
    end

    -- Check resources
    if not canAfford(tech.cost, inventory) then
        return false, "Insufficient resources."
    end

    -- Check if something is already being researched
    if currentResearch.techId then
        return false, "Research already in progress."
    end

    return true, "Ready to research."
end

-- =============================================================================
-- Public API -- Research actions
-- =============================================================================

--- Begin researching a tech. Deducts resources from inventory immediately.
--- @param techId string
--- @param inventory table  Mutable resource inventory.
--- @return boolean  True if research started successfully.
function Tech.startResearch(techId, inventory)
    local canStart, reason = Tech.canResearch(techId, inventory)
    if not canStart then
        return false
    end

    local tech = Tech.TREE[techId]
    deductCost(tech.cost, inventory)

    currentResearch.techId   = techId
    currentResearch.elapsed  = 0
    currentResearch.duration = tech.researchTime

    return true
end

--- Cancel current research. Does NOT refund resources (intentional penalty).
function Tech.cancelResearch()
    currentResearch.techId   = nil
    currentResearch.elapsed  = 0
    currentResearch.duration = 0
end

-- =============================================================================
-- Public API -- Update
-- =============================================================================

--- Main update tick. Advances current research and returns completed tech id.
--- @param dt number  Delta time in seconds.
--- @return string|nil  Completed tech id, or nil if nothing completed this frame.
function Tech.update(dt)
    if not currentResearch.techId then
        return nil
    end

    currentResearch.elapsed = currentResearch.elapsed + dt

    if currentResearch.elapsed >= currentResearch.duration then
        local completedId = currentResearch.techId
        researched[completedId] = true

        currentResearch.techId   = nil
        currentResearch.elapsed  = 0
        currentResearch.duration = 0

        return completedId
    end

    return nil
end

-- =============================================================================
-- Public API -- Research status queries
-- =============================================================================

--- Is research currently in progress?
--- @return boolean
function Tech.isResearching()
    return currentResearch.techId ~= nil
end

--- Get the tech id currently being researched.
--- @return string|nil
function Tech.getCurrentResearch()
    return currentResearch.techId
end

--- Get research progress as a 0-1 fraction.
--- @return number  0 if not researching, 0-1 during research.
function Tech.getResearchProgress()
    if not currentResearch.techId or currentResearch.duration <= 0 then
        return 0
    end
    return math_min(1.0, currentResearch.elapsed / currentResearch.duration)
end

--- Get remaining research time in seconds.
--- @return number
function Tech.getResearchTimeRemaining()
    if not currentResearch.techId then return 0 end
    return math_max(0, currentResearch.duration - currentResearch.elapsed)
end

--- Get the list of all completed tech ids.
--- @return table  Array of tech id strings.
function Tech.getResearchedList()
    local list = {}
    for techId in pairs(researched) do
        list[#list + 1] = techId
    end
    table.sort(list)
    return list
end

--- Get the number of researched techs.
--- @return number
function Tech.getResearchedCount()
    local count = 0
    for _ in pairs(researched) do
        count = count + 1
    end
    return count
end

--- Get the total number of techs in the tree.
--- @return number
function Tech.getTotalTechCount()
    return #allTechIds
end

-- =============================================================================
-- Public API -- Save / Load
-- =============================================================================

--- Serialize tech tree state for saving.
--- @return table
function Tech.getSaveData()
    local researchedList = {}
    for techId in pairs(researched) do
        researchedList[#researchedList + 1] = techId
    end

    local current = nil
    if currentResearch.techId then
        current = {
            techId   = currentResearch.techId,
            elapsed  = currentResearch.elapsed,
            duration = currentResearch.duration,
        }
    end

    return {
        researched = researchedList,
        current    = current,
    }
end

--- Restore tech tree state from saved data.
--- Gracefully handles nil or partial data.
--- @param data table|nil
function Tech.loadSaveData(data)
    if not data then return end

    Tech.init()

    if data.researched then
        for _, techId in ipairs(data.researched) do
            -- Only restore techs that still exist in the tree
            if Tech.TREE[techId] then
                researched[techId] = true
            end
        end
    end

    if data.current then
        local techId = data.current.techId
        if techId and Tech.TREE[techId] and not researched[techId] then
            currentResearch.techId   = techId
            currentResearch.elapsed  = data.current.elapsed or 0
            currentResearch.duration = data.current.duration or Tech.TREE[techId].researchTime
        end
    end
end

return Tech
