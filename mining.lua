--[[
    Mining System
    Handles LMB hold-to-mine mechanics for an underwater city builder raycaster.
    Player aims at a wall tile, holds LMB, and after a duration the wall is
    converted to a floor tile and resource items are spawned.

    Integration points:
      - map:getTile(x,y) / map:setTile(x,y,value) for tile queries and conversion
      - Sprites.addItem(x,y,itemType) for spawning resource drops
      - Resources module (optional) for per-wall-type yield tables
      - Raycaster DDA for finding the aimed wall tile

    Exposed API:
      Mining.init()
      Mining.update(dt, playerX, playerY, playerDirX, playerDirY, map)
      Mining.startMining()
      Mining.stopMining()
      Mining.isActive() -> boolean
      Mining.getProgress() -> 0-1
      Mining.getTargetTile() -> tileX, tileY or nil
      Mining.drawHUD(screenW, screenH)
      Mining.setOnMineComplete(callback)
]]

local Mining = {}

-- Cached math functions for hot paths
local math_floor = math.floor
local math_abs   = math.abs
local math_min   = math.min
local math_max   = math.max
local math_sqrt  = math.sqrt
local math_sin   = math.sin

-- =============================================================================
-- Constants
-- =============================================================================

local MINING_RANGE        = 2.5    -- Maximum distance (in tiles) to mine a wall
local DDA_MAX_STEPS       = 20     -- DDA ray march step limit

-- Tile types that cannot be mined
local UNMINED_TILES = {
    [0]  = true,  -- empty / floor
    [10] = true,  -- door
    [11] = true,  -- stairs up
    [12] = true,  -- stairs down
}

-- Mining duration per wall type (seconds). Walls 1-9; default 3.0s.
-- Harder/rarer wall materials take longer.
local MINE_TIME = {
    [1] = 2.0,   -- basic stone
    [2] = 2.5,   -- secondary stone
    [3] = 3.0,   -- decorative / reinforced
    [4] = 3.5,   -- special material
    [5] = 4.0,   -- rare material
}
local MINE_TIME_DEFAULT = 3.0

-- Default resource drops per wall type when no Resources module is present.
-- Each entry: { {itemType, minQty, maxQty}, ... }
local DEFAULT_DROPS = {
    [1] = { {"scrap_metal", 1, 3} },
    [2] = { {"crystal", 1, 2} },
    [3] = { {"biomass", 2, 4} },
    [4] = { {"electronics", 1, 2} },
    [5] = { {"titanium", 1, 2} },
}
local DEFAULT_DROPS_FALLBACK = { {"scrap_metal", 1, 2} }

-- HUD progress bar dimensions
local BAR_WIDTH           = 120
local BAR_HEIGHT          = 8
local BAR_Y_OFFSET        = 30    -- pixels below screen center (below crosshair)
local BAR_BG_COLOR        = {0.12, 0.12, 0.15, 0.85}
local BAR_FILL_COLOR      = {0.25, 0.75, 0.90}
local BAR_BORDER_COLOR    = {0.35, 0.55, 0.70, 0.90}
local BAR_FLASH_COLOR     = {0.60, 0.95, 1.00}

-- =============================================================================
-- Module-local state
-- =============================================================================

local active       = false   -- Is the player currently holding mine button
local progress     = 0       -- 0-1 progress toward completing the mine
local targetX      = nil     -- Tile X of current mining target
local targetY      = nil     -- Tile Y of current mining target
local targetType   = 0       -- Wall type (1-9) of current target
local miningTime   = 0       -- Total time needed for current target

-- Callback fired when mining completes
local onMineComplete = nil

-- Optional external modules (set via Mining.setResources / Mining.setSprites)
local Resources = nil
local Sprites   = nil

-- Font cache
local fontCache = {}
local function getFont(size)
    if not fontCache[size] then
        fontCache[size] = love.graphics.newFont(size)
    end
    return fontCache[size]
end

-- =============================================================================
-- DDA ray cast (finds first solid wall tile the player is looking at)
-- =============================================================================

--- Cast a ray from (px,py) in direction (dirX,dirY) using DDA.
--- Returns tileX, tileY, distance of the first mineable wall hit within maxDist,
--- or nil if nothing mineable is in range.
local function castMiningRay(px, py, dirX, dirY, map, maxDist)
    local mapX = math_floor(px)
    local mapY = math_floor(py)

    -- Avoid division by zero: use a very large delta for zero components
    local deltaDistX = (dirX == 0) and 1e30 or math_abs(1 / dirX)
    local deltaDistY = (dirY == 0) and 1e30 or math_abs(1 / dirY)

    local stepX, stepY
    local sideDistX, sideDistY

    if dirX < 0 then
        stepX = -1
        sideDistX = (px - mapX) * deltaDistX
    else
        stepX = 1
        sideDistX = (mapX + 1 - px) * deltaDistX
    end

    if dirY < 0 then
        stepY = -1
        sideDistY = (py - mapY) * deltaDistY
    else
        stepY = 1
        sideDistY = (mapY + 1 - py) * deltaDistY
    end

    local side = 0
    for _ = 1, DDA_MAX_STEPS do
        -- Step to the next grid boundary
        if sideDistX < sideDistY then
            sideDistX = sideDistX + deltaDistX
            mapX = mapX + stepX
            side = 0
        else
            sideDistY = sideDistY + deltaDistY
            mapY = mapY + stepY
            side = 1
        end

        -- Compute perpendicular wall distance
        local perpDist
        if side == 0 then
            perpDist = sideDistX - deltaDistX
        else
            perpDist = sideDistY - deltaDistY
        end

        -- If beyond range, stop searching
        if perpDist > maxDist then
            return nil
        end

        -- Query the map
        local tile = map:getTile(mapX, mapY)

        -- Check if this tile is a mineable wall (not empty, door, or stairs)
        if tile and tile > 0 and not UNMINED_TILES[tile] then
            return mapX, mapY, perpDist
        end

        -- If we hit a door or stair, the ray is blocked; nothing mineable behind it
        if tile and (tile == 10 or tile == 11 or tile == 12) then
            return nil
        end
    end

    return nil
end

-- =============================================================================
-- Internal helpers
-- =============================================================================

--- Get the mining duration for a given wall type.
local function getMineTimeForTile(wallType)
    -- If a Resources module is available and provides duration, prefer it
    if Resources and Resources.getForWallType then
        local info = Resources.getForWallType(wallType)
        if info and info.mineTime then
            return info.mineTime
        end
    end
    return MINE_TIME[wallType] or MINE_TIME_DEFAULT
end

--- Determine what items to drop for a mined wall type.
--- Returns a list of { itemType=string, amount=number } entries.
local function rollDrops(wallType)
    local drops = {}

    -- Prefer the Resources module if available
    if Resources and Resources.getForWallType then
        local resourceId = Resources.getForWallType(wallType)
        if resourceId then
            local def = Resources.get and Resources.get(resourceId)
            if def then
                local lo = math.max(def.minYield or 1, 1)
                local hi = math.max(def.maxYield or lo, lo)
                local amount = math.random(lo, hi)
                if amount > 0 then
                    drops[#drops + 1] = { itemType = resourceId, amount = amount }
                end
                return drops
            end
        end
    end

    -- Fall back to built-in default drops
    local dropTable = DEFAULT_DROPS[wallType] or DEFAULT_DROPS_FALLBACK
    for _, entry in ipairs(dropTable) do
        local itemType = entry[1]
        local minQty   = entry[2]
        local maxQty   = entry[3]
        local amount   = math.random(minQty, maxQty)
        if amount > 0 then
            drops[#drops + 1] = { itemType = itemType, amount = amount }
        end
    end
    return drops
end

--- Spawn resource items at the world position of the mined tile.
local function spawnDrops(tileX, tileY, drops)
    if not Sprites then return end

    -- Place items at the center of the tile that was just cleared
    local cx = tileX + 0.5
    local cy = tileY + 0.5

    for _, drop in ipairs(drops) do
        for i = 1, drop.amount do
            -- Slight random offset so multiple items don't stack perfectly
            local ox = (math.random() - 0.5) * 0.4
            local oy = (math.random() - 0.5) * 0.4
            Sprites.addItem(cx + ox, cy + oy, drop.itemType)
        end
    end
end

--- Reset mining state (cancel in progress, clear target).
local function resetMiningState()
    active     = false
    progress   = 0
    targetX    = nil
    targetY    = nil
    targetType = 0
    miningTime = 0
end

-- =============================================================================
-- Public API
-- =============================================================================

--- Initialize or reset the mining system. Call on game load / theme change.
function Mining.init()
    resetMiningState()
    onMineComplete = nil
end

--- Inject the Sprites module reference so drops can be spawned.
--- @param spritesModule table  The Sprites module (from sprites.lua)
function Mining.setSprites(spritesModule)
    Sprites = spritesModule
end

--- Inject the Resources module reference for per-wall yield tables.
--- @param resourcesModule table  The Resources module (optional)
function Mining.setResources(resourcesModule)
    Resources = resourcesModule
end

--- Register a callback fired when mining completes.
--- Signature: callback(tileX, tileY, resourceId, amount)
--- (resourceId and amount reflect the first/primary drop; full drops are spawned automatically)
function Mining.setOnMineComplete(callback)
    onMineComplete = callback
end

--- Notify the system that the player pressed the mine button (LMB down).
function Mining.startMining()
    active = true
end

--- Notify the system that the player released the mine button (LMB up).
function Mining.stopMining()
    if active then
        resetMiningState()
    end
end

--- Returns true if the player is actively mining (button held + valid target).
function Mining.isActive()
    return active and targetX ~= nil
end

--- Returns mining progress as a float in [0, 1].
function Mining.getProgress()
    return progress
end

--- Returns the tile coordinates of the current mining target, or nil if none.
function Mining.getTargetTile()
    if targetX then
        return targetX, targetY
    end
    return nil
end

--- Main update. Call every frame while the player might be mining.
--- @param dt      number   Frame delta time.
--- @param playerX number   Player world X.
--- @param playerY number   Player world Y.
--- @param dirX    number   Player look direction X component.
--- @param dirY    number   Player look direction Y component.
--- @param map     table    The Map object (needs :getTile, :setTile).
function Mining.update(dt, playerX, playerY, dirX, dirY, map)
    if not map then return end

    -- If the mine button is not held, nothing to do
    if not active then
        return
    end

    -- Cast a ray to see what wall the player is looking at
    local hitX, hitY, hitDist = castMiningRay(playerX, playerY, dirX, dirY, map, MINING_RANGE)

    if not hitX then
        -- No valid target in range; cancel any in-progress mining
        if targetX then
            resetMiningState()
            active = true  -- Keep active flag since button is still held
        end
        return
    end

    -- Check if the target changed (player looked at a different tile)
    if hitX ~= targetX or hitY ~= targetY then
        -- New target: reset progress
        local tile = map:getTile(hitX, hitY)
        if tile and tile > 0 and not UNMINED_TILES[tile] then
            targetX    = hitX
            targetY    = hitY
            targetType = tile
            miningTime = getMineTimeForTile(tile)
            progress   = 0
        else
            -- Should not happen (castMiningRay already filtered), but defend
            resetMiningState()
            active = true
            return
        end
    end

    -- Verify the target tile is still a wall (could have been changed externally)
    local currentTile = map:getTile(targetX, targetY)
    if not currentTile or currentTile == 0 or UNMINED_TILES[currentTile] then
        resetMiningState()
        active = true
        return
    end

    -- Advance progress
    if miningTime > 0 then
        progress = progress + dt / miningTime
    end

    -- Check completion
    if progress >= 1.0 then
        progress = 1.0

        -- Convert wall to floor
        map:setTile(targetX, targetY, 0)

        -- Determine and spawn drops
        local drops = rollDrops(targetType)
        spawnDrops(targetX, targetY, drops)

        -- Fire callback
        if onMineComplete then
            -- Provide the first drop info for convenience; full drops were already spawned
            local primaryId     = (drops[1] and drops[1].itemType) or "gold"
            local primaryAmount = (drops[1] and drops[1].amount)   or 0
            onMineComplete(targetX, targetY, primaryId, primaryAmount)
        end

        -- Reset for next potential target (button may still be held)
        targetX    = nil
        targetY    = nil
        targetType = 0
        progress   = 0
        miningTime = 0
        -- active stays true so the player can immediately start mining the next tile
    end
end

--- Draw the mining progress bar on the HUD (screen space).
--- Call this from the main draw after all world rendering.
--- @param screenW number  Window width in pixels.
--- @param screenH number  Window height in pixels.
function Mining.drawHUD(screenW, screenH)
    if not Mining.isActive() then
        return
    end

    local cx = math_floor(screenW * 0.5)
    local cy = math_floor(screenH * 0.5) + BAR_Y_OFFSET

    local barX = cx - math_floor(BAR_WIDTH * 0.5)
    local barY = cy

    love.graphics.push("all")

    -- Background
    love.graphics.setColor(BAR_BG_COLOR[1], BAR_BG_COLOR[2], BAR_BG_COLOR[3], BAR_BG_COLOR[4])
    love.graphics.rectangle("fill", barX - 1, barY - 1, BAR_WIDTH + 2, BAR_HEIGHT + 2, 2, 2)

    -- Fill (progress)
    local fillW = math_floor(BAR_WIDTH * progress)
    if fillW > 0 then
        -- Slight pulsing glow effect as mining nears completion
        local pulse = 1.0
        if progress > 0.7 then
            local t = (progress - 0.7) / 0.3
            pulse = 1.0 + math_sin(love.timer.getTime() * 8) * 0.15 * t
        end
        local fr = math_min(1, BAR_FILL_COLOR[1] * pulse)
        local fg = math_min(1, BAR_FILL_COLOR[2] * pulse)
        local fb = math_min(1, BAR_FILL_COLOR[3] * pulse)
        love.graphics.setColor(fr, fg, fb)
        love.graphics.rectangle("fill", barX, barY, fillW, BAR_HEIGHT, 2, 2)
    end

    -- Border
    love.graphics.setColor(BAR_BORDER_COLOR[1], BAR_BORDER_COLOR[2], BAR_BORDER_COLOR[3], BAR_BORDER_COLOR[4])
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", barX - 1, barY - 1, BAR_WIDTH + 2, BAR_HEIGHT + 2, 2, 2)

    -- Small "Mining..." label above bar
    local font = getFont(10)
    love.graphics.setFont(font)
    love.graphics.setColor(0.7, 0.85, 0.95, 0.9)
    local label = "Mining..."
    local labelW = font:getWidth(label)
    love.graphics.print(label, cx - math_floor(labelW * 0.5), barY - 14)

    love.graphics.pop()
end

-- =============================================================================
-- Save / Load support
-- =============================================================================

--- Returns save data for serialization (mining is transient, so mostly a no-op).
function Mining.getSaveData()
    return {}
end

--- Restore from save data. Mining progress is not persisted.
function Mining.loadSaveData(data)
    resetMiningState()
end

return Mining
