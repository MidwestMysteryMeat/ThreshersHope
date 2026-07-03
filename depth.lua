--[[
    Depth Zone System
    Manages depth layers for an underwater raycaster environment.
    Each floor in the map system maps to a depth zone, with deeper
    zones increasing pressure, reducing light, and escalating danger.

    Floor 1 = shallowest (Surface/Shallows)
    Higher floors = deeper water

    Depth zones affect:
    - Atmosphere (darker, foggier at depth)
    - Pressure damage scaling
    - Enemy difficulty multipliers
    - Resource availability per zone
]]

local Depth = {}

-- Local references for performance
local math_floor = math.floor
local math_min = math.min
local math_max = math.max

-- Module-local state
local totalFloors = 1
local floorDepthMap = {}    -- floorNum -> depth in meters
local floorZoneCache = {}   -- floorNum -> zone index (cached lookup)
local initialized = false

-- Zone definitions (ordered shallow to deep)
local zones = {
    {
        name = "The Surface",
        minDepth = 0,
        maxDepth = 0,
        floors = {},
        pressure = 1.0,
        lightReduction = 0.0,
        enemyDifficulty = 0.0,
        atmospherePreset = "surface",
        resources = {},
        color = {0.5, 0.85, 1.0},
    },
    {
        name = "The Shallows",
        minDepth = 0,
        maxDepth = 50,
        floors = {},
        pressure = 1.0,
        lightReduction = 0.1,
        enemyDifficulty = 0.5,
        atmospherePreset = "underwater",
        resources = {"scrap_metal", "biomass"},
        color = {0.3, 0.7, 0.9},
    },
    {
        name = "Mid-Depth",
        minDepth = 50,
        maxDepth = 150,
        floors = {},
        pressure = 2.5,
        lightReduction = 0.35,
        enemyDifficulty = 1.0,
        atmospherePreset = "underwater",
        resources = {"scrap_metal", "biomass", "rare_minerals", "coral"},
        color = {0.2, 0.5, 0.75},
    },
    {
        name = "The Deep",
        minDepth = 150,
        maxDepth = 300,
        floors = {},
        pressure = 5.0,
        lightReduction = 0.6,
        enemyDifficulty = 1.8,
        atmospherePreset = "deep",
        resources = {"rare_minerals", "bioluminescent_flora", "pressure_crystals"},
        color = {0.1, 0.3, 0.55},
    },
    {
        name = "The Abyss",
        minDepth = 300,
        maxDepth = 500,
        floors = {},
        pressure = 10.0,
        lightReduction = 0.85,
        enemyDifficulty = 3.0,
        atmospherePreset = "abyss",
        resources = {"pressure_crystals", "abyssal_ore", "void_kelp"},
        color = {0.05, 0.15, 0.35},
    },
    {
        name = "The Trench",
        minDepth = 500,
        maxDepth = 1000,
        floors = {},
        pressure = 20.0,
        lightReduction = 0.97,
        enemyDifficulty = 5.0,
        atmospherePreset = "trench",
        resources = {"abyssal_ore", "leviathan_bone", "trench_diamond"},
        color = {0.02, 0.05, 0.15},
    },
}

-- Number of zones (excludes Surface since floor 1 maps to Shallows)
local ZONE_COUNT = #zones
-- Surface zone is index 1, Shallows is index 2, etc.
local SURFACE_ZONE = 1
local SHALLOWS_ZONE = 2

-- Lerp helper
local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Lerp for color tables
local function lerpColor(a, b, t)
    return {
        lerp(a[1], b[1], t),
        lerp(a[2], b[2], t),
        lerp(a[3], b[3], t),
    }
end

-- Map a floor number to its depth in meters.
-- Floor 1 is the shallowest playable floor (start of Shallows).
-- Floors are distributed evenly across the total depth range.
local function computeFloorDepth(floorNum, numFloors)
    if numFloors <= 0 then return 0 end
    if numFloors == 1 then return 25 end -- Single floor sits mid-Shallows

    -- Floor 1 = 10m (top of Shallows, not zero to keep it underwater)
    -- Last floor = maxDepth of the deepest zone that has floors assigned
    local minPlayableDepth = 10
    local maxPlayableDepth = zones[ZONE_COUNT].maxDepth

    -- Scale total depth range based on number of floors available.
    -- Few floors should not stretch to the Trench; many floors should.
    -- Use a mapping: 1 floor = 25m, 2 = 80m, 3 = 150m, scaling up
    local depthCaps = {
        [1] = 25,
        [2] = 80,
        [3] = 150,
        [4] = 250,
        [5] = 400,
        [6] = 550,
    }
    local maxReachable = depthCaps[numFloors]
    if not maxReachable then
        -- For more than 6 floors, scale linearly toward the cap
        maxReachable = math_min(maxPlayableDepth, 100 * numFloors)
    end

    local t = (floorNum - 1) / (numFloors - 1)
    return minPlayableDepth + t * (maxReachable - minPlayableDepth)
end

-- Find which zone a given depth falls into.
-- Returns zone index (1-based into the zones table).
local function findZoneIndex(depthMeters)
    -- Surface zone: exactly 0m depth
    if depthMeters <= 0 then
        return SURFACE_ZONE
    end

    -- Walk zones from Shallows onward
    for i = SHALLOWS_ZONE, ZONE_COUNT do
        local zone = zones[i]
        if depthMeters <= zone.maxDepth then
            return i
        end
    end

    -- Deeper than any defined zone: clamp to Trench
    return ZONE_COUNT
end

-- Build the floor-to-zone mapping and assign floor lists to zones.
local function buildFloorMapping(numFloors)
    floorDepthMap = {}
    floorZoneCache = {}

    -- Clear existing floor assignments
    for i = 1, ZONE_COUNT do
        zones[i].floors = {}
    end

    for f = 1, numFloors do
        local depth = computeFloorDepth(f, numFloors)
        floorDepthMap[f] = depth

        local zoneIdx = findZoneIndex(depth)
        floorZoneCache[f] = zoneIdx
        table.insert(zones[zoneIdx].floors, f)
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--- Initialize the depth system with the total number of playable floors.
--- Must be called before any queries. Safe to call multiple times
--- (e.g., when the map changes).
--- @param numFloors number  Total floor count from the map
function Depth.init(numFloors)
    totalFloors = math_max(1, numFloors or 1)
    buildFloorMapping(totalFloors)
    initialized = true
end

--- Return the full zone data table for the given floor number.
--- Returns a defensive copy of resource list but shares color reference
--- for performance (colors are treated as read-only).
--- @param floorNum number
--- @return table  Zone data with name, depth range, pressure, etc.
function Depth.getZoneForFloor(floorNum)
    if not initialized then Depth.init(1) end

    floorNum = math_max(1, math_min(floorNum or 1, totalFloors))
    local zoneIdx = floorZoneCache[floorNum]
    if not zoneIdx then
        zoneIdx = SHALLOWS_ZONE
    end
    return zones[zoneIdx]
end

--- Convenience: get zone for the map's current floor.
--- @param map table  Map object with .currentFloor field
--- @return table  Zone data
function Depth.getCurrentZone(map)
    if not map then
        return zones[SHALLOWS_ZONE]
    end
    local floor = map.currentFloor or 1
    return Depth.getZoneForFloor(floor)
end

--- Get depth in meters for a given floor number.
--- @param floorNum number
--- @return number  Depth in meters
function Depth.getDepthMeters(floorNum)
    if not initialized then Depth.init(1) end

    floorNum = math_max(1, math_min(floorNum or 1, totalFloors))
    return floorDepthMap[floorNum] or 0
end

--- Get pressure multiplier for a floor.
--- Interpolates between zone boundaries for smooth pressure changes.
--- 1.0 at the surface, increasing with depth.
--- @param floorNum number
--- @return number  Pressure multiplier
function Depth.getPressureMultiplier(floorNum)
    if not initialized then Depth.init(1) end

    floorNum = math_max(1, math_min(floorNum or 1, totalFloors))
    local depth = floorDepthMap[floorNum] or 0
    local zoneIdx = floorZoneCache[floorNum] or SHALLOWS_ZONE
    local zone = zones[zoneIdx]

    -- If this is a boundary zone (Surface), return its flat value
    if zoneIdx == SURFACE_ZONE then
        return zone.pressure
    end

    -- Interpolate pressure within the zone based on how deep we are
    local zoneSpan = zone.maxDepth - zone.minDepth
    if zoneSpan <= 0 then
        return zone.pressure
    end

    local prevZone = zones[zoneIdx - 1]
    local prevPressure = prevZone and prevZone.pressure or 1.0
    local t = (depth - zone.minDepth) / zoneSpan

    return lerp(prevPressure, zone.pressure, t)
end

--- Get light reduction factor for a floor.
--- 0.0 = full light (surface), 1.0 = total darkness.
--- Interpolates smoothly between zone boundaries.
--- @param floorNum number
--- @return number  Light reduction (0-1)
function Depth.getLightReduction(floorNum)
    if not initialized then Depth.init(1) end

    floorNum = math_max(1, math_min(floorNum or 1, totalFloors))
    local depth = floorDepthMap[floorNum] or 0
    local zoneIdx = floorZoneCache[floorNum] or SHALLOWS_ZONE
    local zone = zones[zoneIdx]

    if zoneIdx == SURFACE_ZONE then
        return zone.lightReduction
    end

    local zoneSpan = zone.maxDepth - zone.minDepth
    if zoneSpan <= 0 then
        return zone.lightReduction
    end

    local prevZone = zones[zoneIdx - 1]
    local prevLight = prevZone and prevZone.lightReduction or 0.0
    local t = (depth - zone.minDepth) / zoneSpan

    return lerp(prevLight, zone.lightReduction, t)
end

--- Get enemy difficulty multiplier for a floor.
--- Scales enemy stats (health, damage, speed) by this factor.
--- @param floorNum number
--- @return number  Difficulty multiplier
function Depth.getEnemyDifficulty(floorNum)
    if not initialized then Depth.init(1) end

    floorNum = math_max(1, math_min(floorNum or 1, totalFloors))
    local zoneIdx = floorZoneCache[floorNum] or SHALLOWS_ZONE
    local zone = zones[zoneIdx]

    -- Interpolate within zone for gradual difficulty ramp
    local depth = floorDepthMap[floorNum] or 0
    if zoneIdx == SURFACE_ZONE then
        return zone.enemyDifficulty
    end

    local zoneSpan = zone.maxDepth - zone.minDepth
    if zoneSpan <= 0 then
        return zone.enemyDifficulty
    end

    local prevZone = zones[zoneIdx - 1]
    local prevDiff = prevZone and prevZone.enemyDifficulty or 0.0
    local t = (depth - zone.minDepth) / zoneSpan

    return lerp(prevDiff, zone.enemyDifficulty, t)
end

--- Get the display name for the zone at a given floor.
--- @param floorNum number
--- @return string  Zone name for HUD display
function Depth.getZoneName(floorNum)
    local zone = Depth.getZoneForFloor(floorNum)
    return zone.name
end

--- Get the indicator color for the zone at a given floor.
--- Returns an interpolated color between adjacent zone colors
--- based on exact depth for smooth transitions.
--- @param floorNum number
--- @return table  {r, g, b} color values (0-1)
function Depth.getZoneColor(floorNum)
    if not initialized then Depth.init(1) end

    floorNum = math_max(1, math_min(floorNum or 1, totalFloors))
    local depth = floorDepthMap[floorNum] or 0
    local zoneIdx = floorZoneCache[floorNum] or SHALLOWS_ZONE
    local zone = zones[zoneIdx]

    if zoneIdx == SURFACE_ZONE or zoneIdx == SHALLOWS_ZONE then
        return {zone.color[1], zone.color[2], zone.color[3]}
    end

    local zoneSpan = zone.maxDepth - zone.minDepth
    if zoneSpan <= 0 then
        return {zone.color[1], zone.color[2], zone.color[3]}
    end

    local prevZone = zones[zoneIdx - 1]
    local t = (depth - zone.minDepth) / zoneSpan

    return lerpColor(prevZone.color, zone.color, t)
end

--- Get the atmosphere preset string for the zone at a given floor.
--- Used to drive the Atmosphere system's environment selection.
--- @param floorNum number
--- @return string  Atmosphere preset identifier
function Depth.getAtmospherePreset(floorNum)
    local zone = Depth.getZoneForFloor(floorNum)
    return zone.atmospherePreset
end

--- Get the list of available resources for the zone at a given floor.
--- Returns a copy of the resource table to prevent mutation.
--- @param floorNum number
--- @return table  Array of resource identifier strings
function Depth.getResources(floorNum)
    local zone = Depth.getZoneForFloor(floorNum)
    local copy = {}
    for i, res in ipairs(zone.resources) do
        copy[i] = res
    end
    return copy
end

--- Check whether a specific resource is available at a given floor.
--- @param floorNum number
--- @param resourceId string  Resource identifier to check
--- @return boolean
function Depth.hasResource(floorNum, resourceId)
    if not resourceId then return false end
    local zone = Depth.getZoneForFloor(floorNum)
    for _, res in ipairs(zone.resources) do
        if res == resourceId then
            return true
        end
    end
    return false
end

--- Get all zone definitions (read-only reference).
--- @return table  Array of zone data tables
function Depth.getAllZones()
    return zones
end

--- Get the total number of defined depth zones.
--- @return number
function Depth.getZoneCount()
    return ZONE_COUNT
end

--- Get a formatted depth string for HUD display.
--- e.g. "127m" or "Surface"
--- @param floorNum number
--- @return string
function Depth.getDepthString(floorNum)
    local depth = Depth.getDepthMeters(floorNum)
    if depth <= 0 then
        return "Surface"
    end
    return math_floor(depth) .. "m"
end

--- Get a full status string for HUD display.
--- e.g. "The Deep - 217m | Pressure: x5.0"
--- @param floorNum number
--- @return string
function Depth.getStatusString(floorNum)
    local zone = Depth.getZoneForFloor(floorNum)
    local depth = Depth.getDepthMeters(floorNum)
    local pressure = Depth.getPressureMultiplier(floorNum)
    local depthStr = math_floor(depth) .. "m"
    return zone.name .. " - " .. depthStr .. " | Pressure: x" .. string.format("%.1f", pressure)
end

--- Compute a fog color tint based on depth.
--- Blends from clear blue at surface toward dark navy in the deep.
--- Intended as an overlay multiplier for the atmosphere fog color.
--- @param floorNum number
--- @return table  {r, g, b} fog tint
function Depth.getFogTint(floorNum)
    local lightReduc = Depth.getLightReduction(floorNum)
    -- Surface: bright cyan-blue fog. Deep: near-black blue fog.
    local surfaceFog = {0.15, 0.35, 0.55}
    local deepFog = {0.02, 0.04, 0.08}
    return lerpColor(surfaceFog, deepFog, lightReduc)
end

--- Compute an ambient light multiplier based on depth.
--- Reduces the base ambient light from the atmosphere system.
--- @param floorNum number
--- @return number  Multiplier (0-1) to apply to ambient light
function Depth.getAmbientMultiplier(floorNum)
    local lightReduc = Depth.getLightReduction(floorNum)
    -- Never reduce below 5% ambient (bioluminescence / equipment)
    return math_max(0.05, 1.0 - lightReduc)
end

--- Compute a view distance multiplier based on depth.
--- Reduces max ray steps in deeper zones.
--- @param floorNum number
--- @return number  Multiplier (0-1) to apply to max view distance
function Depth.getViewDistanceMultiplier(floorNum)
    local lightReduc = Depth.getLightReduction(floorNum)
    -- View distance falls off faster than ambient light
    -- Never below 30% (sonar / equipment provides baseline visibility)
    return math_max(0.3, 1.0 - lightReduc * 0.8)
end

return Depth
