--[[
    Flooding / Water System
    Simulates water ingress from breach points, spreading to adjacent floor tiles.
    Provides per-tile water levels, room-wide water level, color tinting, fog
    modulation, and a submerged overlay for deeply flooded conditions.

    Designed to be injected into the Raycaster via Raycaster.setFlooding(Flooding).
    Mirrors the Corruption module pattern for consistency.
]]

local Flooding = {}

-- Cached math functions for hot paths
local math_floor = math.floor
local math_min   = math.min
local math_max   = math.max
local math_abs   = math.abs
local math_sin   = math.sin
local math_sqrt  = math.sqrt

-- ============================================================
-- Constants
-- ============================================================

local SPREAD_INTERVAL   = 0.5    -- Seconds between spread ticks
local SPREAD_CHANCE     = 0.30   -- Base probability to spread to an adjacent tile
local MAX_WATER         = 1.0    -- Maximum per-tile water level
local WATER_GROWTH      = 0.06   -- Per-tile water increment each tick
local BREACH_PUMP_RATE  = 0.12   -- How much a breach adds to its tile per tick

-- Water color palette (blue-green, darkens with depth)
local COLOR_SHALLOW = {0.15, 0.35, 0.50}   -- Light aqua
local COLOR_MEDIUM  = {0.10, 0.25, 0.45}   -- Mid blue-green
local COLOR_DEEP    = {0.05, 0.15, 0.35}   -- Dark navy-teal

-- Fog multiplier range: 1.0 (no water) .. FOG_MULT_MAX (fully flooded room)
local FOG_MULT_BASE = 1.0
local FOG_MULT_MAX  = 2.2

-- Submerged overlay threshold
local SUBMERGE_THRESHOLD = 0.8

-- ============================================================
-- Module-local state
-- ============================================================

local floodedTiles  = {}   -- { ["x,y"] = waterLevel (0-1) }
local breachPoints  = {}   -- { ["x,y"] = { x=int, y=int, strength=number } }
local roomWaterLvl  = 0    -- Global room-wide water level (0-1)
local spreadTimer   = 0

-- Adjacent tile offset table (4-connected)
local ADJ_OFFSETS = {
    { -1,  0 },
    {  1,  0 },
    {  0, -1 },
    {  0,  1 },
}

-- ============================================================
-- Helpers
-- ============================================================

local function tileKey(x, y)
    return x .. "," .. y
end

local function parseTileKey(key)
    local sx, sy = key:match("^(-?%d+),(-?%d+)$")
    return tonumber(sx), tonumber(sy)
end

-- Linear interpolation
local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Clamp to 0-1
local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

-- ============================================================
-- Public API -- lifecycle
-- ============================================================

function Flooding.init()
    floodedTiles = {}
    breachPoints = {}
    roomWaterLvl = 0
    spreadTimer  = 0
end

function Flooding.clear()
    floodedTiles = {}
    breachPoints = {}
    roomWaterLvl = 0
    spreadTimer  = 0
end

function Flooding.update(dt, map)
    spreadTimer = spreadTimer + dt

    if spreadTimer >= SPREAD_INTERVAL then
        spreadTimer = spreadTimer - SPREAD_INTERVAL
        Flooding.spread(map)
    end
end

-- ============================================================
-- Breach management
-- ============================================================

--- Add or replace a breach point at integer tile coordinates.
--- @param x number  Integer tile X
--- @param y number  Integer tile Y
--- @param strength number  Flow rate multiplier (default 1.0)
function Flooding.addBreach(x, y, strength)
    x = math_floor(x)
    y = math_floor(y)
    local id = tileKey(x, y)
    breachPoints[id] = {
        x = x,
        y = y,
        strength = strength or 1.0,
    }
    -- Breach tile gets an immediate kick of water
    floodedTiles[id] = math_min(MAX_WATER, (floodedTiles[id] or 0) + BREACH_PUMP_RATE)
end

function Flooding.removeBreach(x, y)
    x = math_floor(x)
    y = math_floor(y)
    breachPoints[tileKey(x, y)] = nil
end

-- ============================================================
-- Room-wide / per-tile setters
-- ============================================================

function Flooding.setRoomWaterLevel(level)
    roomWaterLvl = clamp01(level)
end

function Flooding.setTileWater(x, y, level)
    x = math_floor(x)
    y = math_floor(y)
    local clamped = clamp01(level)
    if clamped <= 0 then
        floodedTiles[tileKey(x, y)] = nil
    else
        floodedTiles[tileKey(x, y)] = clamped
    end
end

-- ============================================================
-- Spread logic  (called once per SPREAD_INTERVAL)
-- ============================================================

function Flooding.spread(map)
    -- 1. Pump water at breach points
    for id, breach in pairs(breachPoints) do
        local cur = floodedTiles[id] or 0
        floodedTiles[id] = math_min(MAX_WATER, cur + BREACH_PUMP_RATE * breach.strength)
    end

    -- 2. Spread from flooded tiles to walkable neighbours
    local additions = {}   -- collect new/updated levels before applying

    for id, level in pairs(floodedTiles) do
        if level > 0.15 then  -- Only spread from tiles with meaningful water
            local ox, oy = parseTileKey(id)
            if ox then
                for i = 1, 4 do
                    local off = ADJ_OFFSETS[i]
                    local ax, ay = ox + off[1], oy + off[2]

                    -- Only flood walkable tiles (0 = empty, 11/12 = stairs)
                    if map then
                        local tile = map:getTile(ax, ay)
                        if tile ~= 0 and tile ~= 11 and tile ~= 12 then
                            goto continue_adj
                        end
                    end

                    -- Probabilistic spread, weighted by source level
                    if math.random() < SPREAD_CHANCE * level then
                        local aid = tileKey(ax, ay)
                        local curAdj = floodedTiles[aid] or 0
                        local newAdj = math_min(MAX_WATER, curAdj + WATER_GROWTH)
                        -- Water flows downhill: neighbour cannot exceed source
                        newAdj = math_min(newAdj, level)
                        if newAdj > curAdj then
                            additions[aid] = math_max(additions[aid] or 0, newAdj)
                        end
                    end

                    ::continue_adj::
                end
            end
        end

        -- Existing flooded tiles slowly deepen (not at breaches, those are pumped above)
        if not breachPoints[id] then
            local newLevel = math_min(MAX_WATER, level + WATER_GROWTH * 0.3)
            additions[id] = math_max(additions[id] or 0, newLevel)
        end
    end

    -- Apply accumulated changes
    for id, lvl in pairs(additions) do
        floodedTiles[id] = lvl
    end
end

-- ============================================================
-- Query API (called by Raycaster every frame -- keep fast)
-- ============================================================

--- Per-tile water level. Hot path -- no table creation.
function Flooding.getLevelFast(tileX, tileY)
    local id = math_floor(tileX) .. "," .. math_floor(tileY)
    return floodedTiles[id] or 0
end

--- Is this tile a breach point?
function Flooding.isBreachFast(x, y)
    local id = math_floor(x) .. "," .. math_floor(y)
    return breachPoints[id] ~= nil
end

--- Room-wide water level (0-1).
function Flooding.getRoomWaterLevel()
    return roomWaterLvl
end

--- Return reference to the full flooded-tile table.
--- Keys are "x,y", values are 0-1.
function Flooding.getAllFlooded()
    return floodedTiles
end

-- ============================================================
-- Fog modulation
-- ============================================================

--- Returns a multiplier >= 1.0 applied to the atmosphere fog density.
--- Considers both room-wide flooding and the average breach saturation
--- so that any flooding noticeably reduces visibility.
function Flooding.getFogMultiplier()
    -- Room-wide contribution
    local roomContrib = roomWaterLvl * (FOG_MULT_MAX - FOG_MULT_BASE)

    -- Breach contribution: if there are active breaches, bump fog slightly
    local breachContrib = 0
    local breachCount = 0
    for id, breach in pairs(breachPoints) do
        breachContrib = breachContrib + (floodedTiles[id] or 0) * breach.strength
        breachCount = breachCount + 1
    end
    if breachCount > 0 then
        breachContrib = (breachContrib / breachCount) * 0.4  -- gentle extra fog
    end

    return FOG_MULT_BASE + roomContrib + breachContrib
end

-- ============================================================
-- Color / tinting
-- ============================================================

--- Water color for a given depth. Returns {r, g, b}.
function Flooding.getColor(waterLevel)
    if waterLevel >= 0.7 then
        return COLOR_DEEP
    elseif waterLevel >= 0.35 then
        return COLOR_MEDIUM
    else
        return COLOR_SHALLOW
    end
end

--- Tint an RGB triplet toward blue-green based on water level.
--- @return r, g, b  (each 0-1, clamped)
function Flooding.applyTint(r, g, b, waterLevel)
    if waterLevel <= 0 then
        return r, g, b
    end

    local tint = Flooding.getColor(waterLevel)
    local t = waterLevel * 0.65  -- blend strength

    -- Darken as well as shift hue: deeper water absorbs more light
    local darken = 1.0 - waterLevel * 0.35

    local nr = (r * (1 - t) + tint[1] * t) * darken
    local ng = (g * (1 - t) + tint[2] * t) * darken
    local nb = (b * (1 - t) + tint[3] * t) * darken

    return clamp01(nr), clamp01(ng), clamp01(nb)
end

-- ============================================================
-- Submerged overlay
-- ============================================================

--- When the room water level exceeds the SUBMERGE_THRESHOLD, return an
--- overlay descriptor consumed by Raycaster.renderSubmergedOverlay().
--- Returns a table { r, g, b, a } or nil.
function Flooding.getSubmergedOverlay()
    if roomWaterLvl < SUBMERGE_THRESHOLD then
        return nil
    end

    -- Intensity ramps from threshold to 1.0
    local t = (roomWaterLvl - SUBMERGE_THRESHOLD) / (1.0 - SUBMERGE_THRESHOLD)
    t = clamp01(t)

    -- Deep blue overlay that intensifies with depth
    return {
        r = lerp(0.02, 0.01, t),
        g = lerp(0.08, 0.04, t),
        b = lerp(0.20, 0.15, t),
        a = lerp(0.30, 0.65, t),
    }
end

-- ============================================================
-- Serialisation
-- ============================================================

function Flooding.getSaveData()
    -- Serialise breach points into a simple list
    local breachList = {}
    for id, bp in pairs(breachPoints) do
        breachList[#breachList + 1] = { x = bp.x, y = bp.y, strength = bp.strength }
    end

    -- Serialise flooded tiles
    local tileList = {}
    for id, level in pairs(floodedTiles) do
        local tx, ty = parseTileKey(id)
        if tx then
            tileList[#tileList + 1] = { x = tx, y = ty, level = level }
        end
    end

    return {
        breaches       = breachList,
        tiles          = tileList,
        roomWaterLevel = roomWaterLvl,
    }
end

function Flooding.loadSaveData(data)
    if not data then return end

    Flooding.clear()

    roomWaterLvl = data.roomWaterLevel or 0

    if data.breaches then
        for _, bp in ipairs(data.breaches) do
            if bp.x and bp.y then
                local id = tileKey(bp.x, bp.y)
                breachPoints[id] = { x = bp.x, y = bp.y, strength = bp.strength or 1.0 }
            end
        end
    end

    if data.tiles then
        for _, t in ipairs(data.tiles) do
            if t.x and t.y and t.level then
                floodedTiles[tileKey(t.x, t.y)] = clamp01(t.level)
            end
        end
    end
end

return Flooding
