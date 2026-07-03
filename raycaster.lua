--[[
    Raycaster Module
    DDA (Digital Differential Analyzer) algorithm for wall rendering
    With theme support, sky/floor/ceiling rendering, doors, corruption,
    atmosphere system, and optional flooding/water integration.
]]

local Raycaster = {}

local Themes = require("themes")
local Doors = require("doors")
local Corruption = require("corruption")
local Atmosphere = require("atmosphere")

-- Optional flooding module (injected via setFlooding or auto-detected)
local Flooding = nil

local map
local textures = {}
local doorTexture
local ceilingTexture
local corruptedFloorTexture
local stairsUpTexture
local stairsDownTexture
local currentTheme

-- Precomputed values
local screenWidth, screenHeight
local texWidth = 64
local texHeight = 64

-- Cached math functions
local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local math_sin = math.sin
local math_abs = math.abs

-- Render canvas for sky/floor
local skyFloorCanvas

-- Pre-allocated quad cache (one per texX column, avoids per-frame allocation)
local quadCache = {}

-- Ceiling zones (tiles that have ceilings)
local ceilingZones = {}

function Raycaster.init(config, gameMap, themeName)
    map = gameMap
    screenWidth = config.renderWidth
    screenHeight = config.renderHeight

    -- Set theme
    Raycaster.setTheme(themeName or "dungeon")

    -- Create canvas for sky/floor gradient
    skyFloorCanvas = love.graphics.newCanvas(screenWidth, screenHeight)
    Raycaster.generateSkyFloor()

    -- Pre-allocate quad cache (one quad per texX column, reused every frame)
    for i = 0, texWidth - 1 do
        quadCache[i] = love.graphics.newQuad(i, 0, 1, texHeight, texWidth, texHeight)
    end
end

function Raycaster.setTheme(themeName)
    currentTheme = Themes.get(themeName)
    Raycaster.generateTextures()
    Raycaster.generateDoorTexture()
    Raycaster.generateCeilingTexture()
    Raycaster.generateCorruptedTexture()
    Raycaster.generateStairsTextures()

    -- Regenerate sky/floor if canvas exists
    if skyFloorCanvas then
        Raycaster.generateSkyFloor()
    end
end

function Raycaster.getTheme()
    return currentTheme
end

-- Mark a rectangular area as having a ceiling
function Raycaster.addCeilingZone(x1, y1, x2, y2)
    table.insert(ceilingZones, {x1 = x1, y1 = y1, x2 = x2, y2 = y2})
end

function Raycaster.clearCeilingZones()
    ceilingZones = {}
end

-- Check if a position has a ceiling
function Raycaster.hasCeiling(x, y)
    for _, zone in ipairs(ceilingZones) do
        if x >= zone.x1 and x <= zone.x2 and y >= zone.y1 and y <= zone.y2 then
            return true
        end
    end
    return false
end

-- Flooding integration (optional - injected from main game systems)
function Raycaster.setFlooding(floodingModule)
    Flooding = floodingModule
end

function Raycaster.getFlooding()
    return Flooding
end

function Raycaster.generateSkyFloor()
    love.graphics.setCanvas(skyFloorCanvas)
    love.graphics.clear()

    local horizon = screenHeight / 2

    -- Draw sky gradient (top half)
    for y = 0, horizon - 1 do
        local t = y / horizon
        local sky = currentTheme.sky
        local r = sky.top[1] + (sky.bottom[1] - sky.top[1]) * t
        local g = sky.top[2] + (sky.bottom[2] - sky.top[2]) * t
        local b = sky.top[3] + (sky.bottom[3] - sky.top[3]) * t
        love.graphics.setColor(r, g, b)
        love.graphics.rectangle("fill", 0, y, screenWidth, 1)
    end

    -- Draw floor gradient (bottom half)
    for y = horizon, screenHeight - 1 do
        local t = (y - horizon) / (screenHeight - horizon)
        local floor = currentTheme.floor
        local r = floor.far[1] + (floor.near[1] - floor.far[1]) * t
        local g = floor.far[2] + (floor.near[2] - floor.far[2]) * t
        local b = floor.far[3] + (floor.near[3] - floor.far[3]) * t
        love.graphics.setColor(r, g, b)
        love.graphics.rectangle("fill", 0, y, screenWidth, 1)
    end

    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1)
end

function Raycaster.generateTextures()
    textures = {}

    for i, color in ipairs(currentTheme.walls) do
        local imageData = love.image.newImageData(texWidth, texHeight)

        for y = 0, texHeight - 1 do
            for x = 0, texWidth - 1 do
                local r = color[1] + (math.random() - 0.5) * 0.15
                local g = color[2] + (math.random() - 0.5) * 0.15
                local b = color[3] + (math.random() - 0.5) * 0.15

                local brickW = 16
                local brickH = 8
                local offsetX = (math.floor(y / brickH) % 2) * (brickW / 2)
                local brickX = (x + offsetX) % brickW
                local brickY = y % brickH

                if brickX == 0 or brickY == 0 then
                    r = r * 0.6
                    g = g * 0.6
                    b = b * 0.6
                end

                r = math.max(0, math.min(1, r))
                g = math.max(0, math.min(1, g))
                b = math.max(0, math.min(1, b))

                imageData:setPixel(x, y, r, g, b, 1)
            end
        end

        textures[i] = love.graphics.newImage(imageData)
        textures[i]:setFilter("nearest", "nearest")
        textures[i]:setWrap("repeat", "repeat")
    end
end

function Raycaster.generateDoorTexture()
    local color = currentTheme.doorColor
    local imageData = love.image.newImageData(texWidth, texHeight)

    for y = 0, texHeight - 1 do
        for x = 0, texWidth - 1 do
            local grain = math.sin(y * 0.5 + x * 0.1) * 0.1
            local r = color[1] + grain + (math.random() - 0.5) * 0.1
            local g = color[2] + grain * 0.8 + (math.random() - 0.5) * 0.1
            local b = color[3] + grain * 0.5 + (math.random() - 0.5) * 0.1

            if x < 4 or x >= texWidth - 4 or y < 4 or y >= texHeight - 4 then
                r = r * 0.7
                g = g * 0.7
                b = b * 0.7
            end

            local panelX = x % 32
            local panelY = y % 32
            if panelX > 6 and panelX < 26 and panelY > 6 and panelY < 26 then
                if panelX == 7 or panelX == 25 or panelY == 7 or panelY == 25 then
                    r = r * 0.8
                    g = g * 0.8
                    b = b * 0.8
                end
            end

            if x > texWidth - 12 and x < texWidth - 6 and y > 28 and y < 36 then
                r, g, b = 0.6, 0.55, 0.4
            end

            r = math.max(0, math.min(1, r))
            g = math.max(0, math.min(1, g))
            b = math.max(0, math.min(1, b))

            imageData:setPixel(x, y, r, g, b, 1)
        end
    end

    doorTexture = love.graphics.newImage(imageData)
    doorTexture:setFilter("nearest", "nearest")
end

function Raycaster.generateCeilingTexture()
    local imageData = love.image.newImageData(texWidth, texHeight)

    for y = 0, texHeight - 1 do
        for x = 0, texWidth - 1 do
            -- Dark stone ceiling
            local r = 0.2 + (math.random() - 0.5) * 0.1
            local g = 0.18 + (math.random() - 0.5) * 0.1
            local b = 0.22 + (math.random() - 0.5) * 0.1

            -- Add some cracks/lines
            if (x + y) % 16 == 0 or (x - y) % 24 == 0 then
                r = r * 0.7
                g = g * 0.7
                b = b * 0.7
            end

            r = math.max(0, math.min(1, r))
            g = math.max(0, math.min(1, g))
            b = math.max(0, math.min(1, b))

            imageData:setPixel(x, y, r, g, b, 1)
        end
    end

    ceilingTexture = love.graphics.newImage(imageData)
    ceilingTexture:setFilter("nearest", "nearest")
end

function Raycaster.generateCorruptedTexture()
    local imageData = love.image.newImageData(texWidth, texHeight)

    for y = 0, texHeight - 1 do
        for x = 0, texWidth - 1 do
            -- Purple corruption texture
            local noise = math.random() * 0.3
            local r = 0.3 + noise * 0.5
            local g = 0.1 + noise * 0.2
            local b = 0.4 + noise * 0.4

            -- Veiny pattern
            local vein = math.sin(x * 0.3 + y * 0.2) * math.cos(y * 0.4 - x * 0.1)
            if vein > 0.7 then
                r = r + 0.2
                b = b + 0.2
            end

            -- Pulsing spots
            local spotX = (x % 16) - 8
            local spotY = (y % 16) - 8
            local dist = math.sqrt(spotX * spotX + spotY * spotY)
            if dist < 3 then
                r = r + 0.15
                g = g - 0.05
                b = b + 0.2
            end

            r = math.max(0, math.min(1, r))
            g = math.max(0, math.min(1, g))
            b = math.max(0, math.min(1, b))

            imageData:setPixel(x, y, r, g, b, 1)
        end
    end

    corruptedFloorTexture = love.graphics.newImage(imageData)
    corruptedFloorTexture:setFilter("nearest", "nearest")
end

function Raycaster.generateStairsTextures()
    -- Stairs Up texture (green tint with upward arrows)
    local imageData = love.image.newImageData(texWidth, texHeight)

    for y = 0, texHeight - 1 do
        for x = 0, texWidth - 1 do
            -- Stone base with green tint
            local r = 0.3 + (math.random() - 0.5) * 0.1
            local g = 0.4 + (math.random() - 0.5) * 0.1
            local b = 0.3 + (math.random() - 0.5) * 0.1

            -- Stair step pattern (horizontal lines)
            local stepHeight = 8
            local stepY = y % stepHeight
            if stepY < 2 then
                r = r * 1.3
                g = g * 1.3
                b = b * 1.3
            end

            -- Upward arrow in center
            local cx = x - texWidth / 2
            local cy = y - texHeight / 2
            -- Arrow body
            if math.abs(cx) < 4 and cy > -10 and cy < 15 then
                r, g, b = 0.2, 0.8, 0.3
            end
            -- Arrow head
            if cy < 0 and cy > -15 then
                local arrowWidth = (-cy) * 0.8
                if math.abs(cx) < arrowWidth then
                    r, g, b = 0.2, 0.9, 0.3
                end
            end

            r = math.max(0, math.min(1, r))
            g = math.max(0, math.min(1, g))
            b = math.max(0, math.min(1, b))

            imageData:setPixel(x, y, r, g, b, 1)
        end
    end

    stairsUpTexture = love.graphics.newImage(imageData)
    stairsUpTexture:setFilter("nearest", "nearest")

    -- Stairs Down texture (red tint with downward arrows)
    imageData = love.image.newImageData(texWidth, texHeight)

    for y = 0, texHeight - 1 do
        for x = 0, texWidth - 1 do
            -- Stone base with red tint
            local r = 0.4 + (math.random() - 0.5) * 0.1
            local g = 0.3 + (math.random() - 0.5) * 0.1
            local b = 0.3 + (math.random() - 0.5) * 0.1

            -- Stair step pattern
            local stepHeight = 8
            local stepY = y % stepHeight
            if stepY > stepHeight - 3 then
                r = r * 0.7
                g = g * 0.7
                b = b * 0.7
            end

            -- Downward arrow in center
            local cx = x - texWidth / 2
            local cy = y - texHeight / 2
            -- Arrow body
            if math.abs(cx) < 4 and cy > -15 and cy < 10 then
                r, g, b = 0.8, 0.2, 0.2
            end
            -- Arrow head (pointing down)
            if cy > 0 and cy < 15 then
                local arrowWidth = cy * 0.8
                if math.abs(cx) < arrowWidth then
                    r, g, b = 0.9, 0.2, 0.2
                end
            end

            r = math.max(0, math.min(1, r))
            g = math.max(0, math.min(1, g))
            b = math.max(0, math.min(1, b))

            imageData:setPixel(x, y, r, g, b, 1)
        end
    end

    stairsDownTexture = love.graphics.newImage(imageData)
    stairsDownTexture:setFilter("nearest", "nearest")
end

function Raycaster.render(player, config)
    local posX, posY = player.x, player.y
    local dirX, dirY = player.dirX, player.dirY
    local planeX, planeY = player.planeX, player.planeY
    local hShift = player.horizonShift or 0  -- Horizon offset for top-down camera
    local minRenderDist = player.minRenderDist or 0  -- Skip walls between camera and player

    -- Draw sky and floor first
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(skyFloorCanvas, 0, 0)

    -- Draw corruption on floor (before walls)
    Raycaster.renderCorruptedFloor(player, config)

    -- Draw flooded floor tiles (before walls, like corruption)
    Raycaster.renderFloodedFloor(player, config)

    -- Z-buffer for sprite rendering
    local zBuffer = {}

    -- Pre-compute per-frame values (constant across all columns)
    local baseFogDensity = Atmosphere.getFogDensity()
    local baseAmbient = Atmosphere.getAmbient()
    local baseFogColor = Atmosphere.getFogColor()
    local floodFogMult = Flooding and Flooding.getFogMultiplier() or 1.0
    local effectiveFogDensity = baseFogDensity * floodFogMult
    local roomWater = Flooding and Flooding.getRoomWaterLevel() or 0
    local hasRoomWater = roomWater > 0.05
    local halfScreenH = screenHeight / 2
    local maxViewDist = Atmosphere.getMaxViewDist()

    -- Cast a ray for each vertical stripe
    for x = 0, screenWidth - 1 do
        local cameraX = 2 * x / screenWidth - 1
        local rayDirX = dirX + planeX * cameraX
        local rayDirY = dirY + planeY * cameraX

        local mapX = math_floor(posX)
        local mapY = math_floor(posY)

        local deltaDistX = (rayDirX == 0) and 1e30 or math_abs(1 / rayDirX)
        local deltaDistY = (rayDirY == 0) and 1e30 or math_abs(1 / rayDirY)

        local perpWallDist

        local stepX, stepY
        local sideDistX, sideDistY

        if rayDirX < 0 then
            stepX = -1
            sideDistX = (posX - mapX) * deltaDistX
        else
            stepX = 1
            sideDistX = (mapX + 1 - posX) * deltaDistX
        end

        if rayDirY < 0 then
            stepY = -1
            sideDistY = (posY - mapY) * deltaDistY
        else
            stepY = 1
            sideDistY = (mapY + 1 - posY) * deltaDistY
        end

        local hit = false
        local side = 0
        local wallType = 1
        local isDoor = false
        local isStairs = false
        local stairsDir = nil
        local doorHit = nil
        local hitMapX, hitMapY = mapX, mapY

        local maxSteps = maxViewDist  -- Pre-computed view distance from atmosphere
        local steps = 0

        while not hit and steps < maxSteps do
            steps = steps + 1

            if sideDistX < sideDistY then
                sideDistX = sideDistX + deltaDistX
                mapX = mapX + stepX
                side = 0
            else
                sideDistY = sideDistY + deltaDistY
                mapY = mapY + stepY
                side = 1
            end

            local door = Doors.getAt(mapX, mapY)
            if door then
                -- Closed doors render flush with cell boundary (like walls)
                -- Only use ray-line intersection for doors that are partially open
                if door.angle > 0.01 then
                    doorHit = Doors.rayIntersect(door, posX, posY, rayDirX, rayDirY)
                    if doorHit then
                        if doorHit.distance >= minRenderDist then
                            hit = true
                            isDoor = true
                            perpWallDist = doorHit.distance
                            hitMapX, hitMapY = mapX, mapY
                        else
                            doorHit = nil
                        end
                    end
                else
                    -- Closed door: treat like a wall at the cell boundary
                    local wallDist
                    if side == 0 then
                        wallDist = sideDistX - deltaDistX
                    else
                        wallDist = sideDistY - deltaDistY
                    end
                    if wallDist >= minRenderDist then
                        hit = true
                        isDoor = true
                        perpWallDist = wallDist
                        hitMapX, hitMapY = mapX, mapY
                        -- Generate texCoord from wall position (same as walls)
                        local wallX
                        if side == 0 then
                            wallX = posY + wallDist * rayDirY
                        else
                            wallX = posX + wallDist * rayDirX
                        end
                        wallX = wallX - math_floor(wallX)
                        doorHit = { distance = wallDist, texCoord = wallX }
                    end
                end
            end

            if not hit then
                local tile = map:getTile(mapX, mapY)
                if tile > 0 and tile < 10 then
                    -- Calculate wall distance to check against minRenderDist
                    local wallDist
                    if side == 0 then
                        wallDist = sideDistX - deltaDistX
                    else
                        wallDist = sideDistY - deltaDistY
                    end
                    -- Skip walls between camera and player in third-person
                    if wallDist >= minRenderDist then
                        hit = true
                        wallType = tile
                        hitMapX, hitMapY = mapX, mapY
                    end
                elseif tile == 11 or tile == 12 then
                    local wallDist
                    if side == 0 then
                        wallDist = sideDistX - deltaDistX
                    else
                        wallDist = sideDistY - deltaDistY
                    end
                    if wallDist >= minRenderDist then
                        hit = true
                        isStairs = true
                        stairsDir = (tile == 11) and "up" or "down"
                        hitMapX, hitMapY = mapX, mapY
                    end
                end
            end
        end

        if not isDoor then
            if side == 0 then
                perpWallDist = sideDistX - deltaDistX
            else
                perpWallDist = sideDistY - deltaDistY
            end
        end

        -- Clamp minimum distance to prevent extreme wall heights when too close
        if perpWallDist < 0.2 then perpWallDist = 0.2 end

        zBuffer[x] = perpWallDist

        -- Calculate line height with a maximum cap to prevent droop/stretching
        local lineHeight = math_floor(screenHeight / perpWallDist)
        local maxLineHeight = screenHeight * 4  -- Cap at 4x screen height
        if lineHeight > maxLineHeight then lineHeight = maxLineHeight end

        local drawStart = math_floor(-lineHeight / 2 + screenHeight / 2 + hShift)
        if drawStart < 0 then drawStart = 0 end
        local drawEnd = math_floor(lineHeight / 2 + screenHeight / 2 + hShift)
        if drawEnd >= screenHeight then drawEnd = screenHeight - 1 end

        local wallX
        if isDoor and doorHit then
            wallX = doorHit.texCoord
        elseif side == 0 then
            wallX = posY + perpWallDist * rayDirY
        else
            wallX = posX + perpWallDist * rayDirX
        end
        wallX = wallX - math_floor(wallX)

        local texX = math_floor(wallX * texWidth)
        if not isDoor then
            if (side == 0 and rayDirX > 0) or (side == 1 and rayDirY < 0) then
                texX = texWidth - texX - 1
            end
        end

        -- Use pre-computed atmosphere values
        local fogDensity = effectiveFogDensity
        local ambient = baseAmbient

        -- Multiplicative falloff: walls dim with distance but never go fully black
        local distFactor = 1.0 / (1.0 + perpWallDist * fogDensity * 2.0)
        local shade = ambient * (0.2 + 0.8 * distFactor)

        if side == 1 and not isDoor and not isStairs then
            shade = shade * 0.75
        end

        -- Check for corruption on this wall tile
        local corruptionLevel = Corruption.getLevel(hitMapX, hitMapY)

        -- Draw ceiling for indoor areas BEFORE walls (so walls draw on top)
        -- Check if the PLAYER/CAMERA is in a ceiling zone (indoor room), not the wall hit
        if Raycaster.hasCeiling(posX, posY) then
            local ceilingEnd = drawStart
            if ceilingEnd > 0 then
                local clampedEnd = math_min(ceilingEnd, screenHeight)

                -- Distance-based ceiling brightness (brighter near, darker far)
                local distBright = 1.0 / (1.0 + perpWallDist * 0.3)
                -- Ceiling base: metallic gray with strong contrast vs sky
                local cr = 0.12 + distBright * 0.18
                local cg = 0.13 + distBright * 0.16
                local cb = 0.16 + distBright * 0.14

                -- Main ceiling fill
                love.graphics.setColor(cr, cg, cb)
                love.graphics.rectangle("fill", x, 0, 1, clampedEnd)

                -- Panel seam lines every 12 pixels (dark grooves for visual pattern)
                local seamR = cr * 0.3
                local seamG = cg * 0.3
                local seamB = cb * 0.3
                love.graphics.setColor(seamR, seamG, seamB)
                for cy = 0, clampedEnd - 1, 12 do
                    love.graphics.rectangle("fill", x, cy, 1, math_min(1, clampedEnd - cy))
                end
                -- Vertical seam every 24 columns (panel grid)
                if x % 24 < 1 then
                    love.graphics.setColor(seamR, seamG, seamB)
                    love.graphics.rectangle("fill", x, 0, 1, clampedEnd)
                end
            end
        end

        -- Select appropriate texture
        local texture
        if isDoor then
            texture = doorTexture
        elseif isStairs then
            texture = (stairsDir == "up") and stairsUpTexture or stairsDownTexture
        else
            texture = textures[wallType] or textures[1]
        end
        if texture then
            local quad = quadCache[texX]

            local scaleY = lineHeight / texHeight

            local fogT = math_min(perpWallDist * fogDensity * 0.5, 0.85)
            local r = shade * (1 - fogT) + baseFogColor[1] * fogT
            local g = shade * (1 - fogT) + baseFogColor[2] * fogT
            local b = shade * (1 - fogT) + baseFogColor[3] * fogT

            -- Apply corruption tint to walls
            if corruptionLevel > 0 then
                r, g, b = Corruption.applyTint(r, g, b, corruptionLevel)
            end

            -- Apply per-tile water tinting (from breach flooding)
            local waterLevel = 0
            if Flooding then
                waterLevel = Flooding.getLevelFast(hitMapX, hitMapY)
                if waterLevel > 0 then
                    r, g, b = Flooding.applyTint(r, g, b, waterLevel)
                end
            end

            -- Apply atmosphere color grading (desaturation, color shift)
            r, g, b = Atmosphere.applyColorGrading(r, g, b)

            -- Check for room-wide water level (split wall into dry/wet sections)
            if hasRoomWater and waterLevel <= 0 then
                -- Split wall: dry above waterline, tinted below
                local horizon = halfScreenH + hShift
                local wallWaterY = math_floor(horizon + (screenHeight - horizon) * (1.0 - roomWater))

                if wallWaterY < drawEnd and wallWaterY > drawStart then
                    -- Dry section (above waterline)
                    love.graphics.setColor(r, g, b)
                    love.graphics.setScissor(x, drawStart, 1, wallWaterY - drawStart)
                    love.graphics.draw(texture, quad, x, drawStart, 0, 1, scaleY)
                    love.graphics.setScissor()

                    -- Wet section (below waterline)
                    local wr, wg, wb = Flooding.applyTint(r, g, b, roomWater)
                    love.graphics.setColor(wr, wg, wb)
                    love.graphics.setScissor(x, wallWaterY, 1, drawEnd - wallWaterY)
                    love.graphics.draw(texture, quad, x, drawStart, 0, 1, scaleY)
                    love.graphics.setScissor()
                else
                    -- Entirely above or below waterline
                    if drawStart >= wallWaterY then
                        -- All below water
                        local wr, wg, wb = Flooding.applyTint(r, g, b, roomWater)
                        love.graphics.setColor(wr, wg, wb)
                    else
                        love.graphics.setColor(r, g, b)
                    end
                    love.graphics.draw(texture, quad, x, drawStart, 0, 1, scaleY)
                end
            else
                love.graphics.setColor(r, g, b)
                love.graphics.draw(texture, quad, x, drawStart, 0, 1, scaleY)
            end
        end
    end

    -- Draw water plane on top of walls (room-wide flooding)
    Raycaster.renderWaterPlane(player, config)

    -- Draw submerged overlay (when deeply flooded)
    Raycaster.renderSubmergedOverlay()

    love.graphics.setColor(1, 1, 1)
    return zBuffer
end

-- Render corrupted floor tiles (optimised: 2x2 pixel blocks, cached lookups)
function Raycaster.renderCorruptedFloor(player, config)
    local posX, posY = player.x, player.y
    local dirX, dirY = player.dirX, player.dirY
    local planeX, planeY = player.planeX, player.planeY
    local hShift = player.horizonShift or 0

    local corruptedTiles = Corruption.getAllCorrupted()

    -- Quick bail if nothing corrupted
    local hasAny = false
    for _ in pairs(corruptedTiles) do hasAny = true; break end
    if not hasAny then return end

    local horizon = screenHeight / 2 + hShift
    local halfH = 0.5 * screenHeight
    local currentTime = love.timer.getTime()
    local pulse = 0.7 + math_sin(currentTime * 4) * 0.3
    local lg = love.graphics

    local rayDirX0 = dirX - planeX
    local rayDirY0 = dirY - planeY
    local rayDirX1 = dirX + planeX
    local rayDirY1 = dirY + planeY

    local startY = math_max(0, math_floor(horizon + 1))
    -- Step by 2 pixels for performance (render 2x2 blocks)
    local step = 2
    for y = startY, screenHeight - 1, step do
        local p = y - horizon
        if p > 0 then
            local rowDistance = halfH / p
            local floorStepX = rowDistance * (rayDirX1 - rayDirX0) / screenWidth
            local floorStepY = rowDistance * (rayDirY1 - rayDirY0) / screenWidth
            local floorX = posX + rowDistance * rayDirX0
            local floorY = posY + rowDistance * rayDirY0

            for x = 0, screenWidth - 1, step do
                local cellX = math_floor(floorX)
                local cellY = math_floor(floorY)
                local tileId = cellX .. "," .. cellY

                local corruptionLevel = corruptedTiles[tileId]
                if corruptionLevel and corruptionLevel > 0.1 then
                    local alpha = corruptionLevel * 0.6

                    if Corruption.isSource(cellX, cellY) then
                        lg.setColor(0.6 * pulse, 0.1, 0.7 * pulse, alpha)
                    else
                        local tint = Corruption.getColor(corruptionLevel)
                        lg.setColor(tint[1], tint[2], tint[3], alpha)
                    end

                    lg.rectangle("fill", x, y, step, step)
                end

                floorX = floorX + floorStepX * step
                floorY = floorY + floorStepY * step
            end
        end
    end
end

-- Render flooded floor tiles (optimised: 2x2 pixel blocks, cached lookups)
function Raycaster.renderFloodedFloor(player, config)
    if not Flooding then return end

    local posX, posY = player.x, player.y
    local dirX, dirY = player.dirX, player.dirY
    local planeX, planeY = player.planeX, player.planeY
    local hShift = player.horizonShift or 0

    local floodedTilesRef = Flooding.getAllFlooded()
    if not floodedTilesRef then return end

    local hasAny = false
    for _ in pairs(floodedTilesRef) do hasAny = true; break end
    if not hasAny then return end

    local horizon = screenHeight / 2 + hShift
    local halfH = 0.5 * screenHeight
    local currentTime = love.timer.getTime()
    local pulse = 0.7 + math_sin(currentTime * 4) * 0.3
    local lg = love.graphics

    local rayDirX0 = dirX - planeX
    local rayDirY0 = dirY - planeY
    local rayDirX1 = dirX + planeX
    local rayDirY1 = dirY + planeY

    local startY = math_max(0, math_floor(horizon + 1))
    local step = 2

    for y = startY, screenHeight - 1, step do
        local p = y - horizon
        if p > 0 then
            local rowDistance = halfH / p
            local floorStepX = rowDistance * (rayDirX1 - rayDirX0) / screenWidth
            local floorStepY = rowDistance * (rayDirY1 - rayDirY0) / screenWidth
            local floorX = posX + rowDistance * rayDirX0
            local floorY = posY + rowDistance * rayDirY0

            for x = 0, screenWidth - 1, step do
                local cellX = math_floor(floorX)
                local cellY = math_floor(floorY)
                local tileId = cellX .. "," .. cellY

                local waterLevel = floodedTilesRef[tileId]
                if waterLevel and waterLevel > 0.1 then
                    local alpha = waterLevel * 0.6

                    if Flooding.isBreachFast(cellX, cellY) then
                        lg.setColor(0.2 * pulse, 0.4, 0.6 * pulse, alpha)
                    else
                        local tint = Flooding.getColor(waterLevel)
                        lg.setColor(tint[1], tint[2], tint[3], alpha)
                    end

                    lg.rectangle("fill", x, y, step, step)
                end

                floorX = floorX + floorStepX * step
                floorY = floorY + floorStepY * step
            end
        end
    end
end

-- Render water plane (room-wide water surface with ripples)
function Raycaster.renderWaterPlane(player, config)
    if not Flooding then return end

    local roomWaterLvl = Flooding.getRoomWaterLevel()
    if roomWaterLvl <= 0.01 then return end

    local hShift = player.horizonShift or 0
    local horizon = screenHeight / 2 + hShift
    local waterSurfaceY = horizon + (screenHeight - horizon) * (1.0 - roomWaterLvl)

    -- Semi-transparent water fill below surface
    love.graphics.setColor(0.05, 0.15, 0.30, 0.45 + roomWaterLvl * 0.25)
    love.graphics.rectangle("fill", 0, waterSurfaceY, screenWidth, screenHeight - waterSurfaceY)

    -- Animated wavy surface ripple line (step by 4 pixels)
    local time = love.timer.getTime()
    love.graphics.setColor(0.15, 0.35, 0.55, 0.6)
    for lx = 0, screenWidth - 1, 4 do
        local waveY = waterSurfaceY + math_sin(lx * 0.05 + time * 3.0) * 2.0
        love.graphics.rectangle("fill", lx, waveY, 4, 2)
    end

    love.graphics.setColor(1, 1, 1)
end

-- Render submerged overlay (full-screen underwater tint + vignette)
function Raycaster.renderSubmergedOverlay()
    if not Flooding then return end

    local overlay = Flooding.getSubmergedOverlay()
    if overlay == nil then return end

    -- Full-screen water tint
    love.graphics.setColor(overlay.r, overlay.g, overlay.b, overlay.a)
    love.graphics.rectangle("fill", 0, 0, screenWidth, screenHeight)

    -- Vignette edges (darker at edges when submerged)
    local vignetteAlpha = overlay.a * 0.6
    local edgeSize = math_floor(screenWidth * 0.15)
    local edgeSizeV = math_floor(screenHeight * 0.15)

    love.graphics.setColor(0, 0, 0.05, vignetteAlpha)
    love.graphics.rectangle("fill", 0, 0, edgeSize, screenHeight)
    love.graphics.rectangle("fill", screenWidth - edgeSize, 0, edgeSize, screenHeight)
    love.graphics.rectangle("fill", 0, 0, screenWidth, edgeSizeV)
    love.graphics.rectangle("fill", 0, screenHeight - edgeSizeV, screenWidth, edgeSizeV)

    -- Corners get extra darkening
    local cornerAlpha = math_min(vignetteAlpha * 1.5, 1)
    local cornerW = math_floor(edgeSize * 0.7)
    local cornerH = math_floor(edgeSizeV * 0.7)

    love.graphics.setColor(0, 0, 0.03, cornerAlpha)
    love.graphics.rectangle("fill", 0, 0, cornerW, cornerH)
    love.graphics.rectangle("fill", screenWidth - cornerW, 0, cornerW, cornerH)
    love.graphics.rectangle("fill", 0, screenHeight - cornerH, cornerW, cornerH)
    love.graphics.rectangle("fill", screenWidth - cornerW, screenHeight - cornerH, cornerW, cornerH)

    love.graphics.setColor(1, 1, 1)
end

return Raycaster
