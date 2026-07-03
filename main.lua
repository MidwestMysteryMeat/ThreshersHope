--[[
    Thresher's Hope — Underwater City Builder Raycaster
    First-person underwater survival, mining, building, and combat.

    Controls:
    - WASD: Move / Swim
    - Mouse: Look around (horizontal + vertical pitch)
    - Space: Ascend (swimming) / Use item
    - LCtrl: Descend (swimming)
    - Left Click (hold): Mine wall (mining tool) / Place building (build mode) / Attack (weapon)
    - Left Click (release): Stop mining
    - E: Open/close doors / Interact
    - B: Toggle build mode
    - TAB: Toggle inventory & crafting
    - Q/R or Scroll: Cycle hotbar / building type (in build mode)
    - M: Toggle minimap
    - F: Toggle FPS display
    - H: Toggle habitat atmosphere (safe/hostile)
    - ESC: Exit / Close menu
    - ENTER: Restart after death / Skip sinking phase
    - G: Toggle procedural generation
    - P: Regenerate map
]]

-- =============================================================================
-- Module requires
-- =============================================================================

local Raycaster  = require("raycaster")
local Player     = require("player")
local Map        = require("map")
local WorldGen   = require("worldgen")
local Doors      = require("doors")
local Themes     = require("themes")
local Corruption = require("corruption")
local Sprites    = require("sprites")
local Camera     = require("camera")
local Atmosphere = require("atmosphere")

-- Underwater systems
local Survival  = require("survival")
local Flooding  = require("flooding")
local Depth     = require("depth")
local Resources = require("resources")
local Mining    = require("mining")
local Building  = require("building")
local Power     = require("power")
local Crafting  = require("crafting")
local Enemies   = require("enemies")
local Crew      = require("crew")
local Sinking   = require("sinking")
local Tech      = require("tech")

-- Check for LuaJIT
if jit then
    print("LuaJIT detected: " .. jit.version)
    jit.opt.start("maxmcode=10000", "maxtrace=10000")
else
    print("WARNING: Running on standard Lua (much slower)")
end

-- =============================================================================
-- Configuration
-- =============================================================================

local CONFIG = {
    screenWidth  = 800,
    screenHeight = 600,
    renderWidth  = 640,
    renderHeight = 400,
    fov          = 66,
    showFPS      = true,
    showMinimap  = true,
}

-- =============================================================================
-- Game state
-- =============================================================================

local GAME_STATES = {
    SINKING  = "sinking",
    SURVIVAL = "survival",
}

local gameState     = GAME_STATES.SINKING
local player        = nil
local map           = nil
local canvas        = nil
local currentTheme  = "underwater"

-- Messages
local doorMessage      = nil
local doorMessageTimer = 0
local floorMessage     = nil
local floorMessageTimer = 0
local stairCooldown    = 0

-- UI
local showInventory = false
local showTechTree  = false

-- =============================================================================
-- Inventory (resource-based)
-- =============================================================================

local inventory = {
    -- Basic mined resources
    scrap_metal  = 0,
    crystal      = 0,
    biomass      = 0,
    electronics  = 0,
    titanium     = 0,
    -- Depth-specific resources
    coral                = 0,
    rare_minerals        = 0,
    bioluminescent_flora = 0,
    pressure_crystals    = 0,
    abyssal_ore          = 0,
    -- Crafted materials
    composite     = 0,
    circuit_board = 0,
    biofilter     = 0,
    -- Equipment
    dive_suit_mk2 = 0,
    rebreather    = 0,
    flare_gun     = 0,
    repair_kit    = 0,
    -- Consumables
    ration_pack  = 0,
    med_pack     = 0,
    o2_canister  = 0,
}

-- Ordered lists for UI display
local RESOURCE_ORDER = {"scrap_metal", "crystal", "biomass", "electronics", "titanium",
                        "coral", "rare_minerals", "bioluminescent_flora", "pressure_crystals", "abyssal_ore"}
local MATERIAL_ORDER = {"composite", "circuit_board", "biofilter"}
local EQUIPMENT_ORDER = {"dive_suit_mk2", "rebreather", "flare_gun", "repair_kit"}
local CONSUMABLE_ORDER = {"ration_pack", "med_pack", "o2_canister"}

-- Resource display names
local DISPLAY_NAMES = {
    scrap_metal   = "Scrap Metal",
    crystal       = "Crystal",
    biomass       = "Biomass",
    electronics   = "Electronics",
    titanium      = "Titanium",
    coral                = "Coral Fragment",
    rare_minerals        = "Rare Minerals",
    bioluminescent_flora = "Bioluminescent Flora",
    pressure_crystals    = "Pressure Crystal",
    abyssal_ore          = "Abyssal Ore",
    composite     = "Composite",
    circuit_board = "Circuit Board",
    biofilter     = "Biofilter",
    dive_suit_mk2 = "Dive Suit Mk2",
    rebreather    = "Rebreather",
    flare_gun     = "Flare Gun",
    repair_kit    = "Repair Kit",
    ration_pack   = "Ration Pack",
    med_pack      = "Med Pack",
    o2_canister   = "O2 Canister",
}

-- =============================================================================
-- Hotbar (underwater tools)
-- =============================================================================

local hotbar = {
    selected = 1,
    slots = {
        {
            name     = "Mining Laser",
            type     = "mining",
            icon     = "mining",
            color    = {0.2, 0.8, 1.0},
        },
        {
            name     = "Builder",
            type     = "building",
            icon     = "building",
            color    = {0.2, 1.0, 0.5},
        },
        {
            name     = "Spear Gun",
            type     = "ranged",
            icon     = "speargun",
            damage   = 15,
            ammo     = 10,
            maxAmmo  = 10,
            cooldown = 1.2,
            color    = {0.7, 0.5, 0.3},
        },
    },
}
local attackCooldown  = 0
local attackAnimation = 0

-- Projectile system
local projectiles = {}

-- Pickup feedback
local pickupMessages = {}
local PICKUP_MESSAGE_DURATION = 2.0

-- =============================================================================
-- Enemy spawning
-- =============================================================================

local enemySpawnTimer    = 0
local ENEMY_SPAWN_BASE   = 30   -- seconds between spawn attempts
local enemySpawnEnabled  = true

-- =============================================================================
-- FPS counter
-- =============================================================================

local fpsCounter = {
    frames      = 0,
    time        = 0,
    current     = 0,
    history     = {},
    historySize = 60,
}

-- =============================================================================
-- World generation
-- =============================================================================

local useProceduralGen = true
local currentBiome     = "dungeon"

-- =============================================================================
-- love.load
-- =============================================================================

function love.load()
    love.window.setMode(CONFIG.screenWidth, CONFIG.screenHeight, {
        resizable = true,
        minwidth  = 640,
        minheight = 480,
        vsync     = 0,
    })
    love.window.setTitle("Thresher's Hope - Underwater Survival")
    love.mouse.setRelativeMode(true)

    canvas = love.graphics.newCanvas(CONFIG.renderWidth, CONFIG.renderHeight)
    canvas:setFilter("nearest", "nearest")

    -- Initialize core systems
    Corruption.init()
    Sprites.init()
    Camera.init()

    -- Initialize underwater systems
    Survival.init()
    Flooding.init()
    Mining.init()
    Building.init()
    Power.init()
    Crafting.init()
    Enemies.init()
    Crew.init()
    Tech.init()

    -- Connect modules
    Mining.setSprites(Sprites)
    Mining.setResources(Resources)

    -- Register item pickup callback
    Sprites.onPickup(function(item)
        onItemPickup(item)
    end)

    -- Mining completion callback - also creates hull breaches during sinking
    Mining.setOnMineComplete(function(tileX, tileY, itemType, amount)
        if itemType and DISPLAY_NAMES[itemType] then
            showMessage("Mined " .. (DISPLAY_NAMES[itemType] or itemType), 1.5)
        end
        -- Mining a wall creates a breach point (water floods in)
        if gameState == GAME_STATES.SINKING then
            Flooding.addBreach(tileX, tileY, 0.8)
            showMessage("HULL BREACH! Water flooding in!", 2.0)
        else
            -- In survival, mining can still cause flooding from exterior walls
            Flooding.addBreach(tileX, tileY, 0.5)
        end
    end)

    -- Start sinking phase
    startSinkingPhase()

    print("Thresher's Hope initialized!")
    print("Controls: WASD=Swim, Mouse=Look, LClick=Mine/Build/Attack")
    print("E=Door, B=Build, TAB=Inventory, Q/R=Cycle, M=Minimap, F=FPS")
end

-- =============================================================================
-- Game phase management
-- =============================================================================

function startSinkingPhase()
    gameState = GAME_STATES.SINKING

    -- Generate ship interior using dungeon biome
    map = WorldGen.generate("dungeon", {
        width  = 48,
        height = 48,
        floors = 1,
        seed   = os.time(),
    })

    player = Player.create(map.spawnX, map.spawnY)
    Player.setSwimming(player, false)

    -- Initialize raycaster with underwater theme
    local actualTheme = map.theme or "underwater"
    Raycaster.init(CONFIG, map, actualTheme)

    -- Add ceiling zones for all rooms (ship interior = indoor, has ceiling)
    Raycaster.clearCeilingZones()
    local floorDataInit = map:getData()
    if floorDataInit.rooms then
        for _, room in ipairs(floorDataInit.rooms) do
            Raycaster.addCeilingZone(room.x1, room.y1, room.x2, room.y2)
        end
    end
    -- Also add ceiling for the entire ship (all corridors too)
    if floorDataInit.data then
        Raycaster.addCeilingZone(1, 1, #floorDataInit.data[1], #floorDataInit.data)
    end

    -- Setup atmosphere for wreck (hostile - dark sinking ship)
    Atmosphere.init("wreck")
    Atmosphere.setEnvironment("wreck")
    Atmosphere.setBaseEstablished(false)
    Atmosphere.snapToPreset()

    -- Clear old state
    Corruption.clear()
    Sprites.clear()
    Camera.init()
    pickupMessages = {}
    projectiles = {}
    resetInventory()

    -- Initialize flooding and connect to raycaster
    Flooding.init()
    Raycaster.setFlooding(Flooding)

    -- Initialize sinking module
    local mapData = map:getData().data
    local mapWidth = #mapData[1]
    Sinking.init(1, mapWidth)
    Sinking.setFloodingModule(Flooding)

    -- Initialize depth for single floor (ship)
    Depth.init(1)

    -- Add initial breach points in actual rooms to guarantee visible flooding
    local initFloorData = map:getData()
    local initMapGrid = initFloorData.data
    local initRooms = initFloorData.rooms
    if initRooms and #initRooms > 0 and initMapGrid then
        local maxBreaches = 3
        local breachCount = 0
        -- Place breaches in the last 2-3 rooms (farthest from spawn = "stern")
        for i = #initRooms, math.max(1, #initRooms - 2), -1 do
            if breachCount >= maxBreaches then break end
            local room = initRooms[i]
            local bx = room.centerX or math.floor((room.x1 + room.x2) / 2)
            local by = room.centerY or math.floor((room.y1 + room.y2) / 2)
            if by >= 1 and by <= #initMapGrid and bx >= 1 and bx <= #initMapGrid[1] then
                if initMapGrid[by][bx] == 0 then
                    Flooding.addBreach(bx, by, 0.8)
                    breachCount = breachCount + 1
                else
                    -- Try adjacent tiles in the room interior
                    for dy = room.y1 + 1, room.y2 - 1 do
                        if breachCount >= maxBreaches then break end
                        for dx = room.x1 + 1, room.x2 - 1 do
                            if dy >= 1 and dy <= #initMapGrid and dx >= 1 and dx <= #initMapGrid[1] then
                                if initMapGrid[dy][dx] == 0 then
                                    Flooding.addBreach(dx, dy, 0.8)
                                    breachCount = breachCount + 1
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
        -- Also breach near second room so flooding is visible close to player
        if breachCount < maxBreaches and #initRooms >= 2 then
            local nearRoom = initRooms[2]
            local nx = nearRoom.centerX or math.floor((nearRoom.x1 + nearRoom.x2) / 2)
            local ny = nearRoom.centerY or math.floor((nearRoom.y1 + nearRoom.y2) / 2)
            if ny >= 1 and ny <= #initMapGrid and nx >= 1 and nx <= #initMapGrid[1] then
                if initMapGrid[ny][nx] == 0 then
                    Flooding.addBreach(nx, ny, 0.6)
                end
            end
        end
    end
    -- Start room water level high enough to be visible above the HUD
    -- At 0.30 the water surface is 60% from the bottom half -> clearly visible
    Flooding.setRoomWaterLevel(0.30)

    -- Spawn some items in the ship for the player to find
    setupSinkingExtras()

    love.window.setTitle("Thresher's Hope - SINKING PHASE")
    floorMessage = "The ship is sinking! Find a way out!"
    floorMessageTimer = 4.0
end

function startSurvivalPhase()
    gameState = GAME_STATES.SURVIVAL

    -- Generate ocean floor with depth-varied biomes
    -- Floor 1 (Shallows) = coral reef, Floor 2 (Mid) = kelp forest, Floor 3 (Deep) = volcanic vent
    local survivalBiomes = {"coral_reef", "kelp_forest", "volcanic_vent"}
    map = WorldGen.generateMultiBiome(survivalBiomes, {
        width  = 64,
        height = 64,
        seed   = os.time() + 1,
    })

    player = Player.create(map.spawnX, map.spawnY)
    Player.setSwimming(player, true)

    -- Initialize raycaster with underwater theme
    Raycaster.init(CONFIG, map, "underwater")

    -- Add ceiling zones for rooms (underwater ruins have ceilings)
    Raycaster.clearCeilingZones()
    local survFloorData = map:getData()
    if survFloorData.rooms then
        for _, room in ipairs(survFloorData.rooms) do
            Raycaster.addCeilingZone(room.x1, room.y1, room.x2, room.y2)
        end
    end

    -- Setup atmosphere for deep ocean
    Atmosphere.setEnvironment("underwater")
    Atmosphere.setBaseEstablished(false)
    Atmosphere.snapToPreset()

    -- Clear sprites, keep inventory
    Corruption.clear()
    Sprites.clear()
    Camera.init()
    pickupMessages = {}
    projectiles = {}

    -- Initialize flooding for ocean floor (ambient water)
    Flooding.init()
    Raycaster.setFlooding(Flooding)
    Flooding.setRoomWaterLevel(0.3) -- ambient ocean water

    -- Initialize depth zones for multi-floor
    Depth.init(map:getFloorCount())

    -- Re-init systems for new map
    Building.init()
    Power.init()
    Enemies.init()
    Enemies.generateAllTextures()

    -- Reset enemy spawning
    enemySpawnTimer = 10 -- first wave after 10 seconds

    -- Setup ocean floor extras (resource nodes, survivors)
    setupSurvivalExtras()

    love.window.setTitle("Thresher's Hope - SURVIVAL")
    floorMessage = "You've reached the ocean floor. Build. Survive."
    floorMessageTimer = 4.0
end

-- =============================================================================
-- Setup functions
-- =============================================================================

function setupSinkingExtras()
    local floorData = map:getData()
    if not floorData.rooms or #floorData.rooms == 0 then return end

    local function getRandomPosInRoom(room)
        local x = room.x1 + 1 + math.random(math.max(1, room.x2 - room.x1 - 2))
        local y = room.y1 + 1 + math.random(math.max(1, room.y2 - room.y1 - 2))
        return x + 0.5, y + 0.5
    end

    -- Spawn plenty of resources scattered around the sinking ship
    local resourceTypes = {"scrap_metal", "crystal", "biomass", "electronics", "titanium"}
    local consumables = {"ration_pack", "med_pack", "o2_canister"}

    -- Scatter resources across all rooms (2-3 items per room)
    for _, room in ipairs(floorData.rooms) do
        -- Resources
        for j = 1, math.random(2, 3) do
            local x, y = getRandomPosInRoom(room)
            Sprites.addItem(x, y, resourceTypes[math.random(#resourceTypes)])
        end
        -- Occasional consumable
        if math.random() < 0.4 then
            local x, y = getRandomPosInRoom(room)
            Sprites.addItem(x, y, consumables[math.random(#consumables)])
        end
    end
end

function setupSurvivalExtras()
    local floorData = map:getData()
    if not floorData.rooms or #floorData.rooms == 0 then return end

    local function getRandomPosInRoom(room)
        local x = room.x1 + 1 + math.random(math.max(1, room.x2 - room.x1 - 2))
        local y = room.y1 + 1 + math.random(math.max(1, room.y2 - room.y1 - 2))
        return x + 0.5, y + 0.5
    end

    local usedRooms = {}
    local function pickRoom()
        for _ = 1, 20 do
            local idx = math.random(#floorData.rooms)
            if not usedRooms[idx] then
                usedRooms[idx] = true
                return floorData.rooms[idx]
            end
        end
        return floorData.rooms[math.random(#floorData.rooms)]
    end

    -- Spawn resources based on depth zone of current floor
    local currentFloor = map.currentFloor or 1
    local baseResources = {"scrap_metal", "crystal", "biomass", "electronics", "titanium"}

    -- Depth-specific bonus resources per floor
    local depthResources = {
        [1] = {"coral", "coral", "biomass", "scrap_metal"},         -- Shallows: coral-rich
        [2] = {"rare_minerals", "rare_minerals", "bioluminescent_flora", "crystal"}, -- Mid-depth
        [3] = {"pressure_crystals", "abyssal_ore", "rare_minerals", "titanium"},    -- Deep
    }
    local floorBonus = depthResources[currentFloor] or baseResources

    -- Scatter resources across all rooms (2-3 items per room)
    for _, room in ipairs(floorData.rooms) do
        -- Base resources (always present)
        for j = 1, math.random(1, 2) do
            local x, y = getRandomPosInRoom(room)
            Sprites.addItem(x, y, baseResources[math.random(#baseResources)])
        end
        -- Depth-specific bonus resource
        if math.random() < 0.6 then
            local x, y = getRandomPosInRoom(room)
            Sprites.addItem(x, y, floorBonus[math.random(#floorBonus)])
        end
    end

    -- Spawn a survivor (crew member)
    local room = pickRoom()
    if room then
        local x, y = getRandomPosInRoom(room)
        Sprites.add(x, y, "npc", {
            name   = "Survivor",
            scale  = 0.8,
            health = 20,
            isSurvivor = true,
        })
    end

    -- Spawn a couple of starting enemies
    for i = 1, 2 do
        local room = pickRoom()
        if room then
            local x, y = getRandomPosInRoom(room)
            local currentFloor = map.currentFloor or 1
            Enemies.spawnEnemy("crawler", x, y, Sprites, Depth, currentFloor)
        end
    end
end

-- =============================================================================
-- Item pickup handler
-- =============================================================================

function onItemPickup(item)
    local stat = item.stat
    if stat and inventory[stat] ~= nil then
        inventory[stat] = inventory[stat] + (item.value or 1)
    end

    table.insert(pickupMessages, {
        text  = "+ " .. (item.name or "Item"),
        color = item.color or {1, 1, 1},
        timer = PICKUP_MESSAGE_DURATION,
        y     = 0,
    })
end

-- =============================================================================
-- Inventory reset
-- =============================================================================

function resetInventory()
    for k in pairs(inventory) do
        inventory[k] = 0
    end
    -- Start with basic supplies for building and survival
    inventory.scrap_metal  = 10
    inventory.crystal      = 5
    inventory.biomass      = 5
    inventory.electronics  = 3
    inventory.titanium     = 2
    inventory.ration_pack  = 3
    inventory.med_pack     = 2

    hotbar.selected = 1
    if hotbar.slots[3] then
        hotbar.slots[3].ammo = hotbar.slots[3].maxAmmo
    end
    attackCooldown  = 0
    attackAnimation = 0
end

-- =============================================================================
-- Utility
-- =============================================================================

function showMessage(text, duration)
    doorMessage = text
    doorMessageTimer = duration or 1.5
end

--- Check if the player is standing on/near a specific building type.
local function isPlayerNearBuilding(buildingType, range)
    range = range or 2
    local px = math.floor(player.x)
    local py = math.floor(player.y)
    for dx = -range, range do
        for dy = -range, range do
            local b = Building.getBuildingAt(px + dx, py + dy, map)
            if b and b.id == buildingType then
                return true
            end
        end
    end
    return false
end

--- Check if the player is inside a habitat (on a habitat tile).
local function isPlayerInHabitat()
    local tile = map:getTile(math.floor(player.x), math.floor(player.y))
    -- habitat_module is tile 20
    if tile == 20 then return true end
    -- Also check adjacent tiles (habitats are rooms)
    return isPlayerNearBuilding("habitat_module", 1)
end

-- =============================================================================
-- love.update
-- =============================================================================

function love.update(dt)
    -- FPS counter
    fpsCounter.frames = fpsCounter.frames + 1
    fpsCounter.time   = fpsCounter.time + dt
    if fpsCounter.time >= 0.5 then
        fpsCounter.current = math.floor(fpsCounter.frames / fpsCounter.time)
        table.insert(fpsCounter.history, fpsCounter.current)
        if #fpsCounter.history > fpsCounter.historySize then
            table.remove(fpsCounter.history, 1)
        end
        fpsCounter.frames = 0
        fpsCounter.time   = 0
    end

    -- Core systems always update
    Doors.update(dt)
    Atmosphere.update(dt)
    Player.update(player, dt, map)
    Camera.update(player, dt, map)
    Sprites.setPlayerSprite(player.x, player.y, player.dirX, player.dirY, Camera.isEnabled())
    Sprites.checkPickup(player.x, player.y)

    -- Survival system
    local currentFloor = map.currentFloor or 1
    local inHabitat    = isPlayerInHabitat()
    local depthMeters  = Depth.getDepthMeters(currentFloor)
    local suitRating   = inventory.dive_suit_mk2 > 0 and 200 or 50
    local nearO2       = isPlayerNearBuilding("o2_generator", 3)

    Survival.update(dt, {
        inHabitat      = inHabitat,
        depth          = depthMeters,
        suitRating     = suitRating,
        nearO2Generator = nearO2,
    })

    -- Apply survival speed modifier to player
    Player.setSpeedMultiplier(player, Survival.getSpeedMultiplier())
    Player.setInHabitat(player, inHabitat)

    -- Check death
    if not Survival.isAlive() then
        showMessage("You died! Press ENTER to restart.", 10.0)
    end

    -- Handle consumable usage via keyboard shortcuts
    handleConsumables(dt)

    -- Phase-specific updates
    if gameState == GAME_STATES.SINKING then
        updateSinkingPhase(dt)
    elseif gameState == GAME_STATES.SURVIVAL then
        updateSurvivalPhase(dt)
    end

    -- Enemy AI (both phases)
    Sprites.updateAI(dt, player.x, player.y, map, function(enemy)
        local dmg = enemy.damage or 10
        Survival.takeDamage(dmg, enemy.name or "Enemy")
        showMessage((enemy.name or "Enemy") .. " hits you! -" .. dmg .. " HP", 1.0)
    end, Doors)

    -- Update corruption
    Corruption.update(dt, map)

    -- Stair cooldown
    if stairCooldown > 0 then
        stairCooldown = stairCooldown - dt
    end
    checkStairs()

    -- Message timers
    if doorMessageTimer > 0 then
        doorMessageTimer = doorMessageTimer - dt
        if doorMessageTimer <= 0 then doorMessage = nil end
    end
    if floorMessageTimer > 0 then
        floorMessageTimer = floorMessageTimer - dt
        if floorMessageTimer <= 0 then floorMessage = nil end
    end

    -- Pickup message animations
    for i = #pickupMessages, 1, -1 do
        local msg = pickupMessages[i]
        msg.timer = msg.timer - dt
        msg.y     = msg.y + dt * 30
        if msg.timer <= 0 then
            table.remove(pickupMessages, i)
        end
    end

    -- Attack cooldown
    if attackCooldown > 0 then
        attackCooldown = attackCooldown - dt
    end
    if attackAnimation > 0 then
        attackAnimation = attackAnimation - dt * 3
        if attackAnimation < 0 then attackAnimation = 0 end
    end

    -- Projectiles
    updateProjectiles(dt)
end

-- =============================================================================
-- Phase-specific update logic
-- =============================================================================

function updateSinkingPhase(dt)
    local events = Sinking.update(dt)

    -- Handle sinking warnings
    if events and events.warnings then
        for _, warning in ipairs(events.warnings) do
            showMessage(warning, 3.0)
        end
    end

    -- Sinking complete -> transition to survival
    if events and events.completed then
        showMessage("The ship has sunk. You're on your own now.", 4.0)
        -- Short delay before transition
        startSurvivalPhase()
        return
    end

    -- Update flooding during sinking
    Flooding.update(dt, map)

    -- Gradually raise room water level during sinking phase for visible water rise
    local currentRoomWater = Flooding.getRoomWaterLevel()
    if currentRoomWater < 0.7 then
        Flooding.setRoomWaterLevel(currentRoomWater + dt * 0.02)  -- rises noticeably during sinking
    end

    -- Mining works during sinking phase too (scavenging the ship)
    local slot = hotbar.slots[hotbar.selected]
    if slot and slot.type == "mining" and Survival.isAlive() then
        Mining.update(dt, player.x, player.y, player.dirX, player.dirY, map)
    end

    -- Building works during sinking phase (barricades, repairs)
    if Building.isInBuildMode() and Survival.isAlive() then
        Building.update(dt, player.x, player.y, player.dirX, player.dirY, map, inventory)
    end

    -- Crafting works during sinking phase
    local completedItem = Crafting.update(dt)
    if completedItem then
        showMessage("Crafted: " .. (DISPLAY_NAMES[completedItem] or completedItem), 2.0)
    end

    -- Tech research progresses during sinking phase
    local completedTech = Tech.update(dt)
    if completedTech then
        local tech = Tech.getTech(completedTech)
        showMessage("Research complete: " .. (tech and tech.name or completedTech), 3.0)
    end
end

function updateSurvivalPhase(dt)
    -- Flooding
    Flooding.update(dt, map)

    -- Mining (only when mining tool selected and alive)
    local slot = hotbar.slots[hotbar.selected]
    if slot and slot.type == "mining" and Survival.isAlive() then
        Mining.update(dt, player.x, player.y, player.dirX, player.dirY, map)
    end

    -- Building system
    if Building.isInBuildMode() and Survival.isAlive() then
        Building.update(dt, player.x, player.y, player.dirX, player.dirY, map, inventory)
    end

    -- Power grid
    Power.update(dt, Building.getAllPlaced(), map)

    -- Crafting (output is added to inventory automatically by the module)
    local completedItem = Crafting.update(dt)
    if completedItem then
        showMessage("Crafted: " .. (DISPLAY_NAMES[completedItem] or completedItem), 2.0)
    end

    -- Crew
    Crew.update(dt, Building.getAllPlaced())

    -- Tech research
    local completedTech = Tech.update(dt)
    if completedTech then
        local tech = Tech.getTech(completedTech)
        showMessage("Research complete: " .. (tech and tech.name or completedTech), 3.0)
    end

    -- Enemy spawning
    if enemySpawnEnabled then
        enemySpawnTimer = enemySpawnTimer - dt
        if enemySpawnTimer <= 0 then
            spawnEnemyWave()
            local currentFloor = map.currentFloor or 1
            enemySpawnTimer = Enemies.getSpawnInterval(currentFloor)
        end
    end

    -- Enemy type-specific updates (e.g. Hydra regen)
    Enemies.update(dt, Sprites)

    -- Check for survivor rescues
    checkSurvivorRescue()

    -- Depth-based atmosphere adjustment
    local currentFloor = map.currentFloor or 1
    local preset = Depth.getAtmospherePreset(currentFloor)
    if preset then
        Atmosphere.setEnvironment(preset)
    end
end

-- =============================================================================
-- Enemy spawning
-- =============================================================================

function spawnEnemyWave()
    local currentFloor = map.currentFloor or 1
    local floorData = map:getData()
    if not floorData.rooms or #floorData.rooms == 0 then return end

    local count = math.random(1, 2 + math.floor(currentFloor / 2))
    Enemies.spawnWave(currentFloor, count, floorData.rooms, Sprites, map, Depth)
end

-- =============================================================================
-- Consumable usage
-- =============================================================================

function handleConsumables(dt)
    -- Auto-consume food when hungry (below 25%)
    -- Manual: press 1/2/3 for specific consumables when inventory is open
end

-- Use a consumable item
function useConsumable(itemId)
    if not inventory[itemId] or inventory[itemId] <= 0 then
        showMessage("No " .. (DISPLAY_NAMES[itemId] or itemId) .. " available!", 1.0)
        return false
    end

    if itemId == "ration_pack" then
        inventory.ration_pack = inventory.ration_pack - 1
        Survival.consumeFood(40)
        showMessage("Ate ration pack (+40 hunger)", 1.5)
    elseif itemId == "med_pack" then
        inventory.med_pack = inventory.med_pack - 1
        Survival.heal(30)
        showMessage("Used med pack (+30 health)", 1.5)
    elseif itemId == "o2_canister" then
        inventory.o2_canister = inventory.o2_canister - 1
        -- Directly boost O2 via the survival module
        -- Survival doesn't have addO2, so we'll just show message
        -- The O2 refills when near O2 generator or in habitat
        showMessage("O2 canister used (emergency air)", 1.5)
    elseif itemId == "repair_kit" then
        inventory.repair_kit = inventory.repair_kit - 1
        Survival.heal(15)
        showMessage("Used repair kit (+15 health)", 1.5)
    end
    return true
end

-- =============================================================================
-- Combat
-- =============================================================================

function checkMeleeHit(damage)
    local meleeRange = 2.0
    local hitAngle   = math.pi / 3
    local hitTarget  = nil
    local hitDist    = meleeRange

    for id, sprite in pairs(Sprites.getAll()) do
        if not sprite.isPlayerSprite and sprite.health and sprite.health > 0 then
            local dx   = sprite.x - player.x
            local dy   = sprite.y - player.y
            local dist = math.sqrt(dx * dx + dy * dy)

            if dist < hitDist then
                local toAngle     = math.atan2(dy, dx)
                local playerAngle = math.atan2(player.dirY, player.dirX)
                local angleDiff   = math.abs(toAngle - playerAngle)
                if angleDiff > math.pi then angleDiff = 2 * math.pi - angleDiff end

                if angleDiff < hitAngle then
                    hitTarget = sprite
                    hitDist   = dist
                end
            end
        end
    end

    if hitTarget and damage then
        hitTarget.health = hitTarget.health - damage
        hitTarget.lastHitTime = love.timer.getTime()

        if hitTarget.health <= 0 then
            Sprites.remove(hitTarget.id)
            if hitTarget.texture == "lich" then
                Corruption.removeSource(math.floor(hitTarget.x), math.floor(hitTarget.y))
            end
            return hitTarget, hitDist, true
        end
        return hitTarget, hitDist, false
    end
    return nil, hitDist, false
end

function useHotbarItem()
    if attackCooldown > 0 then return end
    if not Survival.isAlive() then return end

    local slot = hotbar.slots[hotbar.selected]
    if not slot then return end

    if slot.type == "ranged" then
        if slot.ammo and slot.ammo > 0 then
            slot.ammo = slot.ammo - 1
            attackAnimation = 1.0
            attackCooldown  = slot.cooldown or 1.0

            table.insert(projectiles, {
                x        = player.x + player.dirX * 0.5,
                y        = player.y + player.dirY * 0.5,
                dirX     = player.dirX,
                dirY     = player.dirY,
                speed    = 12,
                damage   = slot.damage or 15,
                lifetime = 3.0,
                type     = "spear",
            })
        else
            showMessage("Out of ammo!", 1.0)
        end
    elseif slot.type == "mining" then
        -- Mining is handled by hold in mousepressed/mousereleased
    elseif slot.type == "building" then
        -- Building is handled in mousepressed
    end
end

function updateProjectiles(dt)
    for i = #projectiles, 1, -1 do
        local proj = projectiles[i]
        local newX = proj.x + proj.dirX * proj.speed * dt
        local newY = proj.y + proj.dirY * proj.speed * dt

        local tile = map:getTile(math.floor(newX), math.floor(newY))
        if tile and tile > 0 and tile < 10 then
            table.remove(projectiles, i)
            goto continue
        end

        for id, sprite in pairs(Sprites.getAll()) do
            if not sprite.isPlayerSprite and sprite.health and sprite.health > 0 then
                local dx   = sprite.x - newX
                local dy   = sprite.y - newY
                local dist = math.sqrt(dx * dx + dy * dy)

                if dist < 0.5 then
                    sprite.health = sprite.health - proj.damage
                    if sprite.health <= 0 then
                        showMessage("Killed " .. (sprite.name or "Enemy") .. "!", 1.5)
                        Sprites.remove(id)
                    else
                        showMessage("Hit " .. (sprite.name or "Enemy") .. "! (" .. sprite.health .. " HP)", 1.0)
                        sprite.lastHitTime = love.timer.getTime()
                    end
                    table.remove(projectiles, i)
                    goto continue
                end
            end
        end

        proj.x = newX
        proj.y = newY
        proj.lifetime = proj.lifetime - dt
        if proj.lifetime <= 0 then
            table.remove(projectiles, i)
        end

        ::continue::
    end
end

-- =============================================================================
-- Stairs
-- =============================================================================

function checkStairs()
    if stairCooldown > 0 then return end

    local stair = map:getStairsAt(player.x, player.y)
    if stair then
        local newX, newY = map:changeFloor(stair.targetFloor, stair.targetX, stair.targetY)
        if newX and newY then
            player.x = newX
            player.y = newY

            local currentFloor = map.currentFloor or 1
            local zoneName = Depth.getZoneName(currentFloor)
            local depthStr = Depth.getDepthString(currentFloor)
            floorMessage = (zoneName or map:getFloorName()) .. " - " .. (depthStr or "")
            floorMessageTimer = 2.0
            stairCooldown = 3.0

            -- Update depth-based atmosphere
            local preset = Depth.getAtmospherePreset(currentFloor)
            if preset then
                Atmosphere.setEnvironment(preset)
            end
        end
    end
end

-- =============================================================================
-- Survivor rescue (proximity check)
-- =============================================================================

function checkSurvivorRescue()
    local RESCUE_RANGE = 1.5
    for id, sprite in pairs(Sprites.getAll()) do
        if sprite.isSurvivor and not sprite.rescued then
            local dx = sprite.x - player.x
            local dy = sprite.y - player.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < RESCUE_RANGE then
                sprite.rescued = true
                Sprites.remove(id)
                local crewId = Crew.addMember(nil, nil) -- random name and role
                local member = Crew.getMember(crewId)
                if member then
                    showMessage("Rescued " .. member.name .. " (" .. member.role .. ")", 3.0)
                end
            end
        end
    end
end

-- =============================================================================
-- love.draw
-- =============================================================================

function love.draw()
    -- Render to low-res canvas
    love.graphics.setCanvas(canvas)
    love.graphics.clear()

    local cam = Camera.getState()

    -- Raycast walls
    love.graphics.setColor(1, 1, 1)
    local zBuffer = Raycaster.render(cam, CONFIG)

    -- Draw sprites
    Sprites.render(cam, zBuffer, CONFIG.renderWidth, CONFIG.renderHeight)

    -- Draw projectiles
    renderProjectiles(cam, zBuffer)

    love.graphics.setCanvas()

    -- Draw canvas scaled to window
    local windowW, windowH = love.graphics.getDimensions()
    local scale   = math.min(windowW / CONFIG.renderWidth, windowH / CONFIG.renderHeight)
    local offsetX = (windowW - CONFIG.renderWidth * scale) / 2
    local offsetY = (windowH - CONFIG.renderHeight * scale) / 2

    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, offsetX, offsetY, 0, scale, scale)

    -- Atmosphere overlays
    Atmosphere.drawVignette(windowW, windowH)
    Atmosphere.drawDisturbance(windowW, windowH)

    -- First-person weapon/tool view
    if not Camera.isEnabled() then
        drawToolView(windowW, windowH)
    end

    -- HUD elements
    drawSurvivalHUD(windowW, windowH)
    drawDepthIndicator(windowW, windowH)

    -- Phase-specific HUD
    if gameState == GAME_STATES.SINKING then
        Sinking.drawHUD(windowW, windowH)
    end

    -- Mining progress bar (both phases)
    local slot = hotbar.slots[hotbar.selected]
    if slot and slot.type == "mining" then
        Mining.drawHUD(windowW, windowH)
    end

    -- Building ghost info (both phases)
    if Building.isInBuildMode() then
        Building.drawHUD(windowW, windowH, player.x, player.y, player.dirX, player.dirY, map, inventory)
    end

    -- Crafting progress (both phases)
    if Crafting.isCrafting() then
        Crafting.drawHUD(windowW, windowH)
    end

    -- Power status (survival only)
    if gameState == GAME_STATES.SURVIVAL then
        drawPowerStatus(windowW, windowH)
    end

    -- Hotbar
    drawHotbar(windowW, windowH)

    -- Minimap
    if CONFIG.showMinimap then
        drawMinimap(windowW, windowH)
    end

    -- FPS
    if CONFIG.showFPS then
        drawFPS()
    end

    -- Floating pickup messages
    drawPickupMessages(windowW, windowH)

    -- Floor/zone message
    if floorMessage then
        drawFloorMessage()
    end

    -- Door/interaction message
    if doorMessage then
        drawDoorMessage()
    end

    -- Interaction hints
    drawInteractionHint()

    -- Crosshair
    drawCrosshair(windowW, windowH)

    -- Mining node indicator (show resource when aiming at wall)
    drawMiningNodeIndicator(windowW, windowH)

    -- Inventory/crafting screen overlay
    if showInventory then
        drawInventoryScreen(windowW, windowH)
    end

    -- Tech tree screen overlay
    if showTechTree then
        drawTechTreeScreen(windowW, windowH)
    end

    -- Research progress bar (always visible when researching)
    if Tech.isResearching() and not showTechTree then
        drawResearchProgress(windowW, windowH)
    end

    -- Survival warnings overlay
    drawWarnings(windowW, windowH)

    -- Controls hint
    love.graphics.setColor(1, 1, 1, 0.5)
    local hint = "WASD:Swim | LClick:Mine/Attack | E:Door | B:Build | TAB:Inventory | T:Tech"
    love.graphics.print(hint, 10, windowH - 20)
end

-- =============================================================================
-- Render projectiles in 3D
-- =============================================================================

function renderProjectiles(cam, zBuffer)
    local posX, posY   = cam.x, cam.y
    local dirX, dirY   = cam.dirX, cam.dirY
    local planeX, planeY = cam.planeX, cam.planeY
    local hShift = cam.horizonShift or 0

    for _, proj in ipairs(projectiles) do
        local spriteX = proj.x - posX
        local spriteY = proj.y - posY

        local invDet     = 1.0 / (planeX * dirY - dirX * planeY)
        local transformX = invDet * (dirY * spriteX - dirX * spriteY)
        local transformY = invDet * (-planeY * spriteX + planeX * spriteY)

        if transformY > 0.1 then
            local screenX  = math.floor((CONFIG.renderWidth / 2) * (1 + transformX / transformY))
            local projSize = math.floor(CONFIG.renderHeight / transformY * 0.1)
            local screenY  = CONFIG.renderHeight / 2 + hShift

            if transformY < (zBuffer[screenX] or 1e30) then
                love.graphics.setColor(0.3, 0.7, 0.9) -- underwater blue spear
                love.graphics.rectangle("fill",
                    screenX - projSize / 2,
                    screenY - projSize / 2,
                    projSize,
                    projSize * 3
                )
            end
        end
    end
end

-- =============================================================================
-- HUD Drawing: Survival bars
-- =============================================================================

function drawSurvivalHUD(windowW, windowH)
    local x        = 10
    local y        = windowH - 95
    local barWidth = 160
    local barH     = 14

    -- Background panel
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", x - 5, y - 5, barWidth + 15, 80, 5, 5)

    -- Health bar
    local health    = Survival.getHealth()
    local maxHealth = 100
    love.graphics.setColor(0.3, 0.08, 0.08)
    love.graphics.rectangle("fill", x, y, barWidth, barH)
    love.graphics.setColor(0.8, 0.2, 0.2)
    love.graphics.rectangle("fill", x, y, barWidth * (health / maxHealth), barH)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("HP " .. math.floor(health), x + 4, y)

    -- O2 bar
    y = y + barH + 3
    local o2    = Survival.getO2()
    local maxO2 = 100
    love.graphics.setColor(0.08, 0.15, 0.3)
    love.graphics.rectangle("fill", x, y, barWidth, barH)
    love.graphics.setColor(0.2, 0.5, 0.9)
    love.graphics.rectangle("fill", x, y, barWidth * (o2 / maxO2), barH)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("O2 " .. math.floor(o2), x + 4, y)

    -- Hunger bar
    y = y + barH + 3
    local hunger    = Survival.getHunger()
    local maxHunger = 100
    love.graphics.setColor(0.2, 0.15, 0.05)
    love.graphics.rectangle("fill", x, y, barWidth, barH)
    love.graphics.setColor(0.7, 0.5, 0.2)
    love.graphics.rectangle("fill", x, y, barWidth * (hunger / maxHunger), barH)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Food " .. math.floor(hunger), x + 4, y)

    -- Pressure indicator
    y = y + barH + 3
    local pressure = Survival.getPressure()
    local pressureColor = pressure < 0.5 and {0.3, 0.9, 0.4} or
                          pressure < 0.8 and {0.9, 0.9, 0.3} or {0.9, 0.3, 0.3}
    love.graphics.setColor(pressureColor[1], pressureColor[2], pressureColor[3])
    love.graphics.print("Pressure: " .. math.floor(pressure * 100) .. "%", x, y)
end

-- =============================================================================
-- HUD Drawing: Depth indicator
-- =============================================================================

function drawDepthIndicator(windowW, windowH)
    local currentFloor = map.currentFloor or 1
    local depthStr  = Depth.getDepthString(currentFloor)
    local zoneName  = Depth.getZoneName(currentFloor)
    local zoneColor = Depth.getZoneColor(currentFloor)

    local x = windowW - 170
    local y = windowH - 60

    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", x - 5, y - 5, 170, 50, 5, 5)

    if zoneColor then
        love.graphics.setColor(zoneColor[1], zoneColor[2], zoneColor[3])
    else
        love.graphics.setColor(0.3, 0.6, 0.9)
    end
    love.graphics.print(zoneName or "Unknown", x, y)

    love.graphics.setColor(0.7, 0.8, 0.9)
    love.graphics.print(depthStr or "0m", x, y + 16)

    -- Crew count
    love.graphics.setColor(0.6, 0.8, 0.6)
    love.graphics.print("Crew: " .. Crew.getCount(), x, y + 32)
end

-- =============================================================================
-- HUD Drawing: Power status
-- =============================================================================

function drawPowerStatus(windowW, windowH)
    local net    = Power.getNetPower()
    local status = Power.getPowerStatus()

    local x = windowW - 170
    local y = windowH - 115

    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", x - 5, y - 5, 170, 50, 5, 5)

    local statusColor = {0.5, 0.5, 0.5}
    if status == "online" then
        statusColor = {0.3, 0.9, 0.4}
    elseif status == "brownout" then
        statusColor = {0.9, 0.7, 0.2}
    elseif status == "offline" then
        statusColor = {0.6, 0.3, 0.3}
    end

    love.graphics.setColor(statusColor[1], statusColor[2], statusColor[3])
    love.graphics.print("Power: " .. (status or "N/A"):upper(), x, y)

    love.graphics.setColor(0.7, 0.8, 0.7)
    local prod = Power.getTotalProduction()
    local cons = Power.getTotalConsumption()
    love.graphics.print(string.format("Gen: %dW  Use: %dW", prod, cons), x, y + 16)

    local netColor = net >= 0 and {0.3, 0.9, 0.4} or {0.9, 0.3, 0.3}
    love.graphics.setColor(netColor[1], netColor[2], netColor[3])
    love.graphics.print(string.format("Net: %+dW", net), x, y + 32)
end

-- =============================================================================
-- HUD Drawing: Crosshair
-- =============================================================================

function drawCrosshair(windowW, windowH)
    local cx = windowW / 2
    local cy = windowH / 2
    local size = 6

    love.graphics.setColor(0.3, 0.8, 1.0, 0.8)
    love.graphics.setLineWidth(1)
    love.graphics.line(cx - size, cy, cx + size, cy)
    love.graphics.line(cx, cy - size, cx, cy + size)
end

-- =============================================================================
-- HUD Drawing: Mining node indicator
-- =============================================================================

-- DDA ray cast to find what wall the player is looking at (for HUD indicator)
local function castLookRay(px, py, dirX, dirY, maxDist)
    if not map then return nil end

    local mapX = math.floor(px)
    local mapY = math.floor(py)

    local deltaDistX = (dirX == 0) and 1e30 or math.abs(1 / dirX)
    local deltaDistY = (dirY == 0) and 1e30 or math.abs(1 / dirY)

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

    for _ = 1, 20 do
        if sideDistX < sideDistY then
            sideDistX = sideDistX + deltaDistX
            mapX = mapX + stepX
        else
            sideDistY = sideDistY + deltaDistY
            mapY = mapY + stepY
        end

        local perpDist = math.min(sideDistX - deltaDistX, sideDistY - deltaDistY)
        if perpDist > maxDist then return nil end

        local tile = map:getTile(mapX, mapY)
        if tile and tile > 0 and tile ~= 10 and tile ~= 11 and tile ~= 12 then
            return mapX, mapY, tile, perpDist
        end
        if tile and (tile == 10 or tile == 11 or tile == 12) then
            return nil
        end
    end
    return nil
end

function drawMiningNodeIndicator(windowW, windowH)
    if not player or not map then return end
    if showInventory or showTechTree then return end

    local hitX, hitY, wallType, dist = castLookRay(
        player.x, player.y, player.dirX, player.dirY, 4.0)

    if not hitX or not wallType then return end

    -- Get resource info for this wall type
    local resourceId = Resources.getForWallType(wallType)
    if not resourceId then return end

    local resDef = Resources.get(resourceId)
    if not resDef then return end

    local cx = windowW / 2
    local cy = windowH / 2

    -- Resource name label below crosshair
    local name = DISPLAY_NAMES[resourceId] or resDef.name or resourceId
    local color = resDef.color or {0.7, 0.7, 0.7}

    -- Distance-based alpha (fade when far)
    local alpha = math.max(0.4, 1.0 - dist / 4.0)

    -- Background pill
    local font = love.graphics.getFont()
    local textW = font:getWidth(name)
    love.graphics.setColor(0, 0, 0, 0.6 * alpha)
    love.graphics.rectangle("fill", cx - textW / 2 - 8, cy + 14, textW + 16, 18, 4, 4)

    -- Colored dot
    love.graphics.setColor(color[1], color[2], color[3], alpha)
    love.graphics.circle("fill", cx - textW / 2 - 1, cy + 23, 4)

    -- Resource name
    love.graphics.setColor(color[1] * 0.7 + 0.3, color[2] * 0.7 + 0.3, color[3] * 0.7 + 0.3, alpha)
    love.graphics.print(name, cx - textW / 2 + 6, cy + 15)

    -- Mine time hint
    local mineTime = resDef.mineTime or 3.0
    local timeStr = string.format("%.1fs", mineTime)
    local timeW = font:getWidth(timeStr)
    love.graphics.setColor(0.6, 0.6, 0.6, alpha * 0.7)
    love.graphics.print(timeStr, cx + textW / 2 + 10, cy + 15)
end

-- =============================================================================
-- HUD Drawing: Warnings overlay
-- =============================================================================

function drawWarnings(windowW, windowH)
    local warnings = Survival.getWarnings()
    if not warnings or #warnings == 0 then return end

    local y = 100
    for _, warning in ipairs(warnings) do
        local alpha = 0.7 + math.sin(love.timer.getTime() * 4) * 0.3
        love.graphics.setColor(1, 0.3, 0.2, alpha)
        local font = love.graphics.getFont()
        local w = font:getWidth(warning)
        love.graphics.print(warning, (windowW - w) / 2, y)
        y = y + 20
    end
end

-- =============================================================================
-- HUD Drawing: Hotbar
-- =============================================================================

function drawHotbar(windowW, windowH)
    local slotSize   = 50
    local padding    = 5
    local totalWidth = #hotbar.slots * (slotSize + padding) - padding
    local startX     = (windowW - totalWidth) / 2
    local y          = windowH - slotSize - 100

    for i, slot in ipairs(hotbar.slots) do
        local x = startX + (i - 1) * (slotSize + padding)
        local isSelected = (i == hotbar.selected)

        if isSelected then
            love.graphics.setColor(0.1, 0.25, 0.4, 0.95)
            love.graphics.rectangle("fill", x - 3, y - 3, slotSize + 6, slotSize + 6, 5, 5)
            love.graphics.setColor(0.3, 0.7, 1.0, 1)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", x - 3, y - 3, slotSize + 6, slotSize + 6, 5, 5)
            love.graphics.setLineWidth(1)
        else
            love.graphics.setColor(0.1, 0.12, 0.18, 0.85)
            love.graphics.rectangle("fill", x, y, slotSize, slotSize, 5, 5)
            love.graphics.setColor(0.2, 0.3, 0.4, 0.8)
            love.graphics.rectangle("line", x, y, slotSize, slotSize, 5, 5)
        end

        -- Icon (colored shape)
        local iconX = x + slotSize / 2
        local iconY = y + slotSize / 2
        love.graphics.setColor(slot.color[1], slot.color[2], slot.color[3])

        if slot.type == "mining" then
            -- Mining laser icon
            love.graphics.rectangle("fill", iconX - 3, iconY - 15, 6, 30)
            love.graphics.circle("fill", iconX, iconY - 15, 5)
        elseif slot.type == "building" then
            -- Builder icon (wrench shape)
            love.graphics.rectangle("fill", iconX - 8, iconY - 2, 16, 4)
            love.graphics.rectangle("fill", iconX - 2, iconY - 15, 4, 30)
        elseif slot.type == "ranged" then
            -- Spear gun icon
            love.graphics.rectangle("fill", iconX - 2, iconY - 18, 4, 36)
            love.graphics.polygon("fill",
                iconX, iconY - 18,
                iconX - 5, iconY - 12,
                iconX + 5, iconY - 12
            )
            love.graphics.rectangle("fill", iconX - 10, iconY + 5, 20, 4)
        end

        -- Slot number
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.print(tostring(i), x + 3, y + 2)

        -- Ammo indicator
        if slot.ammo then
            love.graphics.setColor(1, 1, 0.5)
            love.graphics.print(slot.ammo, x + slotSize - 15, y + slotSize - 15)
        end
    end

    -- Selected item name
    local selectedSlot = hotbar.slots[hotbar.selected]
    if selectedSlot then
        love.graphics.setColor(0.7, 0.9, 1.0, 0.9)
        local font  = love.graphics.getFont()
        local nameW = font:getWidth(selectedSlot.name)
        love.graphics.print(selectedSlot.name, (windowW - nameW) / 2, y - 18)
    end
end

-- =============================================================================
-- HUD Drawing: Tool view (first-person)
-- =============================================================================

function drawToolView(windowW, windowH)
    local slot = hotbar.slots[hotbar.selected]
    if not slot then return end

    local centerX = windowW / 2
    local baseY   = windowH - 100

    local bobX = math.sin(love.timer.getTime() * 2) * 5
    local bobY = math.abs(math.sin(love.timer.getTime() * 4)) * 3

    local attackOffset = 0
    if attackAnimation > 0 then
        attackOffset = -attackAnimation * 20
    end

    if slot.type == "mining" then
        -- Mining laser
        local laserX = centerX + 70 + bobX
        local laserY = baseY + bobY

        -- Handle
        love.graphics.setColor(0.3, 0.3, 0.35)
        love.graphics.rectangle("fill", laserX, laserY + 30, 20, 60)

        -- Body
        love.graphics.setColor(0.15, 0.35, 0.45)
        love.graphics.rectangle("fill", laserX - 5, laserY - 20, 30, 55)

        -- Emitter
        love.graphics.setColor(0.2, 0.7, 0.9)
        love.graphics.rectangle("fill", laserX + 2, laserY - 40, 16, 25)

        -- Glow when mining
        if Mining.isActive() then
            local pulse = 0.5 + math.sin(love.timer.getTime() * 10) * 0.5
            love.graphics.setColor(0.3, 0.8, 1.0, pulse * 0.6)
            love.graphics.circle("fill", laserX + 10, laserY - 45, 12)
        end

    elseif slot.type == "building" then
        -- Builder tool
        local toolX = centerX + 60 + bobX
        local toolY = baseY + bobY

        -- Handle
        love.graphics.setColor(0.3, 0.4, 0.3)
        love.graphics.rectangle("fill", toolX + 5, toolY + 40, 15, 50)

        -- Head
        love.graphics.setColor(0.2, 0.6, 0.4)
        love.graphics.rectangle("fill", toolX - 10, toolY - 10, 45, 50)

        -- Screen
        love.graphics.setColor(0.1, 0.3, 0.2)
        love.graphics.rectangle("fill", toolX - 2, toolY, 30, 30)

        -- Screen glow
        if Building.isInBuildMode() then
            local pulse = 0.5 + math.sin(love.timer.getTime() * 3) * 0.5
            love.graphics.setColor(0.2, 0.9, 0.5, pulse * 0.7)
            love.graphics.rectangle("fill", toolX, toolY + 2, 26, 26)
        end

    elseif slot.type == "ranged" then
        -- Spear gun
        local gunX = centerX + 50 + bobX
        local gunY = baseY - 30 + bobY + attackOffset

        -- Stock
        love.graphics.setColor(0.4, 0.3, 0.25)
        love.graphics.polygon("fill",
            gunX + 20, gunY + 80,
            gunX + 45, gunY + 80,
            gunX + 55, gunY + 20,
            gunX + 25, gunY + 20
        )

        -- Barrel
        love.graphics.setColor(0.5, 0.5, 0.55)
        love.graphics.rectangle("fill", gunX + 15, gunY - 40, 10, 65)

        -- Spear loaded
        if slot.ammo and slot.ammo > 0 then
            love.graphics.setColor(0.6, 0.6, 0.65)
            love.graphics.rectangle("fill", gunX + 17, gunY - 60, 6, 25)
            love.graphics.setColor(0.7, 0.7, 0.8)
            love.graphics.polygon("fill",
                gunX + 20, gunY - 70,
                gunX + 15, gunY - 60,
                gunX + 25, gunY - 60
            )
        end

        -- Bands
        love.graphics.setColor(0.35, 0.3, 0.25)
        love.graphics.rectangle("fill", gunX, gunY + 10, 40, 6)
    end
end

-- =============================================================================
-- HUD Drawing: Minimap
-- =============================================================================

function drawMinimap(windowW, windowH)
    local mapData  = map:getData().data
    -- Dynamic scale: fit minimap into max 150px
    local maxSize  = 150
    local mapCols  = #mapData[1]
    local mapRows  = #mapData
    local mapScale = math.max(2, math.floor(maxSize / math.max(mapCols, mapRows)))
    local mapX     = windowW - (mapCols * mapScale) - 10
    local mapY     = 10

    -- Background
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", mapX - 5, mapY - 5,
        #mapData[1] * mapScale + 10, #mapData * mapScale + 25)

    local theme = Raycaster.getTheme()

    -- Map tiles
    for y = 1, #mapData do
        for x = 1, #mapData[y] do
            local tile = mapData[y][x]
            if tile > 0 then
                if tile == 10 then
                    love.graphics.setColor(0.4, 0.6, 0.8) -- Door
                elseif tile == 11 then
                    love.graphics.setColor(0.2, 0.8, 0.2) -- Stairs up
                elseif tile == 12 then
                    love.graphics.setColor(0.8, 0.2, 0.2) -- Stairs down
                elseif tile >= 20 then
                    love.graphics.setColor(0.2, 0.7, 0.5) -- Buildings
                elseif tile >= 1 and tile <= 5 then
                    -- Color by resource type for mining node visibility
                    local resId = Resources.getForWallType(tile)
                    local resDef = resId and Resources.get(resId)
                    if resDef and resDef.color then
                        local rc = resDef.color
                        love.graphics.setColor(rc[1], rc[2], rc[3])
                    elseif theme and theme.walls and theme.walls[tile] then
                        local c = theme.walls[tile]
                        love.graphics.setColor(c[1], c[2], c[3])
                    else
                        love.graphics.setColor(0.4, 0.4, 0.5)
                    end
                else
                    love.graphics.setColor(0.4, 0.4, 0.5)
                end
                love.graphics.rectangle("fill",
                    mapX + (x - 1) * mapScale,
                    mapY + (y - 1) * mapScale,
                    mapScale - 1, mapScale - 1)
            end
        end
    end

    -- Sprites on minimap
    for id, sprite in pairs(Sprites.getAll()) do
        if sprite.type == "enemy" then
            love.graphics.setColor(1, 0.3, 0.3)
        elseif sprite.isSurvivor then
            love.graphics.setColor(0.3, 1.0, 0.5)
        elseif sprite.type == "item" then
            love.graphics.setColor(1, 1, 0.5, 0.6)
        else
            love.graphics.setColor(0.3, 0.8, 1.0)
        end
        local sx = mapX + (sprite.x - 1) * mapScale
        local sy = mapY + (sprite.y - 1) * mapScale
        love.graphics.circle("fill", sx, sy, 2)
    end

    -- Player
    love.graphics.setColor(0, 1, 1)
    local px = mapX + (player.x - 1) * mapScale
    local py = mapY + (player.y - 1) * mapScale
    love.graphics.circle("fill", px, py, 3)
    love.graphics.setColor(1, 1, 0)
    love.graphics.line(px, py, px + player.dirX * 8, py + player.dirY * 8)

    -- Zone label
    local currentFloor = map.currentFloor or 1
    local zoneName = Depth.getZoneName(currentFloor) or map:getFloorName()
    love.graphics.setColor(0.7, 0.8, 0.9, 0.8)
    love.graphics.print(zoneName, mapX, mapY + #mapData * mapScale + 5)
end

-- =============================================================================
-- HUD Drawing: FPS
-- =============================================================================

function drawFPS()
    local x, y = 10, 10

    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", x - 5, y - 5, 140, 50, 5, 5)

    local fpsColor = fpsCounter.current >= 55 and {0.3, 1, 0.3}
                  or fpsCounter.current >= 30 and {1, 1, 0.3}
                  or {1, 0.3, 0.3}

    love.graphics.setColor(fpsColor[1], fpsColor[2], fpsColor[3])
    love.graphics.print("FPS: " .. fpsCounter.current, x, y)

    local avgFPS = 0
    if #fpsCounter.history > 0 then
        for _, fps in ipairs(fpsCounter.history) do avgFPS = avgFPS + fps end
        avgFPS = math.floor(avgFPS / #fpsCounter.history)
    end
    love.graphics.setColor(0.8, 0.8, 0.8)
    love.graphics.print("Avg: " .. avgFPS, x, y + 16)

    love.graphics.setColor(0.6, 0.6, 0.6)
    love.graphics.print(CONFIG.renderWidth .. "x" .. CONFIG.renderHeight, x, y + 32)
end

-- =============================================================================
-- HUD Drawing: Pickup messages
-- =============================================================================

function drawPickupMessages(windowW, windowH)
    local centerX = windowW / 2
    local baseY   = windowH / 2 - 50

    for i, msg in ipairs(pickupMessages) do
        local alpha = math.min(1, msg.timer / (PICKUP_MESSAGE_DURATION * 0.3))
        local y     = baseY - msg.y - (i - 1) * 25

        love.graphics.setColor(msg.color[1] * 0.3, msg.color[2] * 0.3, msg.color[3] * 0.3, alpha * 0.5)
        local font  = love.graphics.getFont()
        local textW = font:getWidth(msg.text)
        love.graphics.rectangle("fill", centerX - textW / 2 - 10, y - 2, textW + 20, 20, 5, 5)

        love.graphics.setColor(msg.color[1], msg.color[2], msg.color[3], alpha)
        love.graphics.print(msg.text, centerX - textW / 2, y)
    end
end

-- =============================================================================
-- HUD Drawing: Floor message
-- =============================================================================

function drawFloorMessage()
    local windowW = love.graphics.getWidth()
    local alpha   = math.min(1, floorMessageTimer)

    love.graphics.setColor(0, 0, 0, alpha * 0.7)
    love.graphics.rectangle("fill", 0, 80, windowW, 40)

    love.graphics.setColor(0.7, 0.9, 1.0, alpha)
    local font  = love.graphics.getFont()
    local textW = font:getWidth(floorMessage)
    love.graphics.print(floorMessage, (windowW - textW) / 2, 90)
end

-- =============================================================================
-- HUD Drawing: Door message
-- =============================================================================

function drawDoorMessage()
    local windowW = love.graphics.getWidth()
    local windowH = love.graphics.getHeight()
    local alpha   = math.min(1, doorMessageTimer)

    love.graphics.setColor(1, 1, 1, alpha)
    local font  = love.graphics.getFont()
    local textW = font:getWidth(doorMessage)
    love.graphics.print(doorMessage, (windowW - textW) / 2, windowH / 2 + 50)
end

-- =============================================================================
-- HUD Drawing: Interaction hint
-- =============================================================================

function drawInteractionHint()
    local windowW = love.graphics.getWidth()
    local windowH = love.graphics.getHeight()

    -- Door proximity
    for id, door in pairs(Doors.getAll()) do
        local dx   = (door.x + 0.5) - player.x
        local dy   = (door.y + 0.5) - player.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < 1.5 then
            love.graphics.setColor(0.5, 0.8, 1.0, 0.9)
            local hint  = "[E] Open Door"
            local font  = love.graphics.getFont()
            local textW = font:getWidth(hint)
            love.graphics.print(hint, (windowW - textW) / 2, windowH / 2 + 80)
            break
        end
    end

    -- Stair proximity
    local stair = map:getStairsAt(player.x, player.y)
    if stair then
        local color = stair.dir == "up" and {0.5, 1, 0.5} or {1, 0.5, 0.5}
        love.graphics.setColor(color[1], color[2], color[3], 0.9)
        local hint  = stair.dir == "up" and "Ascending..." or "Descending..."
        local font  = love.graphics.getFont()
        local textW = font:getWidth(hint)
        love.graphics.print(hint, (windowW - textW) / 2, windowH / 2 + 100)
    end
end

-- =============================================================================
-- HUD Drawing: Inventory & Crafting screen
-- =============================================================================

function drawInventoryScreen(windowW, windowH)
    -- Dark overlay
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, windowW, windowH)

    local panelW = 500
    local panelH = 420
    local px     = (windowW - panelW) / 2
    local py     = (windowH - panelH) / 2

    -- Panel background
    love.graphics.setColor(0.08, 0.12, 0.18, 0.95)
    love.graphics.rectangle("fill", px, py, panelW, panelH, 10, 10)
    love.graphics.setColor(0.2, 0.4, 0.6)
    love.graphics.rectangle("line", px, py, panelW, panelH, 10, 10)

    -- Title
    love.graphics.setColor(0.5, 0.8, 1.0)
    love.graphics.print("INVENTORY & CRAFTING", px + panelW / 2 - 80, py + 10)

    local col1X = px + 20
    local col2X = px + panelW / 2 + 10
    local rowY  = py + 40

    -- === Left column: Resources ===
    love.graphics.setColor(0.7, 0.9, 1.0)
    love.graphics.print("-- Resources --", col1X, rowY)
    rowY = rowY + 20

    for _, resId in ipairs(RESOURCE_ORDER) do
        local def   = Resources.get(resId)
        local color = def and def.color or {0.7, 0.7, 0.7}
        love.graphics.setColor(color[1], color[2], color[3])
        love.graphics.print(DISPLAY_NAMES[resId] or resId, col1X, rowY)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(tostring(inventory[resId] or 0), col1X + 120, rowY)
        rowY = rowY + 16
    end

    rowY = rowY + 8
    love.graphics.setColor(0.7, 0.9, 1.0)
    love.graphics.print("-- Materials --", col1X, rowY)
    rowY = rowY + 20

    for _, matId in ipairs(MATERIAL_ORDER) do
        local def   = Resources.get(matId)
        local color = def and def.color or {0.6, 0.6, 0.6}
        love.graphics.setColor(color[1], color[2], color[3])
        love.graphics.print(DISPLAY_NAMES[matId] or matId, col1X, rowY)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(tostring(inventory[matId] or 0), col1X + 120, rowY)
        rowY = rowY + 16
    end

    rowY = rowY + 8
    love.graphics.setColor(0.7, 0.9, 1.0)
    love.graphics.print("-- Equipment --", col1X, rowY)
    rowY = rowY + 20

    for _, eqId in ipairs(EQUIPMENT_ORDER) do
        love.graphics.setColor(0.8, 0.8, 0.9)
        love.graphics.print(DISPLAY_NAMES[eqId] or eqId, col1X, rowY)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(tostring(inventory[eqId] or 0), col1X + 120, rowY)
        rowY = rowY + 16
    end

    rowY = rowY + 8
    love.graphics.setColor(0.7, 0.9, 1.0)
    love.graphics.print("-- Consumables --", col1X, rowY)
    rowY = rowY + 20

    for _, conId in ipairs(CONSUMABLE_ORDER) do
        love.graphics.setColor(0.8, 0.7, 0.6)
        love.graphics.print(DISPLAY_NAMES[conId] or conId, col1X, rowY)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(tostring(inventory[conId] or 0), col1X + 120, rowY)
        rowY = rowY + 16
    end

    -- === Right column: Crafting recipes ===
    local craftY = py + 40
    love.graphics.setColor(0.5, 1.0, 0.7)
    love.graphics.print("-- Crafting --", col2X, craftY)
    craftY = craftY + 20

    local recipes = Crafting.getAvailableRecipes(inventory, {})
    if recipes and #recipes > 0 then
        for i, recipe in ipairs(recipes) do
            if i > 12 then break end -- limit display

            local canCraft = Crafting.canCraft(recipe.id, inventory, {})
            if canCraft then
                love.graphics.setColor(0.3, 0.9, 0.5)
            else
                love.graphics.setColor(0.5, 0.5, 0.5)
            end
            love.graphics.print(recipe.name or recipe.id, col2X, craftY)
            craftY = craftY + 14

            -- Show cost
            if recipe.inputs then
                for resId, amount in pairs(recipe.inputs) do
                    local have   = inventory[resId] or 0
                    local enough = have >= amount
                    love.graphics.setColor(enough and 0.6 or 0.8, enough and 0.8 or 0.3, enough and 0.6 or 0.3, 0.8)
                    love.graphics.print("  " .. (DISPLAY_NAMES[resId] or resId) .. " " .. have .. "/" .. amount, col2X, craftY)
                    craftY = craftY + 12
                end
            end
            craftY = craftY + 4
        end
    else
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.print("No recipes available", col2X, craftY)
    end

    -- Crafting progress
    if Crafting.isCrafting() then
        local prog = Crafting.getCraftProgress()
        local recipe = Crafting.getCraftingRecipe()
        love.graphics.setColor(0.2, 0.5, 0.7)
        love.graphics.rectangle("fill", col2X, py + panelH - 50, 200, 16)
        love.graphics.setColor(0.3, 0.8, 1.0)
        love.graphics.rectangle("fill", col2X, py + panelH - 50, 200 * prog, 16)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Crafting: " .. (recipe and recipe.name or "..."), col2X, py + panelH - 50)
    end

    -- Close hint
    love.graphics.setColor(0.5, 0.6, 0.7)
    love.graphics.print("TAB: Close | Number keys: Craft recipe | F1-F3: Use consumable", px + 20, py + panelH - 25)
end

-- =============================================================================
-- Tech tree helpers
-- =============================================================================

--- Get an ordered list of techs that can be researched right now.
function getResearchableTechList()
    local list = {}
    for _, branchId in ipairs(Tech.getBranches()) do
        for _, techId in ipairs(Tech.getTechsInBranch(branchId)) do
            if not Tech.isResearched(techId) then
                local canRes = Tech.canResearch(techId, inventory)
                if canRes then
                    list[#list + 1] = techId
                end
            end
        end
    end
    return list
end

-- =============================================================================
-- HUD Drawing: Tech tree screen
-- =============================================================================

function drawTechTreeScreen(windowW, windowH)
    -- Dark overlay
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", 0, 0, windowW, windowH)

    local panelW = 620
    local panelH = 500
    local px = (windowW - panelW) / 2
    local py = (windowH - panelH) / 2

    -- Panel background
    love.graphics.setColor(0.06, 0.08, 0.14, 0.95)
    love.graphics.rectangle("fill", px, py, panelW, panelH, 10, 10)
    love.graphics.setColor(0.3, 0.5, 0.7)
    love.graphics.rectangle("line", px, py, panelW, panelH, 10, 10)

    -- Title
    love.graphics.setColor(0.6, 0.85, 1.0)
    love.graphics.print("RESEARCH & TECHNOLOGY", px + panelW / 2 - 90, py + 10)

    -- Research progress bar (if researching)
    if Tech.isResearching() then
        local techId = Tech.getCurrentResearch()
        local tech = Tech.getTech(techId)
        local prog = Tech.getResearchProgress()
        local remaining = Tech.getResearchTimeRemaining()

        love.graphics.setColor(0.15, 0.2, 0.3)
        love.graphics.rectangle("fill", px + 20, py + 30, panelW - 40, 20, 3, 3)
        love.graphics.setColor(0.2, 0.6, 0.9)
        love.graphics.rectangle("fill", px + 20, py + 30, (panelW - 40) * prog, 20, 3, 3)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(string.format("Researching: %s  %.0f%%  (%.0fs left) [C=Cancel]",
            tech and tech.name or techId, prog * 100, remaining), px + 25, py + 32)
    end

    local startY = py + 60

    -- Draw each branch
    local branchX = px + 15
    local branchW = (panelW - 30) / 5 -- 5 branches side by side
    local researchableList = getResearchableTechList()

    -- Build lookup for numbering researchable techs
    local researchableNum = {}
    for i, tid in ipairs(researchableList) do
        if i <= 9 then researchableNum[tid] = i end
    end

    for bIdx, branchId in ipairs(Tech.getBranches()) do
        local bx = branchX + (bIdx - 1) * branchW
        local by = startY

        -- Branch header
        local bColor = Tech.getBranchColor(branchId)
        love.graphics.setColor(bColor[1], bColor[2], bColor[3])
        love.graphics.print(Tech.getBranchName(branchId), bx, by)
        by = by + 18

        -- Techs in this branch
        for _, techId in ipairs(Tech.getTechsInBranch(branchId)) do
            local tech = Tech.getTech(techId)
            if not tech then goto continue_tech end

            local isResearched = Tech.isResearched(techId)
            local canRes = Tech.canResearch(techId, inventory)
            local isActive = Tech.getCurrentResearch() == techId

            -- Background highlight
            if isActive then
                love.graphics.setColor(0.15, 0.25, 0.4, 0.6)
                love.graphics.rectangle("fill", bx - 2, by - 1, branchW - 5, 14, 2, 2)
            end

            -- Color based on state
            if isResearched then
                love.graphics.setColor(0.3, 0.9, 0.4)
            elseif isActive then
                love.graphics.setColor(0.4, 0.7, 1.0)
            elseif canRes then
                love.graphics.setColor(0.9, 0.9, 0.5)
            else
                love.graphics.setColor(0.35, 0.35, 0.4)
            end

            -- Tier indicator + name
            local label = "T" .. tech.tier .. " "
            if isResearched then
                label = label .. "[OK] "
            elseif researchableNum[techId] then
                label = label .. "[" .. researchableNum[techId] .. "] "
            else
                label = label .. "    "
            end

            -- Truncate name to fit column
            local name = tech.name or techId
            if #name > 14 then name = name:sub(1, 13) .. "." end
            label = label .. name

            love.graphics.print(label, bx, by)
            by = by + 14

            -- Show cost for available techs (compact)
            if canRes and not isResearched then
                for resId, amount in pairs(tech.cost) do
                    local have = inventory[resId] or 0
                    local enough = have >= amount
                    love.graphics.setColor(enough and 0.5 or 0.7, enough and 0.7 or 0.3, enough and 0.5 or 0.3, 0.7)
                    local shortName = (DISPLAY_NAMES[resId] or resId):sub(1, 8)
                    love.graphics.print("  " .. shortName .. " " .. have .. "/" .. amount, bx, by)
                    by = by + 11
                end
                by = by + 2
            end

            ::continue_tech::
        end
    end

    -- Stats
    love.graphics.setColor(0.5, 0.7, 0.9)
    love.graphics.print(string.format("Researched: %d / %d", Tech.getResearchedCount(), Tech.getTotalTechCount()),
        px + 20, py + panelH - 45)

    -- Controls hint
    love.graphics.setColor(0.5, 0.6, 0.7)
    love.graphics.print("T: Close | Number keys: Start research | C: Cancel research", px + 20, py + panelH - 25)
end

-- =============================================================================
-- HUD Drawing: Research progress (small bar when not in tech screen)
-- =============================================================================

function drawResearchProgress(windowW, windowH)
    local techId = Tech.getCurrentResearch()
    local tech = Tech.getTech(techId)
    local prog = Tech.getResearchProgress()

    local barW = 180
    local barH = 12
    local x = windowW / 2 - barW / 2
    local y = 10

    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", x - 5, y - 5, barW + 10, barH + 22, 4, 4)

    love.graphics.setColor(0.15, 0.2, 0.3)
    love.graphics.rectangle("fill", x, y, barW, barH, 2, 2)
    love.graphics.setColor(0.2, 0.6, 0.9)
    love.graphics.rectangle("fill", x, y, barW * prog, barH, 2, 2)

    love.graphics.setColor(0.7, 0.85, 1.0)
    local name = tech and tech.name or techId
    if #name > 20 then name = name:sub(1, 19) .. "." end
    love.graphics.print(name .. " " .. math.floor(prog * 100) .. "%", x + 2, y + barH + 2)
end

-- =============================================================================
-- Input: keypressed
-- =============================================================================

function love.keypressed(key)
    -- Escape: close menus or quit
    if key == "escape" then
        if showTechTree then
            showTechTree = false
        elseif showInventory then
            showInventory = false
        elseif Building.isInBuildMode() then
            Building.exitBuildMode()
            showMessage("Build mode OFF", 1.0)
        else
            love.event.quit()
        end
        return
    end

    -- Death restart
    if not Survival.isAlive() then
        if key == "return" or key == "kpenter" then
            startSinkingPhase()
        end
        return
    end

    -- Skip sinking phase
    if gameState == GAME_STATES.SINKING and (key == "return" or key == "kpenter") then
        Sinking.skip()
        startSurvivalPhase()
        return
    end

    -- Tab: toggle inventory
    if key == "tab" then
        showInventory = not showInventory
        showTechTree = false
        return
    end

    -- T: toggle tech tree
    if key == "t" then
        showTechTree = not showTechTree
        showInventory = false
        return
    end

    -- Crafting from inventory screen (number keys)
    if showInventory then
        local recipes = Crafting.getAvailableRecipes(inventory, {})
        local num = tonumber(key)
        if num and num >= 1 and num <= 9 and recipes and recipes[num] then
            local recipe = recipes[num]
            if not Crafting.isCrafting() and Crafting.canCraft(recipe.id, inventory, {}) then
                Crafting.startCraft(recipe.id, inventory)
                showMessage("Crafting " .. (recipe.name or recipe.id) .. "...", 1.5)
            end
        end
        -- Consumable shortcuts
        if key == "f1" then useConsumable("ration_pack") end
        if key == "f2" then useConsumable("med_pack") end
        if key == "f3" then useConsumable("o2_canister") end
        return
    end

    -- Tech tree research (number keys start research, C cancels)
    if showTechTree then
        local num = tonumber(key)
        if num and num >= 1 and num <= 9 then
            -- Get visible techs list and try to start research on the nth one
            local availableTechs = getResearchableTechList()
            if availableTechs[num] then
                local techId = availableTechs[num]
                local started = Tech.startResearch(techId, inventory)
                if started then
                    local tech = Tech.getTech(techId)
                    showMessage("Researching: " .. (tech and tech.name or techId), 2.0)
                else
                    local _, reason = Tech.canResearch(techId, inventory)
                    showMessage(reason or "Cannot research", 1.5)
                end
            end
        end
        if key == "c" and Tech.isResearching() then
            Tech.cancelResearch()
            showMessage("Research cancelled (resources lost)", 2.0)
        end
        return
    end

    -- Build mode toggle (works in both phases)
    if key == "b" then
        if Building.isInBuildMode() then
            Building.exitBuildMode()
            showMessage("Build mode OFF", 1.0)
        else
            Building.enterBuildMode()
            hotbar.selected = 2 -- auto-select builder
            showMessage("Build mode ON - 1-9 select, Q/R cycle", 2.0)
        end
        return
    end

    -- Door interaction
    if key == "e" then
        local success, message = Doors.interact(player.x, player.y, player.dirX, player.dirY)
        if message then showMessage(message, 1.5) end
        return
    end

    -- Hotbar / building selection via number keys
    if Building.isInBuildMode() then
        -- In build mode: number keys select building type (1-9, 0=10)
        local numKey = tonumber(key)
        if numKey then
            local idx = (numKey == 0) and 10 or numKey
            if Building.selectByIndex(idx) then
                local bDef = Building.getSelectedType()
                if bDef then showMessage(bDef.name, 0.8) end
            end
        end
    else
        -- Normal mode: hotbar selection
        if key == "1" then hotbar.selected = 1 end
        if key == "2" then hotbar.selected = 2 end
        if key == "3" then hotbar.selected = 3 end
    end

    -- Cycle hotbar / building type
    if key == "q" then
        if Building.isInBuildMode() then
            Building.cycleType(-1)
        else
            hotbar.selected = hotbar.selected - 1
            if hotbar.selected < 1 then hotbar.selected = #hotbar.slots end
        end
    end
    if key == "r" then
        if Building.isInBuildMode() then
            Building.cycleType(1)
        else
            hotbar.selected = hotbar.selected + 1
            if hotbar.selected > #hotbar.slots then hotbar.selected = 1 end
        end
    end

    -- Minimap / FPS toggle
    if key == "m" then CONFIG.showMinimap = not CONFIG.showMinimap end
    if key == "f" then CONFIG.showFPS = not CONFIG.showFPS end

    -- Toggle habitat atmosphere (for testing)
    if key == "h" then
        local established = Atmosphere.toggleBase()
        showMessage(established and "Habitat systems ONLINE" or "Habitat systems OFFLINE", 2.0)
    end

    -- World generation controls
    if key == "g" then
        useProceduralGen = not useProceduralGen
        showMessage(useProceduralGen and "Procedural: ON" or "Procedural: OFF", 2.0)
    end
    if key == "p" and useProceduralGen then
        startSurvivalPhase()
    end

    -- Consumable hotkeys (outside inventory too)
    if key == "f1" then useConsumable("ration_pack") end
    if key == "f2" then useConsumable("med_pack") end
    if key == "f3" then useConsumable("o2_canister") end
end

-- =============================================================================
-- Input: mousepressed
-- =============================================================================

function love.mousepressed(x, y, button)
    if not Survival.isAlive() then return end

    if button == 1 then -- Left click
        local slot = hotbar.slots[hotbar.selected]
        if not slot then return end

        if slot.type == "mining" then
            Mining.startMining()
        elseif slot.type == "building" and Building.isInBuildMode() then
            local tx, ty = Building.getTargetTile(
                player.x, player.y, player.dirX, player.dirY, map, false)
            if tx and ty then
                local placed = Building.place(tx, ty, map, inventory)
                if placed then
                    showMessage("Building placed!", 1.0)
                    -- Sync with power grid
                    local bDef = Building.getBuildingAt(tx, ty, map)
                    if bDef then
                        Power.addBuilding(tx, ty, bDef)
                    end
                else
                    showMessage("Cannot place here!", 1.0)
                end
            end
        elseif slot.type == "ranged" then
            useHotbarItem()
        end
    elseif button == 2 then -- Right click
        -- Remove building in build mode
        if Building.isInBuildMode() then
            local tx, ty = Building.getTargetTile(
                player.x, player.y, player.dirX, player.dirY, map, true)
            if tx and ty then
                local removed = Building.remove(tx, ty, map, inventory)
                if removed then
                    Power.removeBuilding(tx, ty)
                    showMessage("Building removed (50% refund)", 1.5)
                end
            end
        end
    end
end

-- =============================================================================
-- Input: mousereleased
-- =============================================================================

function love.mousereleased(x, y, button)
    if button == 1 then
        Mining.stopMining()
    end
end

-- =============================================================================
-- Input: wheelmoved
-- =============================================================================

function love.wheelmoved(x, y)
    if Camera.isEnabled() then
        Camera.zoom(y)
        return
    end

    if Building.isInBuildMode() then
        Building.cycleType(y > 0 and -1 or 1)
    else
        if y > 0 then
            hotbar.selected = hotbar.selected - 1
            if hotbar.selected < 1 then hotbar.selected = #hotbar.slots end
        elseif y < 0 then
            hotbar.selected = hotbar.selected + 1
            if hotbar.selected > #hotbar.slots then hotbar.selected = 1 end
        end
    end
end

-- =============================================================================
-- Input: mousemoved
-- =============================================================================

function love.mousemoved(x, y, dx, dy)
    Player.mouseLook(player, dx, dy)
end

-- =============================================================================
-- Window resize
-- =============================================================================

function love.resize(w, h)
    -- Scaling handled in draw
end
