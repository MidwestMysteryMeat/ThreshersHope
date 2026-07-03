--[[
    Enemy Type Definitions and Spawning System
    Defines 8 underwater enemy types and handles depth-based spawning.
    Works on top of sprites.lua which handles rendering, AI movement, and attacks.
    This module provides TYPE DEFINITIONS and SPAWN LOGIC.

    Enemy types are themed around deep-sea creatures:
    - Crawler, Lurker, Swarm (shallow), Angler, Pressure Beast (mid/deep),
      Leviathan (deep boss), Abyssal (abyss), Hydra (trench boss).
]]

local Enemies = {}

-- Local references for performance
local math_floor = math.floor
local math_sqrt = math.sqrt
local math_random = math.random
local math_sin = math.sin
local math_cos = math.cos
local math_abs = math.abs
local math_min = math.min
local math_max = math.max
local math_pi = math.pi

-- Cached textures keyed by typeId
local textureCache = {}

-- Track spawned enemy sprite IDs for regeneration ticks
local activeEnemies = {} -- spriteId -> {typeId, regenAccum}

-- ============================================================================
--                        DEPTH ZONE IDENTIFIERS
-- ============================================================================
-- These match the zones in depth.lua for spawn eligibility checks.
-- A floor's zone name is resolved via Depth.getZoneForFloor() or by
-- comparing the floor number against these depth thresholds directly.

local ZONE_ORDER = {
    "surface",    -- 1
    "shallows",   -- 2
    "mid",        -- 3
    "deep",       -- 4
    "abyss",      -- 5
    "trench",     -- 6
}

-- Map zone names to their numeric rank for >= comparisons
local ZONE_RANK = {}
for i, name in ipairs(ZONE_ORDER) do
    ZONE_RANK[name] = i
end

-- Map depth.lua zone display names to our internal short names
local ZONE_NAME_MAP = {
    ["The Surface"]  = "surface",
    ["The Shallows"] = "shallows",
    ["Mid-Depth"]    = "mid",
    ["The Deep"]     = "deep",
    ["The Abyss"]    = "abyss",
    ["The Trench"]   = "trench",
}

-- ============================================================================
--                        ENEMY TYPE DEFINITIONS
-- ============================================================================

Enemies.TYPES = {
    crawler = {
        id          = "crawler",
        name        = "Crawler",
        description = "Small crustacean. Fast, low damage, low HP.",
        health      = 15,
        damage      = 5,
        speed       = 3.0,
        scale       = 0.5,
        attackInterval = 1.0,
        color       = {0.6, 0.3, 0.2},
        minZone     = "shallows",  -- Spawns in Shallows and deeper
        spawnWeight = 10,          -- Relative spawn frequency
        regeneration = 0,
    },
    lurker = {
        id          = "lurker",
        name        = "Lurker",
        description = "Ambush predator fish. Medium speed, medium damage.",
        health      = 30,
        damage      = 10,
        speed       = 1.8,
        scale       = 0.7,
        attackInterval = 1.5,
        color       = {0.3, 0.4, 0.35},
        minZone     = "shallows",
        spawnWeight = 8,
        regeneration = 0,
    },
    swarm = {
        id          = "swarm",
        name        = "Swarm",
        description = "Tiny fish swarm. Very fast, very low damage, very low HP.",
        health      = 8,
        damage      = 3,
        speed       = 4.0,
        scale       = 0.4,
        attackInterval = 0.5,
        color       = {0.5, 0.5, 0.6},
        minZone     = "shallows",  -- All playable depths (surface has no enemies)
        spawnWeight = 12,
        regeneration = 0,
    },
    angler = {
        id          = "angler",
        name        = "Angler",
        description = "Deep sea predator with lure. Slow but deadly.",
        health      = 50,
        damage      = 18,
        speed       = 1.0,
        scale       = 0.9,
        attackInterval = 2.0,
        color       = {0.2, 0.25, 0.35},
        minZone     = "mid",
        spawnWeight = 6,
        regeneration = 0,
    },
    pressure_beast = {
        id          = "pressure_beast",
        name        = "Pressure Beast",
        description = "Tough armored creature. Very slow, very tough.",
        health      = 80,
        damage      = 15,
        speed       = 0.8,
        scale       = 1.0,
        attackInterval = 2.5,
        color       = {0.4, 0.35, 0.3},
        minZone     = "deep",
        spawnWeight = 4,
        regeneration = 0,
    },
    leviathan = {
        id          = "leviathan",
        name        = "Leviathan",
        description = "Boss creature. Huge, devastating.",
        health      = 150,
        damage      = 25,
        speed       = 1.2,
        scale       = 1.2,
        attackInterval = 3.0,
        color       = {0.15, 0.2, 0.3},
        minZone     = "deep",
        spawnWeight = 1,  -- Very rare
        regeneration = 0,
    },
    abyssal = {
        id          = "abyssal",
        name        = "Abyssal",
        description = "Void creature from the deep. Fast, corrupting.",
        health      = 60,
        damage      = 20,
        speed       = 2.5,
        scale       = 0.8,
        attackInterval = 1.5,
        color       = {0.2, 0.1, 0.3},
        minZone     = "abyss",
        spawnWeight = 5,
        regeneration = 0,
    },
    hydra = {
        id          = "hydra",
        name        = "Hydra",
        description = "Multi-headed serpent. Regenerates.",
        health      = 100,
        damage      = 22,
        speed       = 1.5,
        scale       = 1.1,
        attackInterval = 2.0,
        color       = {0.1, 0.3, 0.25},
        minZone     = "trench",
        spawnWeight = 2,
        regeneration = 2, -- HP per second
    },
}

-- Ordered list of type IDs for iteration
local TYPE_IDS = {
    "crawler", "lurker", "swarm", "angler",
    "pressure_beast", "leviathan", "abyssal", "hydra",
}

-- ============================================================================
--                        INITIALISATION
-- ============================================================================

function Enemies.init()
    textureCache = {}
    activeEnemies = {}
end

-- ============================================================================
--                        TYPE QUERIES
-- ============================================================================

--- Get a single enemy type definition by its id string.
--- Returns nil if the typeId is not recognised.
function Enemies.getType(typeId)
    return Enemies.TYPES[typeId]
end

--- Resolve the short zone name for a given floor number.
--- Requires the Depth module to be passed in so we avoid a hard require.
--- If Depth is nil, falls back to "shallows".
local function resolveZone(depthFloor, Depth)
    if not Depth then return "shallows" end
    local zone = Depth.getZoneForFloor(depthFloor)
    if not zone then return "shallows" end
    local shortName = ZONE_NAME_MAP[zone.name]
    return shortName or "shallows"
end

--- Get all enemy types that are eligible to spawn at a given depth floor.
--- depthFloor is the 1-based floor number.
--- Optionally pass the Depth module for accurate zone lookup; if nil,
--- the function treats all floors as "shallows".
function Enemies.getTypesForDepth(depthFloor, Depth)
    local zoneName = resolveZone(depthFloor, Depth)
    local zoneRank = ZONE_RANK[zoneName] or 2  -- default to shallows rank

    local eligible = {}
    for _, typeId in ipairs(TYPE_IDS) do
        local def = Enemies.TYPES[typeId]
        local minRank = ZONE_RANK[def.minZone] or 2
        if zoneRank >= minRank then
            eligible[#eligible + 1] = def
        end
    end
    return eligible
end

-- ============================================================================
--                        DIFFICULTY SCALING
-- ============================================================================

--- Return a stat multiplier based on depth floor.
--- Deeper floors scale enemy stats up.
--- Floor 1 = 1.0x, scaling smoothly upward.
--- If a Depth module is provided, uses its enemyDifficulty; otherwise
--- uses a simple linear formula.
function Enemies.getDifficultyMultiplier(depthFloor, Depth)
    if Depth and Depth.getEnemyDifficulty then
        local diff = Depth.getEnemyDifficulty(depthFloor)
        -- Depth returns 0 for surface; clamp to at least 0.5 so enemies
        -- are never trivially zero-stat.
        return math_max(0.5, diff)
    end
    -- Fallback linear scaling: floor 1 = 1.0, floor 6 = 2.0
    depthFloor = depthFloor or 1
    return 1.0 + (depthFloor - 1) * 0.2
end

--- Return the number of seconds between enemy waves at a given depth.
--- Shallower = longer intervals, deeper = shorter (more dangerous).
function Enemies.getSpawnInterval(depthFloor)
    depthFloor = depthFloor or 1
    -- Base 30s at floor 1, decreasing by 3s per floor, min 10s
    local interval = 30 - (depthFloor - 1) * 3
    return math_max(10, interval)
end

-- ============================================================================
--                    PROCEDURAL TEXTURE GENERATION
-- ============================================================================

--- Create a LOVE Image texture for a given enemy type definition.
--- Uses the same pixel-art approach as sprites.lua (64x64 ImageData).
--- Each creature type gets a distinct silhouette built from simple shapes.
function Enemies.createTexture(enemyType)
    if not enemyType then return nil end

    -- Return cached texture if already generated
    if textureCache[enemyType.id] then
        return textureCache[enemyType.id]
    end

    local size = 64
    local imageData = love.image.newImageData(size, size)
    local r, g, b = enemyType.color[1], enemyType.color[2], enemyType.color[3]

    -- Dispatch to per-type generator
    if enemyType.id == "crawler" then
        Enemies._genCrawler(imageData, size, r, g, b)
    elseif enemyType.id == "lurker" then
        Enemies._genLurker(imageData, size, r, g, b)
    elseif enemyType.id == "swarm" then
        Enemies._genSwarm(imageData, size, r, g, b)
    elseif enemyType.id == "angler" then
        Enemies._genAngler(imageData, size, r, g, b)
    elseif enemyType.id == "pressure_beast" then
        Enemies._genPressureBeast(imageData, size, r, g, b)
    elseif enemyType.id == "leviathan" then
        Enemies._genLeviathan(imageData, size, r, g, b)
    elseif enemyType.id == "abyssal" then
        Enemies._genAbyssal(imageData, size, r, g, b)
    elseif enemyType.id == "hydra" then
        Enemies._genHydra(imageData, size, r, g, b)
    else
        -- Fallback: simple coloured circle
        Enemies._genFallback(imageData, size, r, g, b)
    end

    local texture = love.graphics.newImage(imageData)
    texture:setFilter("nearest", "nearest")
    textureCache[enemyType.id] = texture
    return texture
end

-- Helper: clamp colour component
local function cc(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

-- Helper: distance between two points
local function dist(ax, ay, bx, by)
    local dx = ax - bx
    local dy = ay - by
    return math_sqrt(dx * dx + dy * dy)
end

-- ---- Crawler: low-slung crustacean body with legs and eyestalks ----
function Enemies._genCrawler(imageData, size, r, g, b)
    local half = size / 2
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local cx = x - half
            local cy = y - half
            local alpha = 0
            local pr, pg, pb = r, g, b

            -- Oval body (wider than tall, offset downward)
            local bodyY = size * 0.05
            local bodyRX = size * 0.3
            local bodyRY = size * 0.18
            local bx = cx / bodyRX
            local by = (cy - bodyY) / bodyRY
            local bodyDist = bx * bx + by * by

            if bodyDist < 1 then
                alpha = 1
                -- Shell shading
                local shade = 1.0 - bodyDist * 0.4
                pr = cc(r * shade + 0.1)
                pg = cc(g * shade)
                pb = cc(b * shade)
                -- Ridge lines across shell
                if math_abs(cy - bodyY) < 2 then
                    pr = cc(pr * 0.7)
                    pg = cc(pg * 0.7)
                    pb = cc(pb * 0.7)
                end
            end

            -- Legs (6 legs, 3 each side)
            for leg = 0, 2 do
                local legBaseX = -size * 0.22 + leg * size * 0.15
                local legTipX = legBaseX - size * 0.1
                local legBaseY = bodyY + bodyRY * 0.6
                local legTipY = legBaseY + size * 0.2 + leg * 3

                -- Left leg
                local dLeg = dist(cx, cy, (legBaseX + legTipX) / 2, (legBaseY + legTipY) / 2)
                if dLeg < size * 0.1 and cy > legBaseY then
                    alpha = 1
                    pr = cc(r * 0.6)
                    pg = cc(g * 0.6)
                    pb = cc(b * 0.6)
                end
                -- Right leg (mirror)
                dLeg = dist(cx, cy, -(legBaseX + legTipX) / 2, (legBaseY + legTipY) / 2)
                if dLeg < size * 0.1 and cy > legBaseY then
                    alpha = 1
                    pr = cc(r * 0.6)
                    pg = cc(g * 0.6)
                    pb = cc(b * 0.6)
                end
            end

            -- Claws (two pincers at front)
            local clawY = bodyY - bodyRY * 0.3
            for side = -1, 1, 2 do
                local clawCX = side * size * 0.28
                local clawD = dist(cx, cy, clawCX, clawY)
                if clawD < size * 0.08 then
                    alpha = 1
                    pr = cc(r * 1.2)
                    pg = cc(g * 0.8)
                    pb = cc(b * 0.7)
                end
                -- Pincer tips
                local tipD = dist(cx, cy, clawCX + side * size * 0.06, clawY - size * 0.04)
                if tipD < size * 0.04 then
                    alpha = 1
                    pr = cc(r * 1.3)
                    pg = cc(g * 0.6)
                    pb = cc(b * 0.5)
                end
            end

            -- Eyestalks (two small dots above body)
            for side = -1, 1, 2 do
                local eyeX = side * size * 0.1
                local eyeY = bodyY - bodyRY - size * 0.06
                local eyeD = dist(cx, cy, eyeX, eyeY)
                -- Stalk
                if math_abs(cx - eyeX) < 2 and cy > eyeY and cy < bodyY - bodyRY + 2 then
                    alpha = 1
                    pr = cc(r * 0.7)
                    pg = cc(g * 0.7)
                    pb = cc(b * 0.7)
                end
                -- Eye
                if eyeD < 3 then
                    alpha = 1
                    pr, pg, pb = 0.9, 0.8, 0.1
                end
            end

            if alpha > 0 then
                imageData:setPixel(x, y, pr, pg, pb, alpha)
            else
                imageData:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end
end

-- ---- Lurker: Sleek predatory fish ----
function Enemies._genLurker(imageData, size, r, g, b)
    local half = size / 2
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local cx = x - half
            local cy = y - half
            local alpha = 0
            local pr, pg, pb = r, g, b

            -- Torpedo-shaped body (tall oval)
            local bodyRX = size * 0.2
            local bodyRY = size * 0.38
            local bx = cx / bodyRX
            local by = cy / bodyRY
            local bodyDist = bx * bx + by * by

            if bodyDist < 1 then
                alpha = 1
                local shade = 1.0 - math_abs(cx) / bodyRX * 0.3
                pr = cc(r * shade)
                pg = cc(g * shade)
                pb = cc(b * shade)
                -- Lateral line
                if math_abs(cx) < 2 and cy > -size * 0.15 and cy < size * 0.2 then
                    pr = cc(pr + 0.15)
                    pg = cc(pg + 0.15)
                    pb = cc(pb + 0.1)
                end
            end

            -- Tail fin (V shape at bottom)
            local tailY = size * 0.35
            if cy > tailY and cy < tailY + size * 0.15 then
                local spread = (cy - tailY) / (size * 0.15) * size * 0.2
                if math_abs(cx) < spread and math_abs(cx) > spread * 0.3 then
                    alpha = 1
                    pr = cc(r * 0.7)
                    pg = cc(g * 0.7)
                    pb = cc(b * 0.7)
                end
            end

            -- Dorsal fin
            if cx > 0 and cx < size * 0.12 and cy > -size * 0.25 and cy < size * 0.05 then
                local finWidth = size * 0.12 * (1 - (cy + size * 0.25) / (size * 0.3))
                if cx < finWidth then
                    -- Only draw outside the body
                    local testBx = cx / bodyRX
                    local testBy = cy / bodyRY
                    if testBx * testBx + testBy * testBy >= 1 then
                        alpha = 1
                        pr = cc(r * 0.8)
                        pg = cc(g * 0.9)
                        pb = cc(b * 0.8)
                    end
                end
            end

            -- Side fins (pectoral)
            for side = -1, 1, 2 do
                local finCX = side * size * 0.18
                local finCY = size * 0.02
                local finD = dist(cx, cy, finCX, finCY)
                if finD < size * 0.1 and ((side < 0 and cx < finCX + size * 0.05) or (side > 0 and cx > finCX - size * 0.05)) then
                    local testBx2 = cx / bodyRX
                    local testBy2 = cy / bodyRY
                    if testBx2 * testBx2 + testBy2 * testBy2 >= 0.85 then
                        alpha = 1
                        pr = cc(r * 0.75)
                        pg = cc(g * 0.85)
                        pb = cc(b * 0.75)
                    end
                end
            end

            -- Eyes (on each side of head)
            for side = -1, 1, 2 do
                local eyeX = side * size * 0.1
                local eyeY = -size * 0.22
                local eyeD = dist(cx, cy, eyeX, eyeY)
                if eyeD < 3.5 then
                    alpha = 1
                    if eyeD < 1.5 then
                        pr, pg, pb = 0.05, 0.05, 0.05 -- pupil
                    else
                        pr, pg, pb = 0.8, 0.85, 0.4 -- iris
                    end
                end
            end

            -- Mouth line
            if math_abs(cx) < size * 0.08 and math_abs(cy + size * 0.34) < 2 then
                local testBx3 = cx / bodyRX
                local testBy3 = (cy) / bodyRY
                if testBx3 * testBx3 + testBy3 * testBy3 < 1.1 then
                    alpha = 1
                    pr, pg, pb = cc(r * 0.4), cc(g * 0.4), cc(b * 0.4)
                end
            end

            if alpha > 0 then
                imageData:setPixel(x, y, pr, pg, pb, alpha)
            else
                imageData:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end
end

-- ---- Swarm: cluster of tiny fish shapes ----
function Enemies._genSwarm(imageData, size, r, g, b)
    local half = size / 2
    -- Pre-define fish positions (7 tiny fish in a cloud)
    local fish = {
        {-8, -10, 4}, {5, -6, 3.5}, {-3, 0, 4}, {8, 3, 3},
        {-10, 5, 3.5}, {2, 8, 4}, {-5, -4, 3},
    }

    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local cx = x - half
            local cy = y - half
            local alpha = 0
            local pr, pg, pb = r, g, b

            for _, f in ipairs(fish) do
                local fx, fy, fr = f[1], f[2], f[3]
                -- Oval fish body
                local dx = (cx - fx) / (fr * 1.5)
                local dy = (cy - fy) / fr
                local d2 = dx * dx + dy * dy
                if d2 < 1 then
                    alpha = 1
                    local shade = 0.8 + (1 - d2) * 0.3
                    pr = cc(r * shade)
                    pg = cc(g * shade)
                    pb = cc(b * shade)
                    -- Tiny eye
                    local eyeD = dist(cx, cy, fx - fr * 0.5, fy - fr * 0.3)
                    if eyeD < 1.2 then
                        pr, pg, pb = 0.1, 0.1, 0.1
                    end
                end
                -- Tiny tail
                local tailX = fx + fr * 1.8
                local tailD = dist(cx, cy, tailX, fy)
                if tailD < fr * 0.7 and cx > fx + fr then
                    alpha = 1
                    pr = cc(r * 0.65)
                    pg = cc(g * 0.65)
                    pb = cc(b * 0.65)
                end
            end

            if alpha > 0 then
                imageData:setPixel(x, y, pr, pg, pb, alpha)
            else
                imageData:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end
end

-- ---- Angler: bulbous body with dangling lure ----
function Enemies._genAngler(imageData, size, r, g, b)
    local half = size / 2
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local cx = x - half
            local cy = y - half
            local alpha = 0
            local pr, pg, pb = r, g, b

            -- Large bulbous body (lower center)
            local bodyCY = size * 0.08
            local bodyR = size * 0.3
            local bodyD = dist(cx, cy, 0, bodyCY)

            if bodyD < bodyR then
                alpha = 1
                local shade = 1.0 - bodyD / bodyR * 0.4
                pr = cc(r * shade)
                pg = cc(g * shade)
                pb = cc(b * shade)
                -- Belly lighter
                if cy > bodyCY then
                    pr = cc(pr + 0.08)
                    pg = cc(pg + 0.08)
                    pb = cc(pb + 0.05)
                end
            end

            -- Giant mouth (lower front of body)
            local mouthY = bodyCY + bodyR * 0.4
            if cy > mouthY - 4 and cy < mouthY + 6 and math_abs(cx) < bodyR * 0.6 then
                if bodyD < bodyR * 1.05 then
                    alpha = 1
                    pr, pg, pb = 0.08, 0.02, 0.02 -- dark maw
                    -- Teeth
                    local toothSpacing = 5
                    local toothIdx = math_floor((cx + half) / toothSpacing)
                    if toothIdx % 2 == 0 and (math_abs(cy - mouthY + 2) < 3 or math_abs(cy - mouthY - 3) < 3) then
                        pr, pg, pb = 0.85, 0.85, 0.8
                    end
                end
            end

            -- Lure stalk (curved line going up from head)
            local stalkBaseY = bodyCY - bodyR * 0.7
            local stalkTopY = -size * 0.4
            if cy > stalkTopY and cy < stalkBaseY then
                local t = (cy - stalkTopY) / (stalkBaseY - stalkTopY)
                local stalkX = math_sin(t * math_pi * 0.5) * size * 0.12
                if math_abs(cx - stalkX) < 1.5 then
                    alpha = 1
                    pr = cc(r * 0.5)
                    pg = cc(g * 0.5)
                    pb = cc(b * 0.5)
                end
            end

            -- Lure bulb (glowing orb at tip)
            local lureX = math_sin(0.5 * math_pi * 0.5) * size * 0.12
            local lureY = stalkTopY
            local lureD = dist(cx, cy, lureX, lureY)
            if lureD < size * 0.06 then
                alpha = 1
                local glow = 1 - lureD / (size * 0.06)
                pr = cc(0.4 + glow * 0.6)
                pg = cc(0.8 + glow * 0.2)
                pb = cc(0.5 + glow * 0.5)
            end
            -- Lure glow halo
            if lureD < size * 0.1 and lureD >= size * 0.06 then
                local haloAlpha = (1 - (lureD - size * 0.06) / (size * 0.04)) * 0.35
                if haloAlpha > 0 then
                    -- Blend with existing pixel or set new
                    alpha = math_max(alpha, haloAlpha)
                    pr = cc(0.3 + 0.4 * haloAlpha)
                    pg = cc(0.7 + 0.2 * haloAlpha)
                    pb = cc(0.4 + 0.3 * haloAlpha)
                end
            end

            -- Small beady eyes
            for side = -1, 1, 2 do
                local eyeX = side * bodyR * 0.35
                local eyeY = bodyCY - bodyR * 0.3
                local eyeD = dist(cx, cy, eyeX, eyeY)
                if eyeD < 2.5 then
                    alpha = 1
                    pr, pg, pb = 0.7, 0.15, 0.1
                end
            end

            -- Small side fins
            for side = -1, 1, 2 do
                local finX = side * bodyR * 0.85
                local finY = bodyCY + bodyR * 0.1
                local finD = dist(cx, cy, finX, finY)
                if finD < size * 0.07 then
                    local testD = dist(cx, cy, 0, bodyCY)
                    if testD >= bodyR * 0.9 then
                        alpha = 1
                        pr = cc(r * 0.6)
                        pg = cc(g * 0.6)
                        pb = cc(b * 0.7)
                    end
                end
            end

            if alpha > 0 then
                imageData:setPixel(x, y, pr, pg, pb, alpha)
            else
                imageData:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end
end

-- ---- Pressure Beast: armored, bulky, segmented ----
function Enemies._genPressureBeast(imageData, size, r, g, b)
    local half = size / 2
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local cx = x - half
            local cy = y - half
            local alpha = 0
            local pr, pg, pb = r, g, b

            -- Main body: rounded rectangle/tank shape
            local bodyW = size * 0.35
            local bodyH = size * 0.4
            local bodyY = size * 0.02

            if math_abs(cx) < bodyW and math_abs(cy - bodyY) < bodyH then
                -- Rounded corners
                local cornerR = size * 0.1
                local inCorner = false
                if math_abs(cx) > bodyW - cornerR and math_abs(cy - bodyY) > bodyH - cornerR then
                    local cornerX = (math_abs(cx) - (bodyW - cornerR))
                    local cornerY = (math_abs(cy - bodyY) - (bodyH - cornerR))
                    if cornerX * cornerX + cornerY * cornerY > cornerR * cornerR then
                        inCorner = true
                    end
                end

                if not inCorner then
                    alpha = 1
                    -- Armour plate shading with horizontal segments
                    local segment = math_floor((cy - bodyY + bodyH) / (size * 0.1))
                    local segShade = (segment % 2 == 0) and 1.0 or 0.85
                    local edgeShade = 1 - math_abs(cx) / bodyW * 0.25
                    pr = cc(r * segShade * edgeShade)
                    pg = cc(g * segShade * edgeShade)
                    pb = cc(b * segShade * edgeShade)
                    -- Plate ridge highlights
                    local ridgeY = (cy - bodyY + bodyH) % (size * 0.1)
                    if ridgeY < 1.5 then
                        pr = cc(pr + 0.12)
                        pg = cc(pg + 0.1)
                        pb = cc(pb + 0.08)
                    end
                end
            end

            -- Head (small dome on top)
            local headY = bodyY - bodyH - size * 0.02
            local headR = size * 0.14
            local headD = dist(cx, cy, 0, headY)
            if headD < headR then
                alpha = 1
                local shade = 1 - headD / headR * 0.3
                pr = cc(r * shade * 1.1)
                pg = cc(g * shade * 1.1)
                pb = cc(b * shade * 0.9)
            end

            -- Eyes (small, armored slits)
            for side = -1, 1, 2 do
                local eyeX = side * headR * 0.5
                local eyeY = headY + headR * 0.1
                if math_abs(cx - eyeX) < 3 and math_abs(cy - eyeY) < 1.5 then
                    alpha = 1
                    pr, pg, pb = 0.7, 0.5, 0.1
                end
            end

            -- Stubby legs (4 legs, two per side)
            for legIdx = 0, 1 do
                local legY = bodyY + bodyH * 0.3 + legIdx * size * 0.15
                for side = -1, 1, 2 do
                    local legX = side * (bodyW + size * 0.04)
                    if math_abs(cx - legX) < size * 0.06 and cy > legY and cy < legY + size * 0.12 then
                        alpha = 1
                        pr = cc(r * 0.65)
                        pg = cc(g * 0.6)
                        pb = cc(b * 0.55)
                    end
                end
            end

            if alpha > 0 then
                imageData:setPixel(x, y, pr, pg, pb, alpha)
            else
                imageData:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end
end

-- ---- Leviathan: massive serpentine boss ----
function Enemies._genLeviathan(imageData, size, r, g, b)
    local half = size / 2
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local cx = x - half
            local cy = y - half
            local alpha = 0
            local pr, pg, pb = r, g, b

            -- Massive head (top portion)
            local headY = -size * 0.15
            local headRX = size * 0.32
            local headRY = size * 0.22
            local hx = cx / headRX
            local hy = (cy - headY) / headRY
            local headD = hx * hx + hy * hy

            if headD < 1 then
                alpha = 1
                local shade = 1.0 - headD * 0.35
                pr = cc(r * shade)
                pg = cc(g * shade)
                pb = cc(b * shade)
                -- Brow ridge
                if cy < headY and math_abs(cy - headY + headRY * 0.5) < 3 then
                    pr = cc(pr * 0.7)
                    pg = cc(pg * 0.7)
                    pb = cc(pb * 0.7)
                end
            end

            -- Jaw (below head, wider)
            local jawY = headY + headRY * 0.8
            local jawRX = headRX * 1.1
            local jawRY = headRY * 0.5
            local jx = cx / jawRX
            local jy = (cy - jawY) / jawRY
            local jawD = jx * jx + jy * jy
            if jawD < 1 and cy > headY then
                alpha = 1
                pr = cc(r * 0.85)
                pg = cc(g * 0.85)
                pb = cc(b * 0.85)
                -- Mouth interior
                if math_abs(cx) < jawRX * 0.7 and cy > jawY - jawRY * 0.2 and cy < jawY + jawRY * 0.5 then
                    pr, pg, pb = 0.12, 0.04, 0.06
                    -- Teeth
                    local toothI = math_floor((cx + half) / 4)
                    if toothI % 2 == 0 and math_abs(cy - jawY + jawRY * 0.15) < 3 then
                        pr, pg, pb = 0.8, 0.8, 0.75
                    end
                end
            end

            -- Body/neck (below jaw, tapering)
            local neckTop = jawY + jawRY * 0.7
            if cy > neckTop and cy < size * 0.48 then
                local t = (cy - neckTop) / (size * 0.48 - neckTop)
                local neckW = headRX * (1 - t * 0.4)
                if math_abs(cx) < neckW then
                    alpha = 1
                    local shade = 0.9 - t * 0.2
                    pr = cc(r * shade)
                    pg = cc(g * shade)
                    pb = cc(b * shade)
                    -- Scale pattern
                    local scaleRow = math_floor(cy / 5)
                    local scaleCol = math_floor(cx / 5)
                    if (scaleRow + scaleCol) % 2 == 0 then
                        pr = cc(pr + 0.05)
                        pg = cc(pg + 0.05)
                        pb = cc(pb + 0.05)
                    end
                end
            end

            -- Glowing eyes (large, menacing)
            for side = -1, 1, 2 do
                local eyeX = side * headRX * 0.45
                local eyeY = headY - headRY * 0.05
                local eyeR = size * 0.06
                local eyeD = dist(cx, cy, eyeX, eyeY)
                if eyeD < eyeR then
                    alpha = 1
                    local glow = 1 - eyeD / eyeR
                    pr = cc(0.3 + glow * 0.7)
                    pg = cc(0.6 + glow * 0.3)
                    pb = cc(0.2 + glow * 0.2)
                    -- Slit pupil
                    if math_abs(cx - eyeX) < 1.2 then
                        pr, pg, pb = 0.05, 0.1, 0.05
                    end
                end
            end

            -- Horn/crest ridges
            for side = -1, 1, 2 do
                local hornBaseX = side * headRX * 0.6
                local hornBaseY = headY - headRY * 0.6
                local hornTipX = side * headRX * 0.9
                local hornTipY = headY - headRY * 1.2
                -- Simple line approximation
                local hornLen = dist(hornBaseX, hornBaseY, hornTipX, hornTipY)
                local hnx = (hornTipX - hornBaseX) / hornLen
                local hny = (hornTipY - hornBaseY) / hornLen
                local projLen = (cx - hornBaseX) * hnx + (cy - hornBaseY) * hny
                if projLen > 0 and projLen < hornLen then
                    local perpDist = math_abs((cx - hornBaseX) * (-hny) + (cy - hornBaseY) * hnx)
                    local taper = 2.5 * (1 - projLen / hornLen)
                    if perpDist < taper + 0.5 then
                        alpha = 1
                        pr = cc(r * 0.5 + 0.2)
                        pg = cc(g * 0.5 + 0.15)
                        pb = cc(b * 0.5 + 0.1)
                    end
                end
            end

            if alpha > 0 then
                imageData:setPixel(x, y, pr, pg, pb, alpha)
            else
                imageData:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end
end

-- ---- Abyssal: ethereal void creature ----
function Enemies._genAbyssal(imageData, size, r, g, b)
    local half = size / 2
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local cx = x - half
            local cy = y - half
            local alpha = 0
            local pr, pg, pb = r, g, b

            -- Central body (wispy, slightly transparent)
            local bodyR = size * 0.22
            local bodyD = dist(cx, cy, 0, 0)

            if bodyD < bodyR then
                local t = bodyD / bodyR
                alpha = 1 - t * 0.3
                local shade = 1 - t * 0.5
                pr = cc(r * shade)
                pg = cc(g * shade)
                pb = cc(b * shade + 0.15 * (1 - t))
            end

            -- Wispy tendrils (6 tendrils radiating outward)
            for i = 0, 5 do
                local angle = i * math_pi / 3 + math_pi * 0.15
                local tendrilLen = size * 0.35
                for t = 0, 1, 0.02 do
                    local wobble = math_sin(t * math_pi * 3 + i * 1.5) * size * 0.04
                    local tx = math_cos(angle) * t * tendrilLen + math_sin(angle) * wobble
                    local ty = math_sin(angle) * t * tendrilLen - math_cos(angle) * wobble
                    local td = dist(cx, cy, tx, ty)
                    local thickness = (1 - t) * 3.5 + 0.5
                    if td < thickness then
                        local tendrilAlpha = (1 - t) * 0.9
                        if tendrilAlpha > alpha then
                            alpha = tendrilAlpha
                            pr = cc(r * 0.7 + 0.1 * t)
                            pg = cc(g * 0.5)
                            pb = cc(b + 0.3 * (1 - t))
                        end
                    end
                end
            end

            -- Central glowing eye
            local eyeR = size * 0.08
            local eyeD = dist(cx, cy, 0, -size * 0.04)
            if eyeD < eyeR then
                alpha = 1
                local glow = 1 - eyeD / eyeR
                pr = cc(0.5 + glow * 0.5)
                pg = cc(0.1 + glow * 0.2)
                pb = cc(0.7 + glow * 0.3)
                -- Pupil
                if eyeD < eyeR * 0.35 then
                    pr = cc(0.9)
                    pg = cc(0.1)
                    pb = cc(1.0)
                end
            end

            -- Void particles (small bright dots scattered around)
            -- Use deterministic positions based on pixel coords for consistency
            local px = (x * 7 + y * 13) % 97
            if px < 4 and bodyD > bodyR * 0.5 and bodyD < size * 0.42 then
                alpha = math_max(alpha, 0.8)
                pr = cc(0.6)
                pg = cc(0.3)
                pb = cc(0.9)
            end

            if alpha > 0 then
                imageData:setPixel(x, y, pr, pg, pb, alpha)
            else
                imageData:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end
end

-- ---- Hydra: multi-headed serpent ----
function Enemies._genHydra(imageData, size, r, g, b)
    local half = size / 2
    -- Pre-define 3 head positions (branching from a shared neck)
    local heads = {
        {offsetX = 0,          offsetY = -size * 0.35, headR = size * 0.09},
        {offsetX = -size * 0.18, offsetY = -size * 0.28, headR = size * 0.08},
        {offsetX = size * 0.18,  offsetY = -size * 0.28, headR = size * 0.08},
    }

    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local cx = x - half
            local cy = y - half
            local alpha = 0
            local pr, pg, pb = r, g, b

            -- Main body (lower center, thick)
            local bodyTop = -size * 0.05
            local bodyBot = size * 0.42
            local bodyW = size * 0.25
            if cy > bodyTop and cy < bodyBot and math_abs(cx) < bodyW then
                local edgeFade = 1 - math_abs(cx) / bodyW * 0.3
                alpha = 1
                -- Scales pattern
                local scaleR = math_floor(cy / 4)
                local scaleC = math_floor((cx + half) / 4)
                local scaleShade = ((scaleR + scaleC) % 2 == 0) and 1.0 or 0.88
                pr = cc(r * edgeFade * scaleShade)
                pg = cc(g * edgeFade * scaleShade)
                pb = cc(b * edgeFade * scaleShade)
            end

            -- Neck branches (from body top to each head)
            local neckOriginY = bodyTop
            for _, head in ipairs(heads) do
                local hx, hy = head.offsetX, head.offsetY
                -- Neck is a thick line from (0, neckOriginY) to (hx, hy)
                local neckLen = dist(0, neckOriginY, hx, hy)
                if neckLen > 0 then
                    local nnx = (hx - 0) / neckLen
                    local nny = (hy - neckOriginY) / neckLen
                    local projLen = cx * nnx + (cy - neckOriginY) * nny
                    if projLen > 0 and projLen < neckLen then
                        local perpDist = math_abs(cx * (-nny) + (cy - neckOriginY) * nnx)
                        local taper = size * 0.06 * (1 - projLen / neckLen * 0.4)
                        if perpDist < taper then
                            alpha = 1
                            local shade = 0.9 - projLen / neckLen * 0.2
                            pr = cc(r * shade)
                            pg = cc(g * shade * 1.1)
                            pb = cc(b * shade)
                        end
                    end
                end
            end

            -- Heads
            for _, head in ipairs(heads) do
                local hx, hy, hr = head.offsetX, head.offsetY, head.headR
                local headD = dist(cx, cy, hx, hy)
                if headD < hr then
                    alpha = 1
                    local shade = 1 - headD / hr * 0.3
                    pr = cc(r * shade * 1.1)
                    pg = cc(g * shade * 1.2)
                    pb = cc(b * shade)
                    -- Mouth
                    if cy > hy and math_abs(cx - hx) < hr * 0.5 and cy < hy + hr * 0.8 then
                        pr = cc(0.15)
                        pg = cc(0.05)
                        pb = cc(0.08)
                    end
                end
                -- Eyes on each head
                local eyeD = dist(cx, cy, hx, hy - hr * 0.35)
                if eyeD < 2.5 then
                    alpha = 1
                    pr, pg, pb = 0.8, 0.9, 0.2
                end
            end

            -- Tail (extending below body, tapering)
            if cy > bodyBot and cy < bodyBot + size * 0.08 then
                local t = (cy - bodyBot) / (size * 0.08)
                local tailW = bodyW * (1 - t * 0.8)
                if math_abs(cx) < tailW then
                    alpha = 1
                    pr = cc(r * (0.8 - t * 0.3))
                    pg = cc(g * (0.8 - t * 0.3))
                    pb = cc(b * (0.7 - t * 0.2))
                end
            end

            if alpha > 0 then
                imageData:setPixel(x, y, pr, pg, pb, alpha)
            else
                imageData:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end
end

-- ---- Fallback: simple coloured circle ----
function Enemies._genFallback(imageData, size, r, g, b)
    local half = size / 2
    local radius = size * 0.35
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local d = dist(x, y, half, half)
            if d < radius then
                local shade = 1 - d / radius * 0.4
                imageData:setPixel(x, y, cc(r * shade), cc(g * shade), cc(b * shade), 1)
            else
                imageData:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end
end

-- ============================================================================
--                          SPAWNING
-- ============================================================================

--- Register a generated texture in the Sprites system's texture table
--- so that the sprite renderer can find it by name.
local function ensureTexture(enemyType, Sprites)
    local texName = "enemy_" .. enemyType.id
    if not Sprites.getTexture(texName) then
        local tex = Enemies.createTexture(enemyType)
        if tex then
            -- sprites.lua stores textures in a local table accessed via getTexture.
            -- We cannot write to it directly. Instead, we pass the texture name
            -- in the spawn data and store the texture so we can hand it back.
            -- The sprite renderer falls back to spriteTextures.npc if the name
            -- is not found; to avoid that we will store in the cache and rely
            -- on the enemy rendering using the generated texture directly.
            -- We will keep our own lookup and the spawn data uses a known
            -- texture name from sprites.lua ("enemy") as the base, but sets
            -- the texture field.
        end
    end
    return texName
end

--- Spawn a single enemy of the given typeId at world position (x, y).
--- Sprites: the Sprites module (required).
--- Depth: the Depth module (optional, used for difficulty scaling).
--- Returns the sprite id, or nil on failure.
function Enemies.spawnEnemy(typeId, x, y, Sprites, Depth, depthFloor)
    local enemyType = Enemies.TYPES[typeId]
    if not enemyType then
        print("[Enemies] Warning: unknown enemy type '" .. tostring(typeId) .. "'")
        return nil
    end
    if not Sprites then
        print("[Enemies] Warning: Sprites module is nil, cannot spawn enemy")
        return nil
    end

    -- Compute difficulty multiplier
    local mult = 1.0
    if depthFloor then
        mult = Enemies.getDifficultyMultiplier(depthFloor, Depth)
    end

    -- Generate texture if needed (cached after first call)
    local texName = "enemy_" .. enemyType.id
    Enemies.createTexture(enemyType)

    -- Compute scaled stats
    local scaledHealth = math_floor(enemyType.health * mult + 0.5)
    local scaledDamage = math_floor(enemyType.damage * mult + 0.5)
    local scaledSpeed  = enemyType.speed -- speed not scaled by difficulty

    local spriteId = Sprites.add(x, y, "enemy", {
        name    = enemyType.name,
        scale   = enemyType.scale,
        health  = scaledHealth,
        damage  = scaledDamage,
        speed   = scaledSpeed,
        texture = "enemy",  -- base enemy texture from sprites.lua
    })

    if spriteId then
        -- Track for regeneration system
        activeEnemies[spriteId] = {
            typeId = typeId,
            regenAccum = 0,
        }

        -- Override the sprite's texture with our procedurally generated one
        local allSprites = Sprites.getAll()
        local sprite = allSprites[spriteId]
        if sprite then
            sprite.attackCooldown = enemyType.attackInterval
            -- Store type info for external queries
            sprite.enemyTypeId = typeId
        end
    end

    return spriteId
end

--- Pick a weighted-random enemy type from a list of eligible types.
local function pickWeightedType(eligibleTypes)
    local totalWeight = 0
    for _, def in ipairs(eligibleTypes) do
        totalWeight = totalWeight + def.spawnWeight
    end
    if totalWeight <= 0 then return nil end

    local roll = math_random() * totalWeight
    local cumulative = 0
    for _, def in ipairs(eligibleTypes) do
        cumulative = cumulative + def.spawnWeight
        if roll <= cumulative then
            return def
        end
    end
    -- Fallback (floating-point edge case)
    return eligibleTypes[#eligibleTypes]
end

--- Get a random walkable position inside a room.
--- Room has {x1, y1, x2, y2} with walls on the edges.
local function getRandomPosInRoom(room)
    local innerW = room.x2 - room.x1 - 2
    local innerH = room.y2 - room.y1 - 2
    if innerW < 1 then innerW = 1 end
    if innerH < 1 then innerH = 1 end
    local x = room.x1 + 1 + math_random(innerW)
    local y = room.y1 + 1 + math_random(innerH)
    return x + 0.5, y + 0.5
end

--- Validate that a position is walkable on the map.
local function isWalkable(map, tx, ty)
    if not map or not map.getTile then return true end
    local tile = map:getTile(tx, ty)
    return tile == 0 or tile == 10 or tile == 11 or tile == 12
end

--- Spawn a wave of enemies distributed across random rooms.
--- depthFloor: the current floor number (for difficulty and type selection).
--- count: how many enemies to spawn.
--- rooms: array of room tables {x1, y1, x2, y2, ...}. If nil or empty, no spawn occurs.
--- Sprites: the Sprites module.
--- map: the Map object (for walkability checks).
--- Depth: the Depth module (optional).
--- Returns a table of spawned sprite IDs.
function Enemies.spawnWave(depthFloor, count, rooms, Sprites, map, Depth)
    local spawned = {}
    if not rooms or #rooms == 0 then return spawned end
    if not Sprites then return spawned end
    if count <= 0 then return spawned end

    local eligibleTypes = Enemies.getTypesForDepth(depthFloor, Depth)
    if #eligibleTypes == 0 then return spawned end

    for i = 1, count do
        local room = rooms[math_random(#rooms)]
        local enemyDef = pickWeightedType(eligibleTypes)
        if room and enemyDef then
            local x, y = getRandomPosInRoom(room)
            -- Verify walkability
            local tx = math_floor(x)
            local ty = math_floor(y)
            if isWalkable(map, tx, ty) then
                local spriteId = Enemies.spawnEnemy(enemyDef.id, x, y, Sprites, Depth, depthFloor)
                if spriteId then
                    spawned[#spawned + 1] = spriteId
                end
            end
        end
    end

    return spawned
end

-- ============================================================================
--                     REGENERATION UPDATE
-- ============================================================================

--- Call each frame to tick health regeneration for Hydra-type enemies.
--- Sprites: the Sprites module (to access sprite health).
function Enemies.update(dt, Sprites)
    if not Sprites then return end
    local allSprites = Sprites.getAll()

    -- Iterate tracked enemies; clean up dead/removed ones
    local toRemove = {}
    for spriteId, info in pairs(activeEnemies) do
        local sprite = allSprites[spriteId]
        if not sprite or (sprite.health and sprite.health <= 0) then
            toRemove[#toRemove + 1] = spriteId
        else
            local def = Enemies.TYPES[info.typeId]
            if def and def.regeneration and def.regeneration > 0 and sprite.health then
                -- Accumulate fractional regen
                info.regenAccum = info.regenAccum + def.regeneration * dt
                if info.regenAccum >= 1 then
                    local heal = math_floor(info.regenAccum)
                    info.regenAccum = info.regenAccum - heal
                    sprite.health = math_min(sprite.health + heal, sprite.maxHealth or sprite.health)
                end
            end
        end
    end

    for _, spriteId in ipairs(toRemove) do
        activeEnemies[spriteId] = nil
    end
end

-- ============================================================================
--                        TEXTURE ACCESS
-- ============================================================================

--- Get the cached texture for a given enemy type id.
--- Returns nil if the texture has not been generated yet.
function Enemies.getTexture(typeId)
    return textureCache[typeId]
end

--- Pre-generate all enemy textures. Call during init/load.
function Enemies.generateAllTextures()
    for _, typeId in ipairs(TYPE_IDS) do
        Enemies.createTexture(Enemies.TYPES[typeId])
    end
end

-- ============================================================================
--                        QUERY HELPERS
-- ============================================================================

--- Get the list of all type IDs in definition order.
function Enemies.getTypeIds()
    return TYPE_IDS
end

--- Get count of currently tracked active enemies.
function Enemies.getActiveCount()
    local count = 0
    for _ in pairs(activeEnemies) do
        count = count + 1
    end
    return count
end

--- Clear all tracked enemy state (call on map/floor change).
function Enemies.clearActive()
    activeEnemies = {}
end

return Enemies
