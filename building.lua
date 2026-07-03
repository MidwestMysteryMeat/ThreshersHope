--[[
    Building Placement System
    Manages first-person building placement for an underwater city builder raycaster.
    Uses DDA ray cast to target floor tiles, renders ghost preview, and tracks
    all placed buildings with resource cost deduction and partial refund on removal.

    Building tiles occupy the range 20-31 on the map grid.
    Buildings can only be placed on empty floor tiles (tile 0).
    Placement range is 3.0 tiles in front of the player.

    Designed to integrate with main.lua's game loop:
        Building.init()
        Building.update(dt)
        Building.drawHUD(screenW, screenH, px, py, dirX, dirY, map)
        -- Raycaster queries Building.getGhostTile() for preview rendering
]]

local Building = {}

-- Cached math functions for hot paths
local math_floor = math.floor
local math_abs   = math.abs
local math_min   = math.min
local math_max   = math.max
local math_sin   = math.sin
local math_cos   = math.cos

-- =============================================================================
-- Constants
-- =============================================================================

local PLACEMENT_RANGE   = 3.0   -- Max tile distance for placing buildings
local DDA_MAX_STEPS     = 8     -- Max DDA steps (generous for 3-tile range)
local REFUND_FRACTION   = 0.5   -- Fraction of resources returned on removal
local PULSE_SPEED       = 4.0   -- Ghost preview pulse animation speed
local HUD_PADDING       = 10
local HUD_SLOT_W        = 180
local HUD_SLOT_H        = 48
local HUD_SELECTED_W    = 260
local HUD_SELECTED_H    = 110
local BUILDING_TILE_MIN = 20
local BUILDING_TILE_MAX = 31

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
-- Building type definitions
-- =============================================================================

-- Ordered list for cycling; lookup table built at init.
-- Each entry: id, name, tile, cost, power, crew, description, color
local TYPES_LIST = {
    {
        id          = "habitat_module",
        name        = "Habitat Module",
        tile        = 20,
        cost        = { titanium = 5, scrap_metal = 3 },
        power       = 0,
        crew        = 2,
        description = "Living quarters. +2 crew capacity.",
        color       = { 0.3, 0.7, 0.9 },
    },
    {
        id          = "o2_generator",
        name        = "O2 Generator",
        tile        = 21,
        cost        = { electronics = 3, crystal = 2 },
        power       = -10,
        crew        = 0,
        description = "Produces oxygen for the habitat. -10W",
        color       = { 0.4, 0.9, 0.6 },
    },
    {
        id          = "generator",
        name        = "Generator",
        tile        = 22,
        cost        = { scrap_metal = 4, electronics = 2 },
        power       = 50,
        crew        = 0,
        description = "Produces electrical power. +50W",
        color       = { 1.0, 0.85, 0.2 },
    },
    {
        id          = "storage",
        name        = "Storage Unit",
        tile        = 23,
        cost        = { scrap_metal = 4, titanium = 1 },
        power       = 0,
        crew        = 0,
        description = "Extra inventory storage space.",
        color       = { 0.6, 0.55, 0.45 },
    },
    {
        id          = "med_bay",
        name        = "Med Bay",
        tile        = 24,
        cost        = { electronics = 3, biomass = 3 },
        power       = -15,
        crew        = 0,
        description = "Heals injured crew members. -15W",
        color       = { 0.9, 0.3, 0.3 },
    },
    {
        id          = "food_processor",
        name        = "Food Processor",
        tile        = 25,
        cost        = { electronics = 2, biomass = 3 },
        power       = -5,
        crew        = 0,
        description = "Converts biomass into food. -5W",
        color       = { 0.5, 0.8, 0.3 },
    },
    {
        id          = "research_lab",
        name        = "Research Lab",
        tile        = 26,
        cost        = { electronics = 5, crystal = 3 },
        power       = -20,
        crew        = 0,
        description = "Unlocks new technology. -20W",
        color       = { 0.6, 0.4, 0.9 },
    },
    {
        id          = "turret",
        name        = "Turret",
        tile        = 27,
        cost        = { titanium = 4, electronics = 3 },
        power       = -10,
        crew        = 0,
        description = "Auto-attacks nearby enemies. -10W",
        color       = { 0.9, 0.5, 0.2 },
    },
    {
        id          = "water_pump",
        name        = "Water Pump",
        tile        = 28,
        cost        = { scrap_metal = 3, electronics = 2 },
        power       = -5,
        crew        = 0,
        description = "Removes flooding from area. -5W",
        color       = { 0.2, 0.5, 0.8 },
    },
    {
        id          = "beacon",
        name        = "Beacon",
        tile        = 29,
        cost        = { crystal = 2, electronics = 1 },
        power       = -5,
        crew        = 0,
        description = "Reveals surrounding map area. -5W",
        color       = { 0.9, 0.9, 0.5 },
    },
    {
        id          = "airlock",
        name        = "Airlock",
        tile        = 30,
        cost        = { titanium = 5, scrap_metal = 2 },
        power       = 0,
        crew        = 0,
        description = "Connects habitat to the ocean.",
        color       = { 0.5, 0.6, 0.7 },
    },
    {
        id          = "conveyor",
        name        = "Conveyor",
        tile        = 31,
        cost        = { scrap_metal = 2 },
        power       = 0,
        crew        = 0,
        description = "Moves items between buildings.",
        color       = { 0.65, 0.65, 0.65 },
    },
}

-- =============================================================================
-- Module-local state
-- =============================================================================

local typeById    = {}      -- id string -> type def (built at init)
local typeByTile  = {}      -- tile value -> type def (built at init)
local buildMode   = false   -- Is the player in build mode?
local selectedIdx = 1       -- Index into TYPES_LIST for the currently selected type
local ghostTileX  = nil     -- Tile coordinates of the ghost preview (or nil)
local ghostTileY  = nil
local ghostValid  = false   -- Can the player place at the ghost tile?
local ghostReason = nil     -- Reason placement is blocked (string or nil)
local pulsePhase  = 0       -- Animation phase for ghost pulse

-- Placed buildings tracking: key = "x,y,floor" -> { def=typeDef, x=int, y=int, floor=int }
local placedBuildings = {}

-- Callbacks (event system, mirrors other modules)
local callbacks = {}

-- =============================================================================
-- Callbacks
-- =============================================================================

function Building.registerCallback(event, fn)
    if not callbacks[event] then callbacks[event] = {} end
    callbacks[event][#callbacks[event] + 1] = fn
end

local function fireCallback(event, ...)
    if callbacks[event] then
        for _, fn in ipairs(callbacks[event]) do
            fn(...)
        end
    end
end

-- =============================================================================
-- Helpers
-- =============================================================================

local function buildingKey(x, y, floor)
    return x .. "," .. y .. "," .. (floor or 1)
end

--- Check if a tile value represents a building (20-31).
local function isBuildingTile(tileValue)
    return tileValue >= BUILDING_TILE_MIN and tileValue <= BUILDING_TILE_MAX
end

-- =============================================================================
-- Initialization
-- =============================================================================

function Building.init()
    -- Build fast lookup tables from the ordered list
    typeById   = {}
    typeByTile = {}
    for i, def in ipairs(TYPES_LIST) do
        typeById[def.id]     = def
        typeByTile[def.tile] = def
    end

    buildMode       = false
    selectedIdx     = 1
    ghostTileX      = nil
    ghostTileY      = nil
    ghostValid      = false
    ghostReason     = nil
    pulsePhase      = 0
    placedBuildings = {}
    callbacks       = {}
end

-- =============================================================================
-- Public: type table (read-only reference)
-- =============================================================================

--- Expose building type definitions for external systems.
Building.TYPES = TYPES_LIST

-- =============================================================================
-- Build mode control
-- =============================================================================

function Building.enterBuildMode()
    buildMode = true
    fireCallback("onEnterBuildMode")
end

function Building.exitBuildMode()
    buildMode   = false
    ghostTileX  = nil
    ghostTileY  = nil
    ghostValid  = false
    ghostReason = nil
    fireCallback("onExitBuildMode")
end

function Building.isInBuildMode()
    return buildMode
end

-- =============================================================================
-- Type selection
-- =============================================================================

--- Select a building type by its string id.
--- Returns true if the id was found and selected.
function Building.selectType(buildingId)
    for i, def in ipairs(TYPES_LIST) do
        if def.id == buildingId then
            selectedIdx = i
            fireCallback("onTypeSelected", def)
            return true
        end
    end
    return false
end

--- Get the currently selected building definition, or nil if none.
function Building.getSelectedType()
    if not buildMode then return nil end
    return TYPES_LIST[selectedIdx]
end

--- Select a building type by its index (1-based) in the TYPES_LIST.
--- Returns true if the index was valid and selected.
function Building.selectByIndex(index)
    if not buildMode then return false end
    if index >= 1 and index <= #TYPES_LIST then
        selectedIdx = index
        fireCallback("onTypeSelected", TYPES_LIST[selectedIdx])
        return true
    end
    return false
end

--- Get the total count of building types.
function Building.getTypeCount()
    return #TYPES_LIST
end

--- Cycle through building types. direction: +1 forward, -1 backward.
function Building.cycleType(direction)
    if not buildMode then return end
    selectedIdx = selectedIdx + direction
    if selectedIdx < 1 then
        selectedIdx = #TYPES_LIST
    elseif selectedIdx > #TYPES_LIST then
        selectedIdx = 1
    end
    fireCallback("onTypeSelected", TYPES_LIST[selectedIdx])
end

-- =============================================================================
-- DDA targeting (find the floor tile the player is looking at)
-- =============================================================================

--- Cast a ray from (px, py) in direction (dirX, dirY) using DDA.
--- Returns tileX, tileY of the first empty floor tile (tile == 0) within
--- PLACEMENT_RANGE, or nil if none found.
--- Also accepts building tiles so the player can target existing buildings
--- for removal; set acceptBuildings to true to include those.
function Building.getTargetTile(px, py, dirX, dirY, map, acceptBuildings)
    if not map then return nil, nil end

    local mapX = math_floor(px)
    local mapY = math_floor(py)

    -- DDA setup
    local deltaDistX = (dirX == 0) and 1e30 or math_abs(1 / dirX)
    local deltaDistY = (dirY == 0) and 1e30 or math_abs(1 / dirY)

    local stepX, stepY
    local sideDistX, sideDistY

    if dirX < 0 then
        stepX    = -1
        sideDistX = (px - mapX) * deltaDistX
    else
        stepX    = 1
        sideDistX = (mapX + 1 - px) * deltaDistX
    end

    if dirY < 0 then
        stepY    = -1
        sideDistY = (py - mapY) * deltaDistY
    else
        stepY    = 1
        sideDistY = (mapY + 1 - py) * deltaDistY
    end

    -- Step through tiles
    for _ = 1, DDA_MAX_STEPS do
        local side
        if sideDistX < sideDistY then
            sideDistX = sideDistX + deltaDistX
            mapX = mapX + stepX
            side = 0
        else
            sideDistY = sideDistY + deltaDistY
            mapY = mapY + stepY
            side = 1
        end

        -- Calculate perpendicular wall distance for range check
        local perpDist
        if side == 0 then
            perpDist = sideDistX - deltaDistX
        else
            perpDist = sideDistY - deltaDistY
        end

        -- Beyond placement range
        if perpDist > PLACEMENT_RANGE then
            return nil, nil
        end

        local tile = map:getTile(mapX, mapY)

        -- Empty floor tile: valid target for placement
        if tile == 0 then
            return mapX, mapY
        end

        -- Existing building tile: valid target for removal (if requested)
        if acceptBuildings and isBuildingTile(tile) then
            return mapX, mapY
        end

        -- Hit a wall / door / stair: stop the ray
        if tile > 0 and not isBuildingTile(tile) then
            return nil, nil
        end
    end

    return nil, nil
end

-- =============================================================================
-- Placement validation
-- =============================================================================

--- Check whether the selected building can be placed at (tileX, tileY).
--- @param tileX number  Integer tile X
--- @param tileY number  Integer tile Y
--- @param map   table   Map object
--- @param inventory table  Resource inventory { titanium=N, scrap_metal=N, ... }
--- @return boolean, string  success, reason (reason is nil on success)
function Building.canPlace(tileX, tileY, map, inventory)
    if not map then
        return false, "No map"
    end

    local def = TYPES_LIST[selectedIdx]
    if not def then
        return false, "No building selected"
    end

    -- Tile must be empty floor (tile 0)
    local tile = map:getTile(tileX, tileY)
    if tile ~= 0 then
        if isBuildingTile(tile) then
            return false, "Occupied by " .. (typeByTile[tile] and typeByTile[tile].name or "building")
        end
        return false, "Not a floor tile"
    end

    -- Check resource costs against inventory
    if inventory then
        for resource, amount in pairs(def.cost) do
            local have = inventory[resource] or 0
            if have < amount then
                return false, "Need " .. amount .. " " .. resource .. " (have " .. have .. ")"
            end
        end
    else
        return false, "No inventory"
    end

    return true, nil
end

-- =============================================================================
-- Place / Remove
-- =============================================================================

--- Place the currently selected building at (tileX, tileY).
--- Deducts resources from inventory and sets the map tile.
--- @return boolean  true on success
function Building.place(tileX, tileY, map, inventory)
    local ok, reason = Building.canPlace(tileX, tileY, map, inventory)
    if not ok then
        return false
    end

    local def = TYPES_LIST[selectedIdx]

    -- Deduct resources
    for resource, amount in pairs(def.cost) do
        inventory[resource] = (inventory[resource] or 0) - amount
    end

    -- Set tile on map
    map:setTile(tileX, tileY, def.tile)

    -- Track placement
    local floor = map.currentFloor or 1
    local key = buildingKey(tileX, tileY, floor)
    placedBuildings[key] = {
        def   = def,
        x     = tileX,
        y     = tileY,
        floor = floor,
    }

    fireCallback("onBuildingPlaced", def, tileX, tileY, floor)
    return true
end

--- Remove a building at (tileX, tileY). Returns partial resources to inventory.
--- @return boolean  true if a building was removed
function Building.remove(tileX, tileY, map, inventory)
    if not map then return false end

    local tile = map:getTile(tileX, tileY)
    if not isBuildingTile(tile) then
        return false
    end

    local def = typeByTile[tile]
    if not def then
        -- Unknown building tile; just clear it
        map:setTile(tileX, tileY, 0)
        return true
    end

    -- Refund partial resources
    if inventory then
        for resource, amount in pairs(def.cost) do
            local refund = math_max(1, math_floor(amount * REFUND_FRACTION))
            inventory[resource] = (inventory[resource] or 0) + refund
        end
    end

    -- Clear tile
    map:setTile(tileX, tileY, 0)

    -- Remove from tracking
    local floor = map.currentFloor or 1
    local key = buildingKey(tileX, tileY, floor)
    placedBuildings[key] = nil

    fireCallback("onBuildingRemoved", def, tileX, tileY, floor)
    return true
end

-- =============================================================================
-- Queries
-- =============================================================================

--- Get the building definition for whatever is at (tileX, tileY), or nil.
function Building.getBuildingAt(tileX, tileY, map)
    if not map then return nil end
    local tile = map:getTile(tileX, tileY)
    if isBuildingTile(tile) then
        return typeByTile[tile]
    end
    return nil
end

--- Return the full placed-buildings tracking table.
--- Keys are "x,y,floor", values are { def, x, y, floor }.
function Building.getAllPlaced()
    return placedBuildings
end

--- Count placed buildings on the current floor, optionally filtered by id.
function Building.countOnFloor(map, buildingId)
    local floor = (map and map.currentFloor) or 1
    local count = 0
    for _, entry in pairs(placedBuildings) do
        if entry.floor == floor then
            if buildingId == nil or entry.def.id == buildingId then
                count = count + 1
            end
        end
    end
    return count
end

--- Total power balance across all placed buildings (positive = surplus).
function Building.getPowerBalance()
    local total = 0
    for _, entry in pairs(placedBuildings) do
        total = total + (entry.def.power or 0)
    end
    return total
end

--- Total crew capacity across all placed habitat modules.
function Building.getCrewCapacity()
    local total = 0
    for _, entry in pairs(placedBuildings) do
        total = total + (entry.def.crew or 0)
    end
    return total
end

-- =============================================================================
-- Ghost preview (for raycaster integration)
-- =============================================================================

--- Returns the ghost tile coordinates (tileX, tileY) or nil, nil.
--- The raycaster should highlight this tile on the floor when in build mode.
function Building.getGhostTile()
    if not buildMode then return nil, nil end
    return ghostTileX, ghostTileY
end

--- Returns whether the ghost position is a valid placement.
function Building.isGhostValid()
    return ghostValid
end

--- Returns the color for the ghost preview (from selected building type).
function Building.getGhostColor()
    local def = TYPES_LIST[selectedIdx]
    if not def then return 0.5, 0.5, 0.5 end
    return def.color[1], def.color[2], def.color[3]
end

-- =============================================================================
-- Update
-- =============================================================================

--- Call once per frame. Updates ghost preview targeting and pulse animation.
--- @param dt number  Delta time
--- @param px number  Player world X
--- @param py number  Player world Y
--- @param dirX number  Player direction X
--- @param dirY number  Player direction Y
--- @param map table  Map object
--- @param inventory table  Resource inventory
function Building.update(dt, px, py, dirX, dirY, map, inventory)
    -- Pulse animation runs regardless of build mode
    pulsePhase = pulsePhase + dt * PULSE_SPEED

    if not buildMode then
        ghostTileX = nil
        ghostTileY = nil
        ghostValid = false
        ghostReason = nil
        return
    end

    -- DDA ray cast to find targeted floor tile
    local tx, ty = Building.getTargetTile(px, py, dirX, dirY, map)
    ghostTileX = tx
    ghostTileY = ty

    if tx and ty then
        ghostValid, ghostReason = Building.canPlace(tx, ty, map, inventory)
    else
        ghostValid  = false
        ghostReason = "No floor tile in range"
    end
end

-- =============================================================================
-- HUD Drawing
-- =============================================================================

--- Draw the build-mode HUD overlay.
--- Should be called during the draw phase, after the 3D view is composited
--- to screen space.
function Building.drawHUD(screenW, screenH, px, py, dirX, dirY, map, inventory)
    if not buildMode then return end

    love.graphics.push("all")

    local def = TYPES_LIST[selectedIdx]
    local lg = love.graphics

    -- -------------------------------------------------------------------------
    -- Crosshair (build mode bracket crosshair)
    -- -------------------------------------------------------------------------
    local cx = screenW / 2
    local cy = screenH / 2
    local crossSize = 10
    if ghostValid then
        lg.setColor(0.3, 1.0, 0.4, 0.8)
    else
        lg.setColor(1.0, 0.4, 0.4, 0.8)
    end
    lg.setLineWidth(2)
    lg.line(cx - crossSize, cy, cx + crossSize, cy)
    lg.line(cx, cy - crossSize, cx, cy + crossSize)
    local bSize = 6
    lg.line(cx - crossSize, cy - crossSize, cx - crossSize + bSize, cy - crossSize)
    lg.line(cx - crossSize, cy - crossSize, cx - crossSize, cy - crossSize + bSize)
    lg.line(cx + crossSize, cy - crossSize, cx + crossSize - bSize, cy - crossSize)
    lg.line(cx + crossSize, cy - crossSize, cx + crossSize, cy - crossSize + bSize)
    lg.line(cx - crossSize, cy + crossSize, cx - crossSize + bSize, cy + crossSize)
    lg.line(cx - crossSize, cy + crossSize, cx - crossSize, cy + crossSize - bSize)
    lg.line(cx + crossSize, cy + crossSize, cx + crossSize - bSize, cy + crossSize)
    lg.line(cx + crossSize, cy + crossSize, cx + crossSize, cy + crossSize - bSize)
    lg.setLineWidth(1)

    -- -------------------------------------------------------------------------
    -- Ghost tile status (below crosshair)
    -- -------------------------------------------------------------------------
    lg.setFont(getFont(13))
    local statusY = cy + 30

    if ghostTileX and ghostTileY then
        if ghostValid then
            lg.setColor(0.3, 1.0, 0.4, 0.9)
            lg.printf("Click to place " .. (def and def.name or "building"), 0, statusY, screenW, "center")
        else
            lg.setColor(1.0, 0.35, 0.35, 0.9)
            lg.printf(ghostReason or "Cannot place here", 0, statusY, screenW, "center")
        end
    else
        lg.setColor(0.6, 0.6, 0.6, 0.7)
        lg.printf("Look at a floor tile to place", 0, statusY, screenW, "center")
    end

    -- -------------------------------------------------------------------------
    -- Bottom panel: Selected building + compact selector
    -- -------------------------------------------------------------------------

    -- Compact card grid at bottom-center
    local cardW = 60
    local cardH = 56
    local cardGap = 4
    local numCards = #TYPES_LIST
    local gridCols = math_min(numCards, 6)
    local gridRows = math.ceil(numCards / gridCols)
    local gridW = gridCols * (cardW + cardGap) - cardGap
    local gridH = gridRows * (cardH + cardGap) - cardGap

    -- Detail panel width (shows selected building info)
    local detailW = 200
    local detailH = gridH + 8

    -- Total panel
    local totalPanelW = detailW + 12 + gridW + 20
    local panelH = math_max(detailH, gridH) + 52
    local panelX = (screenW - totalPanelW) / 2
    local panelY = screenH - panelH - 8

    -- Background
    lg.setColor(0.04, 0.06, 0.10, 0.88)
    lg.rectangle("fill", panelX, panelY, totalPanelW, panelH, 8, 8)
    lg.setColor(0.2, 0.4, 0.6, 0.5)
    lg.setLineWidth(1)
    lg.rectangle("line", panelX, panelY, totalPanelW, panelH, 8, 8)

    -- ---- Header row ----
    local headerY = panelY + 6
    lg.setFont(getFont(13))
    lg.setColor(0.3, 0.8, 1.0)
    lg.print("BUILD", panelX + 10, headerY)

    -- Power balance in header
    local powerBal = Building.getPowerBalance()
    local powerStr = (powerBal >= 0 and "+" or "") .. powerBal .. "W"
    if powerBal > 0 then
        lg.setColor(0.3, 1.0, 0.4)
    elseif powerBal == 0 then
        lg.setColor(0.7, 0.7, 0.3)
    else
        lg.setColor(1.0, 0.3, 0.3)
    end
    lg.print(powerStr, panelX + totalPanelW - getFont(13):getWidth(powerStr) - 10, headerY)

    -- Controls hint
    lg.setFont(getFont(10))
    lg.setColor(0.5, 0.6, 0.7, 0.7)
    lg.printf("Q/R Cycle | Click Place | X Remove | B/ESC Exit", panelX, headerY + 2, totalPanelW, "center")

    -- ---- Detail panel (left side) ----
    local detailX = panelX + 10
    local detailY = headerY + 22

    if def then
        -- Building color bar
        lg.setColor(def.color[1], def.color[2], def.color[3])
        lg.rectangle("fill", detailX, detailY, 4, detailH - 4, 2, 2)

        -- Name
        lg.setFont(getFont(14))
        lg.setColor(1, 1, 1)
        lg.print(def.name, detailX + 10, detailY + 2)

        -- Description
        lg.setFont(getFont(10))
        lg.setColor(0.7, 0.8, 0.9)
        lg.printf(def.description, detailX + 10, detailY + 20, detailW - 20, "left")

        -- Cost
        local costY = detailY + 42
        lg.setFont(getFont(10))
        for resource, amount in pairs(def.cost) do
            local have = (inventory and inventory[resource]) or 0
            local enough = have >= amount
            if enough then
                lg.setColor(0.4, 1.0, 0.4)
            else
                lg.setColor(1.0, 0.35, 0.35)
            end
            -- Clean resource name (replace underscores with spaces)
            local cleanName = resource:gsub("_", " ")
            lg.print(cleanName .. " x" .. amount .. " (" .. have .. ")", detailX + 10, costY)
            costY = costY + 13
        end

        -- Power / Crew info
        if def.power ~= 0 then
            if def.power > 0 then
                lg.setColor(0.3, 1.0, 0.4)
                lg.print("+" .. def.power .. "W power", detailX + 10, costY)
            else
                lg.setColor(1.0, 0.6, 0.3)
                lg.print(def.power .. "W power", detailX + 10, costY)
            end
            costY = costY + 13
        end
        if def.crew > 0 then
            lg.setColor(0.5, 0.85, 1.0)
            lg.print("+" .. def.crew .. " crew cap", detailX + 10, costY)
        end
    end

    -- ---- Building grid (right side) ----
    local gridX = panelX + detailW + 16
    local gridY = headerY + 22

    lg.setFont(getFont(9))

    for i, bDef in ipairs(TYPES_LIST) do
        local col = (i - 1) % gridCols
        local row = math_floor((i - 1) / gridCols)
        local slotX = gridX + col * (cardW + cardGap)
        local slotY = gridY + row * (cardH + cardGap)
        local isSelected = (i == selectedIdx)

        -- Card background
        if isSelected then
            lg.setColor(bDef.color[1] * 0.25, bDef.color[2] * 0.25, bDef.color[3] * 0.25, 0.95)
            lg.rectangle("fill", slotX, slotY, cardW, cardH, 4, 4)
            lg.setColor(bDef.color[1], bDef.color[2], bDef.color[3], 0.9)
            lg.setLineWidth(2)
            lg.rectangle("line", slotX, slotY, cardW, cardH, 4, 4)
            lg.setLineWidth(1)
        else
            lg.setColor(0.08, 0.10, 0.14, 0.9)
            lg.rectangle("fill", slotX, slotY, cardW, cardH, 4, 4)
            -- Subtle border
            lg.setColor(0.2, 0.25, 0.3, 0.4)
            lg.rectangle("line", slotX, slotY, cardW, cardH, 4, 4)
        end

        -- Color icon (centered circle-ish square)
        local iconSize = 16
        local iconX = slotX + (cardW - iconSize) / 2
        local iconY = slotY + 6
        lg.setColor(bDef.color[1], bDef.color[2], bDef.color[3], isSelected and 1.0 or 0.7)
        lg.rectangle("fill", iconX, iconY, iconSize, iconSize, 3, 3)

        -- Building abbreviation/icon inside the square
        lg.setColor(0, 0, 0, 0.6)
        local abbrev = bDef.name:sub(1, 2):upper()
        local abbrevW = getFont(9):getWidth(abbrev)
        lg.print(abbrev, iconX + (iconSize - abbrevW) / 2, iconY + 3)

        -- Name (truncated)
        local shortName = bDef.name
        if getFont(9):getWidth(shortName) > cardW - 4 then
            -- Abbreviate long names
            shortName = shortName:match("^(%S+)") or shortName
        end
        if isSelected then
            lg.setColor(1, 1, 1)
        else
            lg.setColor(0.6, 0.65, 0.7)
        end
        local nameW = getFont(9):getWidth(shortName)
        lg.print(shortName, slotX + (cardW - nameW) / 2, slotY + 26)

        -- Power cost indicator (small)
        if bDef.power ~= 0 then
            if bDef.power > 0 then
                lg.setColor(0.3, 0.9, 0.4, 0.8)
            else
                lg.setColor(1.0, 0.6, 0.3, 0.7)
            end
            local pwrStr = (bDef.power > 0 and "+" or "") .. bDef.power .. "W"
            local pwrW = getFont(9):getWidth(pwrStr)
            lg.print(pwrStr, slotX + (cardW - pwrW) / 2, slotY + 38)
        end

        -- Affordability indicator (small dot)
        local canAfford = true
        if inventory then
            for resource, amount in pairs(bDef.cost) do
                if (inventory[resource] or 0) < amount then
                    canAfford = false
                    break
                end
            end
        end
        if not canAfford then
            lg.setColor(1.0, 0.2, 0.2, 0.7)
            lg.circle("fill", slotX + cardW - 5, slotY + 5, 3)
        end
    end

    lg.pop()
end

-- =============================================================================
-- Render helpers for raycaster integration
-- =============================================================================

--- Get the pulse alpha for the ghost preview tile.
--- Returns a value between 0.2 and 0.6 for smooth pulsing.
function Building.getGhostAlpha()
    return 0.3 + math_sin(pulsePhase) * 0.15
end

--- Returns the ghost info as a table for the raycaster floor renderer.
--- { x, y, r, g, b, a, valid }
function Building.getGhostInfo()
    if not buildMode or not ghostTileX then return nil end

    local def = TYPES_LIST[selectedIdx]
    if not def then return nil end

    local alpha = Building.getGhostAlpha()

    return {
        x     = ghostTileX,
        y     = ghostTileY,
        r     = def.color[1],
        g     = def.color[2],
        b     = def.color[3],
        a     = alpha,
        valid = ghostValid,
    }
end

-- =============================================================================
-- Serialization
-- =============================================================================

function Building.getSaveData()
    local buildingList = {}
    for key, entry in pairs(placedBuildings) do
        buildingList[#buildingList + 1] = {
            id    = entry.def.id,
            x     = entry.x,
            y     = entry.y,
            floor = entry.floor,
        }
    end

    return {
        buildings   = buildingList,
        selectedIdx = selectedIdx,
    }
end

function Building.loadSaveData(data, map)
    if not data then return end

    placedBuildings = {}

    -- Rebuild lookup tables (in case init was not called or was reset)
    if not next(typeById) then
        for _, def in ipairs(TYPES_LIST) do
            typeById[def.id]     = def
            typeByTile[def.tile] = def
        end
    end

    selectedIdx = data.selectedIdx or 1
    if selectedIdx < 1 or selectedIdx > #TYPES_LIST then
        selectedIdx = 1
    end

    if data.buildings then
        for _, entry in ipairs(data.buildings) do
            local def = typeById[entry.id]
            if def and entry.x and entry.y then
                local floor = entry.floor or 1
                local key = buildingKey(entry.x, entry.y, floor)
                placedBuildings[key] = {
                    def   = def,
                    x     = entry.x,
                    y     = entry.y,
                    floor = floor,
                }

                -- Restore the tile on the map if we have the correct floor loaded
                if map and (map.currentFloor or 1) == floor then
                    map:setTile(entry.x, entry.y, def.tile)
                end
            end
        end
    end
end

--- Restore building tiles for a given floor number.
--- Call this when the player changes floors so the map data reflects
--- buildings placed on that floor.
function Building.restoreFloorTiles(map, floorNum)
    if not map then return end
    floorNum = floorNum or (map.currentFloor or 1)

    for _, entry in pairs(placedBuildings) do
        if entry.floor == floorNum then
            map:setTile(entry.x, entry.y, entry.def.tile)
        end
    end
end

return Building
