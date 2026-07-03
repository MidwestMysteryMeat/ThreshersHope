--[[
    Procedural World Generation for Raycaster
    Adapted from main game's worldgen.lua

    Generates dungeons, towns, caves, and other 3D environments
    Uses biome system to determine wall types, layouts, and themes
]]

local WorldGen = {}

-- Reference to modules
local Doors = require("doors")

-- ============================================================================
--                         BIOME DEFINITIONS
-- ============================================================================

WorldGen.BIOMES = {
    dungeon = {
        id = "dungeon",
        name = "Stone Dungeon",
        theme = "dungeon",
        wallTypes = {1, 2, 3, 4, 5},  -- Mix of wall textures
        primaryWall = 1,  -- Dark stone
        secondaryWall = 2,  -- Mossy stone
        roomMinSize = 4,
        roomMaxSize = 9,
        corridorWidth = 1,
        roomCount = {min = 4, max = 8},
        hasCeiling = true,
    },

    cave = {
        id = "cave",
        name = "Natural Cave",
        theme = "dungeon",
        wallTypes = {1, 2, 4},
        primaryWall = 2,  -- Mossy/wet walls
        secondaryWall = 1,
        roomMinSize = 5,
        roomMaxSize = 12,  -- Irregular large caves
        corridorWidth = 2,  -- Wider passages
        roomCount = {min = 3, max = 6},
        hasCeiling = false,  -- Open caverns
    },

    crypt = {
        id = "crypt",
        name = "Ancient Crypt",
        theme = "dungeon",
        wallTypes = {4, 5},
        primaryWall = 4,  -- Blue-gray stone
        secondaryWall = 5,  -- Dark iron
        roomMinSize = 3,
        roomMaxSize = 7,
        corridorWidth = 1,
        roomCount = {min = 6, max = 10},  -- Many small chambers
        hasCeiling = true,
    },

    mine = {
        id = "mine",
        name = "Abandoned Mine",
        theme = "dungeon",
        wallTypes = {1, 3, 4},
        primaryWall = 3,  -- Brown brick (supports)
        secondaryWall = 1,
        roomMinSize = 3,
        roomMaxSize = 6,
        corridorWidth = 1,
        roomCount = {min = 8, max = 12},  -- Many tunnels
        hasCeiling = true,
    },

    town = {
        id = "town",
        name = "Town Streets",
        theme = "town",
        wallTypes = {1, 2, 3, 4, 5},
        primaryWall = 1,  -- Plaster
        secondaryWall = 2,  -- Wood
        roomMinSize = 4,
        roomMaxSize = 8,
        corridorWidth = 3,  -- Wide streets
        roomCount = {min = 5, max = 9},  -- Buildings
        hasCeiling = false,  -- Outdoor
    },

    desert_ruins = {
        id = "desert_ruins",
        name = "Desert Ruins",
        theme = "desert",
        wallTypes = {1, 2, 3, 4, 5},
        primaryWall = 1,  -- Sandstone
        secondaryWall = 3,  -- Pale limestone
        roomMinSize = 5,
        roomMaxSize = 10,
        corridorWidth = 2,
        roomCount = {min = 4, max = 7},
        hasCeiling = false,  -- Ruined/open
    },

    forest = {
        id = "forest",
        name = "Deep Forest",
        theme = "forest",
        wallTypes = {1, 2, 3, 4, 5},
        primaryWall = 1,  -- Living trees
        secondaryWall = 3,  -- Moss-covered
        roomMinSize = 4,
        roomMaxSize = 8,
        corridorWidth = 2,
        roomCount = {min = 3, max = 6},
        hasCeiling = false,  -- Forest canopy
    },

    void_sanctum = {
        id = "void_sanctum",
        name = "Void Sanctum",
        theme = "void",
        wallTypes = {1, 2, 3, 4, 5},
        primaryWall = 1,  -- Dark purple stone
        secondaryWall = 5,  -- Ethereal purple
        roomMinSize = 6,
        roomMaxSize = 10,
        corridorWidth = 2,
        roomCount = {min = 3, max = 5},
        hasCeiling = true,
    },

    castle = {
        id = "castle",
        name = "Castle Keep",
        theme = "castle",
        wallTypes = {1, 2, 3, 4, 5},
        primaryWall = 1,  -- Gray stone blocks
        secondaryWall = 3,  -- Warm stone
        roomMinSize = 5,
        roomMaxSize = 12,  -- Large halls
        corridorWidth = 2,
        roomCount = {min = 4, max = 7},
        hasCeiling = true,
    },

    -- =============================================
    -- UNDERWATER BIOMES (survival phase)
    -- =============================================

    coral_reef = {
        id = "coral_reef",
        name = "Coral Reef",
        theme = "underwater",
        wallTypes = {1, 2, 3},
        primaryWall = 3,  -- Biomass (coral/organic)
        secondaryWall = 2,  -- Crystal formations
        roomMinSize = 5,
        roomMaxSize = 11,  -- Open reef chambers
        corridorWidth = 2,  -- Wide swim-throughs
        roomCount = {min = 5, max = 9},
        hasCeiling = false,  -- Open water above
    },

    kelp_forest = {
        id = "kelp_forest",
        name = "Kelp Forest",
        theme = "underwater",
        wallTypes = {2, 3, 4},
        primaryWall = 3,  -- Biomass (kelp/organic)
        secondaryWall = 4,  -- Electronics (tech debris)
        roomMinSize = 4,
        roomMaxSize = 8,
        corridorWidth = 1,  -- Dense kelp narrows
        roomCount = {min = 6, max = 10},
        hasCeiling = false,
    },

    volcanic_vent = {
        id = "volcanic_vent",
        name = "Volcanic Vent",
        theme = "underwater",
        wallTypes = {1, 4, 5},
        primaryWall = 5,  -- Titanium ore
        secondaryWall = 1,  -- Scrap metal (cooled lava)
        roomMinSize = 3,
        roomMaxSize = 7,
        corridorWidth = 1,
        roomCount = {min = 4, max = 7},
        hasCeiling = true,  -- Cave-like overhangs
    },

    abyssal_trench = {
        id = "abyssal_trench",
        name = "Abyssal Trench",
        theme = "underwater",
        wallTypes = {4, 5},
        primaryWall = 5,  -- Titanium (pressure-forged)
        secondaryWall = 4,  -- Electronics (precursor debris)
        roomMinSize = 4,
        roomMaxSize = 9,
        corridorWidth = 1,
        roomCount = {min = 3, max = 5},  -- Sparse, dangerous
        hasCeiling = true,  -- Deep cave structures
    },

    sunken_ruins = {
        id = "sunken_ruins",
        name = "Sunken Ruins",
        theme = "underwater",
        wallTypes = {1, 2, 4, 5},
        primaryWall = 1,  -- Scrap metal (ancient structures)
        secondaryWall = 2,  -- Crystal (overgrown minerals)
        roomMinSize = 5,
        roomMaxSize = 10,
        corridorWidth = 2,
        roomCount = {min = 4, max = 8},
        hasCeiling = true,
    },
}

-- ============================================================================
--                         PROCEDURAL GENERATION
-- ============================================================================

-- BSP (Binary Space Partitioning) Room Generation
function WorldGen.generateBSPDungeon(width, height, biomeId, floorCount, seed)
    local biome = WorldGen.BIOMES[biomeId] or WorldGen.BIOMES.dungeon

    -- Set random seed for reproducible generation
    if seed then
        math.randomseed(seed)
    end

    local map = {
        theme = biome.theme,
        spawnX = 2.5,
        spawnY = 2.5,
        spawnFloor = 1,
        currentFloor = 1,
        floors = {},
        biome = biome,
    }

    -- Generate each floor
    for floor = 1, floorCount do
        local floorData = WorldGen.generateFloor(width, height, biome, floor, floorCount)
        table.insert(map.floors, floorData)
    end

    -- Link stairs between floors
    for floor = 1, floorCount - 1 do
        local currentFloor = map.floors[floor]
        local nextFloor = map.floors[floor + 1]

        -- Find down stairs on current floor
        for _, stair in ipairs(currentFloor.stairs) do
            if stair.dir == "down" then
                -- Find up stairs on next floor
                for _, nextStair in ipairs(nextFloor.stairs) do
                    if nextStair.dir == "up" then
                        -- Link them
                        stair.targetX = nextStair.x + 0.5
                        stair.targetY = nextStair.y + 0.5
                        nextStair.targetX = stair.x + 0.5
                        nextStair.targetY = stair.y + 0.5
                        break
                    end
                end
                break
            end
        end
    end

    -- Find spawn point on first floor (first room)
    if map.floors[1] and map.floors[1].rooms and #map.floors[1].rooms > 0 then
        local firstRoom = map.floors[1].rooms[1]
        map.spawnX = firstRoom.centerX + 0.5
        map.spawnY = firstRoom.centerY + 0.5
    end

    return map
end

-- Generate a single floor using BSP
function WorldGen.generateFloor(width, height, biome, floorNum, totalFloors)
    -- Initialize empty grid
    local grid = {}
    for y = 1, height do
        grid[y] = {}
        for x = 1, width do
            grid[y][x] = biome.primaryWall  -- Fill with walls
        end
    end

    -- Generate rooms using BSP
    local rooms = WorldGen.generateRoomsBSP(width, height, biome)

    -- Carve rooms
    for _, room in ipairs(rooms) do
        WorldGen.carveRoom(grid, room, biome)
    end

    -- Connect rooms with corridors
    WorldGen.connectRooms(grid, rooms, biome)

    -- Add doors at room entrances
    local doorPositions = WorldGen.placeDoors(grid, rooms)

    -- Add stairs
    local stairs = {}
    if floorNum < totalFloors then
        -- Place down stairs in last room
        local lastRoom = rooms[#rooms]
        local stairX, stairY = lastRoom.centerX, lastRoom.centerY
        grid[stairY][stairX] = 12  -- Down stairs
        table.insert(stairs, {
            x = stairX,
            y = stairY,
            dir = "down",
            targetFloor = floorNum + 1,
            targetX = lastRoom.centerX + 0.5,  -- Placeholder, will be updated
            targetY = lastRoom.centerY + 0.5,
        })
    end

    if floorNum > 1 then
        -- Place up stairs in first room
        local firstRoom = rooms[1]
        local stairX, stairY = firstRoom.centerX, firstRoom.centerY
        grid[stairY][stairX] = 11  -- Up stairs
        table.insert(stairs, {
            x = stairX,
            y = stairY,
            dir = "up",
            targetFloor = floorNum - 1,
            targetX = firstRoom.centerX + 0.5,  -- Placeholder
            targetY = firstRoom.centerY + 0.5,
        })
    end

    -- Create floor data
    local floorData = {
        name = WorldGen.getFloorName(biome, floorNum, totalFloors),
        data = grid,
        rooms = rooms,
        stairs = stairs,
        doors = doorPositions,
    }

    return floorData
end

-- BSP room generation
function WorldGen.generateRoomsBSP(width, height, biome)
    local rooms = {}
    local containers = {{x1 = 2, y1 = 2, x2 = width - 2, y2 = height - 2}}
    local minSize = biome.roomMinSize + 3  -- Add padding for walls

    -- Split containers recursively
    local splits = 0
    local maxSplits = 5

    while splits < maxSplits and #containers < biome.roomCount.max do
        local newContainers = {}

        for _, container in ipairs(containers) do
            local w = container.x2 - container.x1
            local h = container.y2 - container.y1

            -- Can we split?
            if w >= minSize * 2 or h >= minSize * 2 then
                -- Choose split direction
                local splitHorizontal = math.random() > 0.5

                if w < minSize * 2 then
                    splitHorizontal = true
                elseif h < minSize * 2 then
                    splitHorizontal = false
                end

                if splitHorizontal and h >= minSize * 2 then
                    -- Horizontal split
                    local splitY = container.y1 + minSize + math.random(h - minSize * 2)
                    table.insert(newContainers, {
                        x1 = container.x1, y1 = container.y1,
                        x2 = container.x2, y2 = splitY
                    })
                    table.insert(newContainers, {
                        x1 = container.x1, y1 = splitY,
                        x2 = container.x2, y2 = container.y2
                    })
                elseif not splitHorizontal and w >= minSize * 2 then
                    -- Vertical split
                    local splitX = container.x1 + minSize + math.random(w - minSize * 2)
                    table.insert(newContainers, {
                        x1 = container.x1, y1 = container.y1,
                        x2 = splitX, y2 = container.y2
                    })
                    table.insert(newContainers, {
                        x1 = splitX, y1 = container.y1,
                        x2 = container.x2, y2 = container.y2
                    })
                else
                    table.insert(newContainers, container)
                end
            else
                table.insert(newContainers, container)
            end
        end

        containers = newContainers
        splits = splits + 1
    end

    -- Create rooms within containers
    for i, container in ipairs(containers) do
        if i > biome.roomCount.max then break end

        local w = container.x2 - container.x1
        local h = container.y2 - container.y1

        -- Random room size within container
        local roomW = math.min(biome.roomMaxSize, math.max(biome.roomMinSize, w - 2))
        local roomH = math.min(biome.roomMaxSize, math.max(biome.roomMinSize, h - 2))

        -- Random position within container
        local roomX = container.x1 + math.random(math.max(1, w - roomW))
        local roomY = container.y1 + math.random(math.max(1, h - roomH))

        local room = {
            x1 = roomX,
            y1 = roomY,
            x2 = roomX + roomW,
            y2 = roomY + roomH,
            centerX = math.floor(roomX + roomW / 2),
            centerY = math.floor(roomY + roomH / 2),
        }

        table.insert(rooms, room)
    end

    return rooms
end

-- Carve a room into the grid
function WorldGen.carveRoom(grid, room, biome)
    -- First carve the interior (leave 1-tile border for walls)
    for y = room.y1 + 1, room.y2 - 1 do
        for x = room.x1 + 1, room.x2 - 1 do
            if y >= 1 and y <= #grid and x >= 1 and x <= #grid[1] then
                grid[y][x] = 0  -- Empty floor
            end
        end
    end
end

-- Connect rooms with corridors
function WorldGen.connectRooms(grid, rooms, biome)
    for i = 1, #rooms - 1 do
        local roomA = rooms[i]
        local roomB = rooms[i + 1]

        -- Carve L-shaped corridor
        local startX, startY = roomA.centerX, roomA.centerY
        local endX, endY = roomB.centerX, roomB.centerY

        -- Horizontal then vertical
        if math.random() > 0.5 then
            WorldGen.carveCorridor(grid, startX, startY, endX, startY, biome.corridorWidth)
            WorldGen.carveCorridor(grid, endX, startY, endX, endY, biome.corridorWidth)
        else
            -- Vertical then horizontal
            WorldGen.carveCorridor(grid, startX, startY, startX, endY, biome.corridorWidth)
            WorldGen.carveCorridor(grid, startX, endY, endX, endY, biome.corridorWidth)
        end
    end
end

-- Carve a corridor
function WorldGen.carveCorridor(grid, x1, y1, x2, y2, width)
    local minX = math.min(x1, x2)
    local maxX = math.max(x1, x2)
    local minY = math.min(y1, y2)
    local maxY = math.max(y1, y2)

    for y = minY - math.floor(width / 2), maxY + math.floor(width / 2) do
        for x = minX - math.floor(width / 2), maxX + math.floor(width / 2) do
            if y >= 1 and y <= #grid and x >= 1 and x <= #grid[1] then
                grid[y][x] = 0  -- Empty
            end
        end
    end
end

-- Place doors at room entrances ONLY (not in corridors)
function WorldGen.placeDoors(grid, rooms)
    local doors = {}

    -- Helper function to check if a tile is inside a room
    local function isInRoom(x, y, room)
        return x > room.x1 and x < room.x2 and y > room.y1 and y < room.y2
    end

    -- Helper function to check if position is on room perimeter
    local function isOnPerimeter(x, y, room)
        local onVerticalEdge = (x == room.x1 or x == room.x2) and y >= room.y1 and y <= room.y2
        local onHorizontalEdge = (y == room.y1 or y == room.y2) and x >= room.x1 and x <= room.x2
        return onVerticalEdge or onHorizontalEdge
    end

    -- For each room, find where corridors connect
    for _, room in ipairs(rooms) do
        local doorsPlaced = 0
        local maxDoorsPerRoom = 3  -- Limit doors per room

        -- Scan room perimeter for connections to corridors
        -- Top edge (horizontal wall = "ew" door, spans east-west, blocks north-south)
        for x = room.x1 + 1, room.x2 - 1 do
            if doorsPlaced >= maxDoorsPerRoom then break end
            local y = room.y1
            -- Check if there's empty space outside and wall at edge and empty inside
            if y > 1 and grid[y-1][x] == 0 and grid[y][x] ~= 0 and grid[y+1][x] == 0 then
                -- Make sure we're not placing multiple doors in a row
                if grid[y][x-1] ~= 10 and grid[y][x+1] ~= 10 then
                    grid[y][x] = 10
                    table.insert(doors, {x = x, y = y, dir = "ew"})
                    doorsPlaced = doorsPlaced + 1
                end
            end
        end

        -- Bottom edge (horizontal wall = "ew" door)
        for x = room.x1 + 1, room.x2 - 1 do
            if doorsPlaced >= maxDoorsPerRoom then break end
            local y = room.y2
            if y < #grid and grid[y+1][x] == 0 and grid[y][x] ~= 0 and grid[y-1][x] == 0 then
                if grid[y][x-1] ~= 10 and grid[y][x+1] ~= 10 then
                    grid[y][x] = 10
                    table.insert(doors, {x = x, y = y, dir = "ew"})
                    doorsPlaced = doorsPlaced + 1
                end
            end
        end

        -- Left edge (vertical wall = "ns" door, spans north-south, blocks east-west)
        for y = room.y1 + 1, room.y2 - 1 do
            if doorsPlaced >= maxDoorsPerRoom then break end
            local x = room.x1
            if x > 1 and grid[y][x-1] == 0 and grid[y][x] ~= 0 and grid[y][x+1] == 0 then
                if grid[y-1][x] ~= 10 and grid[y+1][x] ~= 10 then
                    grid[y][x] = 10
                    table.insert(doors, {x = x, y = y, dir = "ns"})
                    doorsPlaced = doorsPlaced + 1
                end
            end
        end

        -- Right edge (vertical wall = "ns" door)
        for y = room.y1 + 1, room.y2 - 1 do
            if doorsPlaced >= maxDoorsPerRoom then break end
            local x = room.x2
            if x < #grid[1] and grid[y][x+1] == 0 and grid[y][x] ~= 0 and grid[y][x-1] == 0 then
                if grid[y-1][x] ~= 10 and grid[y+1][x] ~= 10 then
                    grid[y][x] = 10
                    table.insert(doors, {x = x, y = y, dir = "ns"})
                    doorsPlaced = doorsPlaced + 1
                end
            end
        end
    end

    return doors
end

-- Generate floor name
function WorldGen.getFloorName(biome, floorNum, totalFloors)
    local names = {
        dungeon = {"Entry Hall", "Lower Chambers", "Deep Vault", "Forgotten Depths", "The Pit"},
        cave = {"Cave Entrance", "Winding Passages", "Underground Lake", "Crystal Cavern", "The Abyss"},
        crypt = {"Burial Hall", "Tomb of Ancients", "Catacombs", "Ossuary", "Lich's Chamber"},
        mine = {"Mine Entrance", "Upper Shafts", "Middle Veins", "Deep Tunnels", "Abandoned Core"},
        town = {"Market Square", "Residential District", "Warehouse Row", "Noble Quarter", "Town Square"},
        desert_ruins = {"Surface Ruins", "Buried Temple", "Sand-Choked Hall", "Ancient Chamber", "Pharaoh's Vault"},
        forest = {"Forest Path", "Grove Clearing", "Ancient Trees", "Druid Circle", "Heart of the Forest"},
        void_sanctum = {"Outer Sanctum", "The Inner Void", "Ethereal Chamber", "Void Core", "Nothingness"},
        castle = {"Great Hall", "Upper Chambers", "Tower Summit", "Throne Room", "Royal Vault"},
        coral_reef = {"Reef Shallows", "Coral Gardens", "Reef Plateau", "Deep Reef", "Reef Abyss"},
        kelp_forest = {"Kelp Canopy", "Dense Fronds", "Kelp Root System", "Sunken Grove", "Deep Forest Floor"},
        volcanic_vent = {"Vent Field", "Thermal Columns", "Magma Channels", "Obsidian Caves", "Core Vent"},
        abyssal_trench = {"Trench Rim", "Descent", "The Narrows", "Pressure Zone", "The Crushing Deep"},
        sunken_ruins = {"Outer Ruins", "Collapsed Halls", "Flooded Archive", "Inner Sanctum", "Lost Chamber"},
    }

    local nameList = names[biome.id] or names.dungeon
    return nameList[floorNum] or ("Floor " .. floorNum)
end

-- ============================================================================
--                         PUBLIC API
-- ============================================================================

--- Generate a multi-biome map where each floor uses a different biome.
--- @param biomeIds table  Array of biome id strings, one per floor.
--- @param options  table  Same as WorldGen.generate options.
function WorldGen.generateMultiBiome(biomeIds, options)
    options = options or {}

    local width  = options.width or 48
    local height = options.height or 48
    local seed   = options.seed or os.time()
    local floors = #biomeIds

    if seed then math.randomseed(seed) end

    local firstBiome = WorldGen.BIOMES[biomeIds[1]] or WorldGen.BIOMES.dungeon

    local map = {
        theme = firstBiome.theme,
        spawnX = 2.5,
        spawnY = 2.5,
        spawnFloor = 1,
        currentFloor = 1,
        floors = {},
        biome = firstBiome,
    }

    -- Generate each floor with its own biome
    for floor = 1, floors do
        local biome = WorldGen.BIOMES[biomeIds[floor]] or WorldGen.BIOMES.dungeon
        local floorData = WorldGen.generateFloor(width, height, biome, floor, floors)
        floorData.biomeId = biomeIds[floor]
        table.insert(map.floors, floorData)
    end

    -- Link stairs between floors
    for floor = 1, floors - 1 do
        local currentFloor = map.floors[floor]
        local nextFloor = map.floors[floor + 1]
        for _, stair in ipairs(currentFloor.stairs) do
            if stair.dir == "down" then
                for _, nextStair in ipairs(nextFloor.stairs) do
                    if nextStair.dir == "up" then
                        stair.targetX = nextStair.x + 0.5
                        stair.targetY = nextStair.y + 0.5
                        nextStair.targetX = stair.x + 0.5
                        nextStair.targetY = stair.y + 0.5
                        break
                    end
                end
                break
            end
        end
    end

    -- Find spawn point on first floor
    if map.floors[1] and map.floors[1].rooms and #map.floors[1].rooms > 0 then
        local firstRoom = map.floors[1].rooms[1]
        map.spawnX = firstRoom.centerX + 0.5
        map.spawnY = firstRoom.centerY + 0.5
    end

    -- Initialize doors for first floor
    Doors.init()
    if map.floors[1] and map.floors[1].doors then
        for _, door in ipairs(map.floors[1].doors) do
            Doors.add(door.x, door.y, door.dir)
        end
    end

    setmetatable(map, {__index = WorldGen.MapMethods})
    return map
end

-- Generate a complete dungeon map
function WorldGen.generate(biomeId, options)
    options = options or {}

    local width = options.width or 48
    local height = options.height or 48
    local floors = options.floors or 3
    local seed = options.seed or os.time()

    -- Generate the map
    local map = WorldGen.generateBSPDungeon(width, height, biomeId, floors, seed)

    -- Initialize doors module for this map
    Doors.init()

    -- Register doors for first floor (will be updated when player changes floors)
    if map.floors[1] and map.floors[1].doors then
        for _, door in ipairs(map.floors[1].doors) do
            Doors.add(door.x, door.y, door.dir)
        end
    end

    -- Add methods
    setmetatable(map, {__index = WorldGen.MapMethods})

    return map
end

-- Map instance methods (same as original map.lua)
WorldGen.MapMethods = {}

function WorldGen.MapMethods:getData()
    return self.floors[self.currentFloor] or self.floors[1]
end

function WorldGen.MapMethods:getTile(x, y)
    local data = self:getData().data
    if y < 1 or y > #data then
        return self.biome.primaryWall
    end
    if x < 1 or x > #data[y] then
        return self.biome.primaryWall
    end
    return data[y][x]
end

function WorldGen.MapMethods:setTile(x, y, value)
    local data = self:getData().data
    if y >= 1 and y <= #data and x >= 1 and x <= #data[y] then
        data[y][x] = value
    end
end

function WorldGen.MapMethods:getWidth()
    return #self:getData().data[1]
end

function WorldGen.MapMethods:getHeight()
    return #self:getData().data
end

function WorldGen.MapMethods:isWalkable(x, y)
    local tile = self:getTile(math.floor(x), math.floor(y))

    if tile == 10 then
        return Doors.isPassable(math.floor(x), math.floor(y))
    end

    if tile == 11 or tile == 12 then
        return true
    end

    return tile == 0
end

function WorldGen.MapMethods:getStairsAt(x, y)
    local floorData = self:getData()
    if not floorData.stairs then return nil end

    local tileX = math.floor(x)
    local tileY = math.floor(y)

    for _, stair in ipairs(floorData.stairs) do
        if stair.x == tileX and stair.y == tileY then
            return stair
        end
    end
    return nil
end

function WorldGen.MapMethods:changeFloor(floorNum, newX, newY)
    if self.floors[floorNum] then
        self.currentFloor = floorNum
        return newX, newY
    end
    return nil, nil
end

function WorldGen.MapMethods:getFloorName()
    local floorData = self:getData()
    return floorData.name or ("Floor " .. self.currentFloor)
end

function WorldGen.MapMethods:getFloorCount()
    return #self.floors
end

return WorldGen
