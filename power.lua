--[[
    Power Grid System
    Manages power generation and consumption for an underwater city builder
    raycaster. Buildings that generate power (generators) produce watts;
    buildings that consume power (O2 generators, turrets, etc.) require watts.
    Power flows via adjacency: a BFS flood-fill from each generator marks
    buildings within range as connected. Brownout logic sheds load from the
    buildings furthest from any generator when demand exceeds supply.

    Integration:
        Power.init()
        Power.update(dt, placedBuildings, map)
        Power.drawHUD(screenW, screenH)
        Power.getSaveData() / Power.loadSaveData(data)
]]

local Power = {}

-- Cached math functions for hot paths
local math_floor = math.floor
local math_min   = math.min
local math_max   = math.max
local math_abs   = math.abs

-- =============================================================================
-- Constants
-- =============================================================================

local BFS_RANGE              = 5       -- Max tile distance from a generator
local RECALC_INTERVAL        = 0.25    -- Seconds between full network recalcs
local HUD_BAR_WIDTH          = 160
local HUD_BAR_HEIGHT         = 14
local HUD_PADDING            = 8

-- Default power values per building type (watts).
-- Positive = generation, negative = consumption.
-- These are used when a buildingDef does not carry its own .power field.
local DEFAULT_POWER = {
    generator       =  50,
    o2_generator    = -10,
    med_bay         = -15,
    food_processor  =  -5,
    research_lab    = -20,
    turret          = -10,
    water_pump      =  -5,
    beacon          =  -5,
}

-- BFS neighbour offsets (4-connected)
local ADJ_OFFSETS = {
    { -1,  0 },
    {  1,  0 },
    {  0, -1 },
    {  0,  1 },
}

-- =============================================================================
-- Font cache
-- =============================================================================

local fontCache = {}
local function getFont(size)
    if not fontCache[size] then
        fontCache[size] = love.graphics.newFont(size)
    end
    return fontCache[size]
end

-- =============================================================================
-- Module-local state
-- =============================================================================

-- Registered buildings: key = "x,y", value = { x, y, type, power, powered, dist }
local buildings     = {}
local generators    = {}      -- Subset references into `buildings` with power > 0
local consumers     = {}      -- Subset references into `buildings` with power < 0

-- Network results (rebuilt every recalc tick)
local connectedSet  = {}      -- { ["x,y"] = true } tiles reachable from generators
local poweredSet    = {}      -- { ["x,y"] = true } buildings that actually have power
local allPoweredList = {}     -- Array of {x=, y=} for Power.getAllPowered()

-- Aggregate values
local totalProduction  = 0
local totalConsumption = 0    -- Stored as a positive number (watts demanded)
local netPower         = 0
local networkStatus    = "offline"  -- "online" | "brownout" | "offline"

-- Timing
local recalcTimer = 0

-- Dirty flag: set when buildings are added/removed so next update recalcs
local dirty = true

-- =============================================================================
-- Helpers
-- =============================================================================

local function tileKey(x, y)
    return x .. "," .. y
end

local function parseTileKey(key)
    local sx, sy = key:match("^(-?%d+),(-?%d+)$")
    return tonumber(sx), tonumber(sy)
end

--- Resolve the wattage for a building definition.
--- Prefers def.power if present, otherwise looks up DEFAULT_POWER by def.type.
local function resolvePower(buildingDef)
    if buildingDef.power then
        return buildingDef.power
    end
    local btype = buildingDef.type or buildingDef.id or ""
    return DEFAULT_POWER[btype] or 0
end

--- Returns true if a map tile is passable for the BFS power cable.
--- Power flows through floor tiles (0), stairs (11, 12), doors (10),
--- and any tile that has a building placed on it.
local function isConductiveTile(map, tx, ty)
    if not map then
        return true  -- No map provided; assume reachable
    end
    local tile = map:getTile(tx, ty)
    -- 0 = empty floor, 10 = door, 11 = stair up, 12 = stair down
    if tile == 0 or tile == 10 or tile == 11 or tile == 12 then
        return true
    end
    -- A building occupying a wall tile still conducts power
    if buildings[tileKey(tx, ty)] then
        return true
    end
    return false
end

-- =============================================================================
-- BFS flood-fill from generators
-- =============================================================================

--- Run BFS from every generator up to BFS_RANGE tiles.
--- Populates `connectedSet` and stamps each reached building with its distance
--- from the nearest generator.
local function bfsFloodFill(map)
    connectedSet = {}

    -- BFS queue: array of {x, y, dist}
    -- Pre-seed with all generator tiles at distance 0
    local queue = {}
    local head  = 1

    for _, gen in ipairs(generators) do
        local key = tileKey(gen.x, gen.y)
        if not connectedSet[key] then
            connectedSet[key] = 0  -- distance
            queue[#queue + 1] = { x = gen.x, y = gen.y, dist = 0 }
        end
    end

    -- Standard BFS
    while head <= #queue do
        local cur  = queue[head]
        head = head + 1

        if cur.dist < BFS_RANGE then
            local nextDist = cur.dist + 1
            for i = 1, 4 do
                local off = ADJ_OFFSETS[i]
                local nx, ny = cur.x + off[1], cur.y + off[2]
                local nkey = tileKey(nx, ny)

                if connectedSet[nkey] == nil and isConductiveTile(map, nx, ny) then
                    connectedSet[nkey] = nextDist
                    queue[#queue + 1] = { x = nx, y = ny, dist = nextDist }
                end
            end
        end
    end

    -- Stamp buildings with their distance from nearest generator
    for key, bld in pairs(buildings) do
        local dist = connectedSet[key]
        if dist then
            bld.dist = dist
        else
            bld.dist = -1  -- Not connected
        end
    end
end

-- =============================================================================
-- Power distribution / brownout
-- =============================================================================

--- After BFS, decide which consumers actually receive power.
--- If total production >= total consumption, every connected consumer is powered.
--- Otherwise, shed load starting from the consumers furthest from any generator.
local function distributePower()
    poweredSet     = {}
    allPoweredList = {}

    -- Generators are always "powered" (they produce their own juice)
    for _, gen in ipairs(generators) do
        local key = tileKey(gen.x, gen.y)
        gen.powered = true
        poweredSet[key] = true
        allPoweredList[#allPoweredList + 1] = { x = gen.x, y = gen.y }
    end

    -- Collect connected consumers and compute totals
    totalProduction  = 0
    totalConsumption = 0

    for _, gen in ipairs(generators) do
        totalProduction = totalProduction + gen.power
    end

    -- Gather connected consumers sorted by distance (ascending)
    local connectedConsumers = {}
    for _, con in ipairs(consumers) do
        if con.dist >= 0 then  -- Reachable from a generator
            connectedConsumers[#connectedConsumers + 1] = con
            totalConsumption = totalConsumption + math_abs(con.power)
        else
            con.powered = false
        end
    end

    -- Sort ascending by distance so closest consumers are powered first
    table.sort(connectedConsumers, function(a, b)
        return a.dist < b.dist
    end)

    -- Determine status before shedding
    if totalProduction <= 0 and totalConsumption > 0 then
        networkStatus = "offline"
    elseif totalConsumption > totalProduction then
        networkStatus = "brownout"
    else
        networkStatus = "online"
    end

    -- If no generators exist at all, nothing gets power
    if #generators == 0 then
        networkStatus = "offline"
        for _, con in ipairs(consumers) do
            con.powered = false
        end
        return
    end

    -- Distribute available watts, closest first
    local availableWatts = totalProduction
    for _, con in ipairs(connectedConsumers) do
        local needed = math_abs(con.power)
        if availableWatts >= needed then
            availableWatts = availableWatts - needed
            con.powered = true
            local key = tileKey(con.x, con.y)
            poweredSet[key] = true
            allPoweredList[#allPoweredList + 1] = { x = con.x, y = con.y }
        else
            -- Not enough juice; this and everything further away is unpowered
            con.powered = false
        end
    end
end

-- =============================================================================
-- Full network recalculation
-- =============================================================================

local function recalcNetwork(map)
    bfsFloodFill(map)
    distributePower()
    dirty = false
end

-- =============================================================================
-- Rebuild generator/consumer index tables from the buildings map.
-- Called when buildings change (add/remove).
-- =============================================================================

local function rebuildIndices()
    generators = {}
    consumers  = {}

    for _, bld in pairs(buildings) do
        if bld.power > 0 then
            generators[#generators + 1] = bld
        elseif bld.power < 0 then
            consumers[#consumers + 1] = bld
        end
    end
end

-- =============================================================================
-- Public API -- lifecycle
-- =============================================================================

function Power.init()
    buildings       = {}
    generators      = {}
    consumers       = {}
    connectedSet    = {}
    poweredSet      = {}
    allPoweredList  = {}
    totalProduction  = 0
    totalConsumption = 0
    netPower         = 0
    networkStatus    = "offline"
    recalcTimer      = 0
    dirty            = true
end

--- Main update tick.
--- @param dt             number   Delta time in seconds.
--- @param placedBuildings table|nil  Optional external building list to sync from.
---                                    Each entry: { tileX, tileY, def = { type, power, ... } }
--- @param map            table|nil  Map object with :getTile(x,y) for BFS passability.
function Power.update(dt, placedBuildings, map)
    -- If an external building list is provided, sync it into our registry
    if placedBuildings then
        Power.syncBuildings(placedBuildings)
    end

    recalcTimer = recalcTimer + dt

    if dirty or recalcTimer >= RECALC_INTERVAL then
        recalcTimer = 0
        recalcNetwork(map)
    end

    netPower = totalProduction - totalConsumption
end

-- =============================================================================
-- Building management
-- =============================================================================

--- Register a building at (tileX, tileY) with the given definition.
--- @param tileX  number  Integer tile X
--- @param tileY  number  Integer tile Y
--- @param buildingDef table  Must have .type or .id and optionally .power
function Power.addBuilding(tileX, tileY, buildingDef)
    if not buildingDef then return end

    tileX = math_floor(tileX)
    tileY = math_floor(tileY)
    local key = tileKey(tileX, tileY)

    local watts = resolvePower(buildingDef)

    buildings[key] = {
        x       = tileX,
        y       = tileY,
        type    = buildingDef.type or buildingDef.id or "unknown",
        power   = watts,
        powered = false,
        dist    = -1,
    }

    rebuildIndices()
    dirty = true
end

--- Remove a building at (tileX, tileY).
--- @param tileX number  Integer tile X
--- @param tileY number  Integer tile Y
function Power.removeBuilding(tileX, tileY)
    tileX = math_floor(tileX)
    tileY = math_floor(tileY)
    local key = tileKey(tileX, tileY)

    if buildings[key] then
        buildings[key] = nil
        rebuildIndices()
        dirty = true
    end
end

--- Bulk-sync from an external placed buildings list.
--- Entries without a power value default based on their type.
--- @param placedBuildings table  Array of { tileX, tileY, def = { type, power, ... } }
function Power.syncBuildings(placedBuildings)
    if not placedBuildings then return end

    -- Build a set of keys from the external list for removal detection
    local externalKeys = {}
    for _, entry in ipairs(placedBuildings) do
        if entry.tileX and entry.tileY and entry.def then
            local key = tileKey(math_floor(entry.tileX), math_floor(entry.tileY))
            externalKeys[key] = entry
        end
    end

    -- Remove buildings no longer present externally
    local toRemove = {}
    for key, _ in pairs(buildings) do
        if not externalKeys[key] then
            toRemove[#toRemove + 1] = key
        end
    end
    for _, key in ipairs(toRemove) do
        buildings[key] = nil
        dirty = true
    end

    -- Add or update buildings from external list
    for key, entry in pairs(externalKeys) do
        local tx = math_floor(entry.tileX)
        local ty = math_floor(entry.tileY)
        local watts = resolvePower(entry.def)

        local existing = buildings[key]
        if not existing or existing.power ~= watts or existing.type ~= (entry.def.type or entry.def.id or "unknown") then
            buildings[key] = {
                x       = tx,
                y       = ty,
                type    = entry.def.type or entry.def.id or "unknown",
                power   = watts,
                powered = false,
                dist    = -1,
            }
            dirty = true
        end
    end

    if dirty then
        rebuildIndices()
    end
end

-- =============================================================================
-- Query API
-- =============================================================================

--- Check if a building at (tileX, tileY) is currently powered.
--- @param tileX number
--- @param tileY number
--- @return boolean
function Power.isPowered(tileX, tileY)
    local key = tileKey(math_floor(tileX), math_floor(tileY))
    return poweredSet[key] == true
end

--- Total watts generated across all generators.
--- @return number
function Power.getTotalProduction()
    return totalProduction
end

--- Total watts demanded across all connected consumers (positive value).
--- @return number
function Power.getTotalConsumption()
    return totalConsumption
end

--- Net power: production minus consumption. Positive = surplus.
--- @return number
function Power.getNetPower()
    return netPower
end

--- Current grid status.
--- @return string  "online" | "brownout" | "offline"
function Power.getPowerStatus()
    return networkStatus
end

--- All tiles that currently have power.
--- @return table  Array of {x=number, y=number}
function Power.getAllPowered()
    return allPoweredList
end

--- Get the building data for a specific tile (or nil).
--- @param tileX number
--- @param tileY number
--- @return table|nil  { x, y, type, power, powered, dist }
function Power.getBuildingAt(tileX, tileY)
    return buildings[tileKey(math_floor(tileX), math_floor(tileY))]
end

--- Is the tile within the BFS-connected network (reachable from a generator)?
--- @param tileX number
--- @param tileY number
--- @return boolean
function Power.isConnected(tileX, tileY)
    local key = tileKey(math_floor(tileX), math_floor(tileY))
    return connectedSet[key] ~= nil
end

--- Get the BFS distance from the nearest generator for a given tile.
--- Returns -1 if not reachable.
--- @param tileX number
--- @param tileY number
--- @return number
function Power.getDistanceToGenerator(tileX, tileY)
    local key = tileKey(math_floor(tileX), math_floor(tileY))
    return connectedSet[key] or -1
end

-- =============================================================================
-- HUD rendering
-- =============================================================================

--- Draw the power status indicator.
--- Call during the draw phase after switching to screen-space.
--- @param screenW number  Current window width
--- @param screenH number  Current window height
function Power.drawHUD(screenW, screenH)
    -- Position: upper-left area below where FPS / atmosphere panels sit
    local x = screenW - HUD_BAR_WIDTH - HUD_PADDING - 10
    local y = 10

    love.graphics.push()

    -- Background panel
    local panelW = HUD_BAR_WIDTH + HUD_PADDING * 2
    local panelH = 52
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", x - HUD_PADDING, y - HUD_PADDING, panelW, panelH, 5, 5)

    -- Status color
    local statusColor
    if networkStatus == "online" then
        statusColor = {0.3, 0.9, 0.4}
    elseif networkStatus == "brownout" then
        statusColor = {1.0, 0.75, 0.2}
    else
        statusColor = {0.9, 0.3, 0.2}
    end

    -- Header line: "PWR: 50W / 100W"
    local consumed = math_floor(totalConsumption)
    local produced = math_floor(totalProduction)
    local headerText = "PWR: " .. consumed .. "W / " .. produced .. "W"

    love.graphics.setColor(statusColor[1], statusColor[2], statusColor[3])
    love.graphics.print(headerText, x, y)

    -- Power bar
    local barY = y + 18
    -- Background track
    love.graphics.setColor(0.15, 0.15, 0.2)
    love.graphics.rectangle("fill", x, barY, HUD_BAR_WIDTH, HUD_BAR_HEIGHT, 3, 3)

    -- Fill based on consumption / production ratio
    if produced > 0 then
        local ratio = math_min(1.0, consumed / produced)
        local fillW = ratio * HUD_BAR_WIDTH

        -- Fill color shifts from green (low usage) to yellow to red
        local fillR, fillG, fillB
        if ratio < 0.5 then
            -- Green to yellow
            local t = ratio / 0.5
            fillR = t
            fillG = 0.85
            fillB = 0.2 * (1 - t)
        elseif ratio < 0.85 then
            -- Yellow to orange
            local t = (ratio - 0.5) / 0.35
            fillR = 0.9 + 0.1 * t
            fillG = 0.85 - 0.45 * t
            fillB = 0.0
        else
            -- Orange to red
            local t = (ratio - 0.85) / 0.15
            fillR = 1.0
            fillG = 0.4 - 0.3 * t
            fillB = 0.05
        end

        love.graphics.setColor(fillR, fillG, fillB, 0.9)
        love.graphics.rectangle("fill", x, barY, fillW, HUD_BAR_HEIGHT, 3, 3)
    end

    -- Bar outline
    love.graphics.setColor(0.4, 0.4, 0.5, 0.8)
    love.graphics.rectangle("line", x, barY, HUD_BAR_WIDTH, HUD_BAR_HEIGHT, 3, 3)

    -- Status label
    local statusLabel = networkStatus:upper()
    love.graphics.setColor(statusColor[1], statusColor[2], statusColor[3], 0.9)
    love.graphics.print(statusLabel, x + HUD_BAR_WIDTH - 50, barY + 1)

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

-- =============================================================================
-- Save / Load
-- =============================================================================

function Power.getSaveData()
    local buildingList = {}
    for key, bld in pairs(buildings) do
        buildingList[#buildingList + 1] = {
            x     = bld.x,
            y     = bld.y,
            type  = bld.type,
            power = bld.power,
        }
    end

    return {
        buildings = buildingList,
    }
end

function Power.loadSaveData(data)
    if not data then return end

    Power.init()

    if data.buildings then
        for _, entry in ipairs(data.buildings) do
            if entry.x and entry.y then
                local key = tileKey(math_floor(entry.x), math_floor(entry.y))
                buildings[key] = {
                    x       = math_floor(entry.x),
                    y       = math_floor(entry.y),
                    type    = entry.type or "unknown",
                    power   = entry.power or 0,
                    powered = false,
                    dist    = -1,
                }
            end
        end

        rebuildIndices()
        dirty = true
    end
end

return Power
