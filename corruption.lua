--[[
    Corruption System
    Simulates spreading corruption like the Lich's influence
    Corruption spreads from source points and affects tiles over time
]]

local Corruption = {}

-- Corruption state
local corruptedTiles = {}  -- {["x,y"] = corruption_level (0-1)}
local corruptionSources = {}  -- Points where corruption originates
local spreadTimer = 0
local SPREAD_INTERVAL = 0.5  -- How often corruption spreads (seconds)
local SPREAD_CHANCE = 0.3    -- Chance to spread to adjacent tile
local MAX_CORRUPTION = 1.0
local CORRUPTION_GROWTH = 0.1  -- How much corruption increases per tick

-- Visual settings
Corruption.COLORS = {
    low = {0.4, 0.2, 0.5},      -- Light purple
    medium = {0.3, 0.1, 0.4},   -- Medium purple
    high = {0.2, 0.05, 0.3},    -- Dark purple
    source = {0.5, 0.0, 0.6},   -- Bright purple (source)
}

function Corruption.init()
    corruptedTiles = {}
    corruptionSources = {}
    spreadTimer = 0
end

-- Add a corruption source
function Corruption.addSource(x, y, strength)
    local id = x .. "," .. y
    corruptionSources[id] = {
        x = x,
        y = y,
        strength = strength or 1.0,
    }
    -- Source tiles are fully corrupted
    corruptedTiles[id] = MAX_CORRUPTION
end

-- Remove a corruption source
function Corruption.removeSource(x, y)
    local id = x .. "," .. y
    corruptionSources[id] = nil
end

-- Get corruption level at a tile (0 = none, 1 = fully corrupted)
function Corruption.getLevel(x, y)
    local id = math.floor(x) .. "," .. math.floor(y)
    return corruptedTiles[id] or 0
end

-- Check if tile is a corruption source
function Corruption.isSource(x, y)
    local id = math.floor(x) .. "," .. math.floor(y)
    return corruptionSources[id] ~= nil
end

-- Get all corrupted tiles
function Corruption.getAllCorrupted()
    return corruptedTiles
end

-- Get all sources
function Corruption.getSources()
    return corruptionSources
end

-- Update corruption spread
function Corruption.update(dt, map)
    spreadTimer = spreadTimer + dt

    if spreadTimer >= SPREAD_INTERVAL then
        spreadTimer = spreadTimer - SPREAD_INTERVAL
        Corruption.spread(map)
    end
end

-- Spread corruption to adjacent tiles
function Corruption.spread(map)
    local newCorruption = {}

    -- First, increase corruption at sources
    for id, source in pairs(corruptionSources) do
        corruptedTiles[id] = MAX_CORRUPTION
    end

    -- Then spread from all corrupted tiles
    for id, level in pairs(corruptedTiles) do
        local x, y = id:match("(-?%d+),(-?%d+)")
        x, y = tonumber(x), tonumber(y)

        if level > 0.3 then  -- Only spread if corruption is strong enough
            -- Check adjacent tiles (4 directions)
            local adjacent = {
                {x - 1, y},
                {x + 1, y},
                {x, y - 1},
                {x, y + 1},
            }

            for _, pos in ipairs(adjacent) do
                local ax, ay = pos[1], pos[2]
                local aid = ax .. "," .. ay

                -- Can only corrupt empty tiles (not walls)
                local tile = map:getTile(ax, ay)
                if tile == 0 or tile == 11 or tile == 12 then  -- Empty or stairs
                    if math.random() < SPREAD_CHANCE * level then
                        local currentLevel = corruptedTiles[aid] or 0
                        local newLevel = math.min(MAX_CORRUPTION, currentLevel + CORRUPTION_GROWTH)
                        newCorruption[aid] = math.max(newCorruption[aid] or 0, newLevel)
                    end
                end
            end
        end

        -- Existing corruption grows slightly
        if not corruptionSources[id] then
            local newLevel = math.min(MAX_CORRUPTION, level + CORRUPTION_GROWTH * 0.5)
            newCorruption[id] = math.max(newCorruption[id] or 0, newLevel)
        end
    end

    -- Apply new corruption levels
    for id, level in pairs(newCorruption) do
        corruptedTiles[id] = level
    end
end

-- Get corruption color based on level
function Corruption.getColor(level)
    if level >= 0.8 then
        return Corruption.COLORS.high
    elseif level >= 0.4 then
        return Corruption.COLORS.medium
    else
        return Corruption.COLORS.low
    end
end

-- Apply corruption tint to a color
function Corruption.applyTint(r, g, b, corruptionLevel)
    if corruptionLevel <= 0 then
        return r, g, b
    end

    local tint = Corruption.getColor(corruptionLevel)
    local t = corruptionLevel * 0.7  -- How much to blend

    return
        r * (1 - t) + tint[1] * t,
        g * (1 - t) + tint[2] * t,
        b * (1 - t) + tint[3] * t
end

-- Clear all corruption
function Corruption.clear()
    corruptedTiles = {}
    corruptionSources = {}
end

-- Get corruption stats
function Corruption.getStats()
    local count = 0
    local totalLevel = 0
    for id, level in pairs(corruptedTiles) do
        count = count + 1
        totalLevel = totalLevel + level
    end
    return {
        tileCount = count,
        sourceCount = 0,
        averageLevel = count > 0 and (totalLevel / count) or 0,
    }
end

-- Count sources
function Corruption.getSourceCount()
    local count = 0
    for _ in pairs(corruptionSources) do
        count = count + 1
    end
    return count
end

return Corruption
