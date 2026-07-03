--[[
    Sprite System
    Handles billboarded sprites (NPCs, items, decorations)
    Sprites always face the player (2.5D style like Doom)
    Includes item pickup system
]]

local Sprites = {}

-- Sprite types
Sprites.TYPE = {
    NPC = "npc",
    ENEMY = "enemy",
    ITEM = "item",
    DECORATION = "decoration",
}

-- Item definitions
Sprites.ITEMS = {
    health_potion = {
        name = "Health Potion",
        texture = "health_potion",
        value = 25,
        stat = "health",
        color = {1, 0.3, 0.3},
    },
    mana_potion = {
        name = "Mana Potion",
        texture = "mana_potion",
        value = 20,
        stat = "mana",
        color = {0.3, 0.3, 1},
    },
    gold = {
        name = "Gold Coins",
        texture = "gold",
        value = 10,
        stat = "gold",
        color = {1, 0.85, 0.2},
    },
    key = {
        name = "Dungeon Key",
        texture = "key",
        value = 1,
        stat = "keys",
        color = {0.8, 0.7, 0.2},
    },
    sword = {
        name = "Iron Sword",
        texture = "sword",
        value = 5,
        stat = "attack",
        color = {0.7, 0.7, 0.8},
    },
    gem = {
        name = "Magic Gem",
        texture = "gem",
        value = 50,
        stat = "gold",
        color = {0.8, 0.2, 0.8},
    },
    -- Underwater resource items (mined from walls)
    scrap_metal = {
        name = "Scrap Metal",
        texture = "gold",  -- reuse existing texture
        value = 1,
        stat = "scrap_metal",
        color = {0.6, 0.55, 0.5},
    },
    crystal = {
        name = "Crystal",
        texture = "gem",
        value = 1,
        stat = "crystal",
        color = {0.4, 0.7, 0.9},
    },
    biomass = {
        name = "Biomass",
        texture = "health_potion",
        value = 1,
        stat = "biomass",
        color = {0.3, 0.7, 0.4},
    },
    electronics = {
        name = "Electronics",
        texture = "key",
        value = 1,
        stat = "electronics",
        color = {0.8, 0.7, 0.3},
    },
    titanium = {
        name = "Titanium",
        texture = "sword",
        value = 1,
        stat = "titanium",
        color = {0.7, 0.75, 0.8},
    },
    -- Crafted materials
    composite = {
        name = "Composite",
        texture = "gold",
        value = 1,
        stat = "composite",
        color = {0.55, 0.6, 0.65},
    },
    circuit_board = {
        name = "Circuit Board",
        texture = "key",
        value = 1,
        stat = "circuit_board",
        color = {0.2, 0.6, 0.3},
    },
    biofilter = {
        name = "Biofilter",
        texture = "health_potion",
        value = 1,
        stat = "biofilter",
        color = {0.35, 0.65, 0.5},
    },
    -- Depth-specific resources (found as pickups in deeper biomes)
    coral = {
        name = "Coral Fragment",
        texture = "gem",
        value = 1,
        stat = "coral",
        color = {0.9, 0.4, 0.5},
    },
    rare_minerals = {
        name = "Rare Minerals",
        texture = "gem",
        value = 1,
        stat = "rare_minerals",
        color = {0.6, 0.3, 0.8},
    },
    bioluminescent_flora = {
        name = "Bioluminescent Flora",
        texture = "health_potion",
        value = 1,
        stat = "bioluminescent_flora",
        color = {0.2, 0.9, 0.7},
    },
    pressure_crystals = {
        name = "Pressure Crystal",
        texture = "gem",
        value = 1,
        stat = "pressure_crystals",
        color = {0.5, 0.4, 0.95},
    },
    abyssal_ore = {
        name = "Abyssal Ore",
        texture = "sword",
        value = 1,
        stat = "abyssal_ore",
        color = {0.2, 0.15, 0.4},
    },
    -- Consumables
    ration_pack = {
        name = "Ration Pack",
        texture = "health_potion",
        value = 1,
        stat = "ration_pack",
        color = {0.7, 0.5, 0.3},
    },
    med_pack = {
        name = "Med Pack",
        texture = "health_potion",
        value = 1,
        stat = "med_pack",
        color = {0.9, 0.3, 0.3},
    },
    o2_canister = {
        name = "O2 Canister",
        texture = "mana_potion",
        value = 1,
        stat = "o2_canister",
        color = {0.3, 0.6, 0.9},
    },
    repair_kit = {
        name = "Repair Kit",
        texture = "gold",
        value = 1,
        stat = "repair_kit",
        color = {0.6, 0.6, 0.3},
    },
}

-- Active sprites
local sprites = {}
local spriteTextures = {}
local pickupCallbacks = {}
local playerSpriteId = nil  -- ID of the player sprite (for third-person view)
local nextSpriteId = 1      -- Monotonically increasing ID counter (avoids sparse table issues)

-- Pickup settings
local PICKUP_RADIUS = 1.5  -- How close player needs to be to auto-collect
local ITEM_BOB_SPEED = 3   -- Bobbing animation speed
local ITEM_BOB_HEIGHT = 5  -- Bobbing pixels

function Sprites.init()
    sprites = {}
    pickupCallbacks = {}
    nextSpriteId = 1
    Sprites.generateTextures()
end

-- Register a callback for when items are picked up
function Sprites.onPickup(callback)
    table.insert(pickupCallbacks, callback)
end

-- Clear pickup callbacks
function Sprites.clearCallbacks()
    pickupCallbacks = {}
end

-- Generate simple sprite textures
function Sprites.generateTextures()
    -- NPC texture (simple humanoid shape)
    spriteTextures.npc = Sprites.createNPCTexture(0.2, 0.5, 0.8)  -- Blue robed figure
    spriteTextures.enemy = Sprites.createNPCTexture(0.7, 0.2, 0.2)  -- Red enemy
    spriteTextures.lich = Sprites.createLichTexture()  -- Special lich texture
    spriteTextures.item = Sprites.createItemTexture({0.3, 0.8, 0.3})  -- Generic green orb
    spriteTextures.pillar = Sprites.createPillarTexture()  -- Decoration

    -- Player texture (for third-person view)
    spriteTextures.player = Sprites.createPlayerTexture()

    -- Item-specific textures
    spriteTextures.health_potion = Sprites.createPotionTexture({1, 0.2, 0.2})
    spriteTextures.mana_potion = Sprites.createPotionTexture({0.2, 0.3, 1})
    spriteTextures.gold = Sprites.createGoldTexture()
    spriteTextures.key = Sprites.createKeyTexture()
    spriteTextures.sword = Sprites.createSwordTexture()
    spriteTextures.gem = Sprites.createGemTexture()
end

function Sprites.createNPCTexture(r, g, b)
    local size = 64
    local imageData = love.image.newImageData(size, size)

    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local cx = x - size / 2
            local cy = y - size / 2

            -- Head (circle at top)
            local headY = -size * 0.3
            local headRadius = size * 0.15
            local headDist = math.sqrt(cx * cx + (cy - headY) * (cy - headY))

            -- Body (rectangle)
            local bodyTop = -size * 0.15
            local bodyBottom = size * 0.4
            local bodyWidth = size * 0.25

            local alpha = 0
            local pr, pg, pb = r, g, b

            if headDist < headRadius then
                -- Head - skin tone
                alpha = 1
                pr, pg, pb = 0.9, 0.7, 0.6
                -- Add face details
                if headDist < headRadius * 0.3 then
                    pr, pg, pb = 0.1, 0.1, 0.1  -- Face center
                end
            elseif cy > bodyTop and cy < bodyBottom and math.abs(cx) < bodyWidth then
                -- Body - robe color
                alpha = 1
                -- Add shading
                local shade = 1 - (math.abs(cx) / bodyWidth) * 0.3
                pr, pg, pb = r * shade, g * shade, b * shade
            end

            if alpha > 0 then
                imageData:setPixel(x, y, pr, pg, pb, alpha)
            else
                imageData:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end

    local texture = love.graphics.newImage(imageData)
    texture:setFilter("nearest", "nearest")
    return texture
end

function Sprites.createLichTexture()
    local size = 64
    local imageData = love.image.newImageData(size, size)

    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local cx = x - size / 2
            local cy = y - size / 2

            -- Hooded figure with glowing eyes
            local headY = -size * 0.25
            local headRadius = size * 0.18
            local headDist = math.sqrt(cx * cx + (cy - headY) * (cy - headY))

            local bodyTop = -size * 0.1
            local bodyBottom = size * 0.45
            local bodyWidth = size * 0.3

            local alpha = 0
            local pr, pg, pb = 0, 0, 0

            -- Tattered robe
            if cy > bodyTop and cy < bodyBottom then
                local robeWidth = bodyWidth * (1 + (cy - bodyTop) / (bodyBottom - bodyTop) * 0.5)
                if math.abs(cx) < robeWidth then
                    alpha = 1
                    -- Dark purple/black robe with tattered edges
                    local tatter = math.sin(cy * 0.5 + cx * 0.3) * 0.2
                    pr = 0.15 + tatter * 0.1
                    pg = 0.05
                    pb = 0.2 + tatter * 0.15

                    -- Tattered bottom edge
                    if cy > bodyBottom - 10 then
                        local edge = math.random()
                        if edge > 0.6 then
                            alpha = 0
                        end
                    end
                end
            end

            -- Hood
            if headDist < headRadius then
                alpha = 1
                pr, pg, pb = 0.1, 0.05, 0.15

                -- Glowing eyes
                local eyeY = headY + 2
                local eyeSpacing = 5
                local eyeRadius = 3

                local leftEyeDist = math.sqrt((cx + eyeSpacing) * (cx + eyeSpacing) + (cy - eyeY) * (cy - eyeY))
                local rightEyeDist = math.sqrt((cx - eyeSpacing) * (cx - eyeSpacing) + (cy - eyeY) * (cy - eyeY))

                if leftEyeDist < eyeRadius or rightEyeDist < eyeRadius then
                    -- Glowing purple eyes
                    pr = 0.8
                    pg = 0.2
                    pb = 1.0
                end
            end

            if alpha > 0 then
                imageData:setPixel(x, y, pr, pg, pb, alpha)
            else
                imageData:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end

    local texture = love.graphics.newImage(imageData)
    texture:setFilter("nearest", "nearest")
    return texture
end

function Sprites.createItemTexture(color)
    color = color or {0.3, 0.8, 0.3}
    local size = 32
    local imageData = love.image.newImageData(size, size)

    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local cx = x - size / 2
            local cy = y - size / 2
            local dist = math.sqrt(cx * cx + cy * cy)
            local radius = size * 0.35

            if dist < radius then
                -- Glowing orb
                local glow = 1 - (dist / radius)
                local r = color[1] * 0.5 + glow * color[1] * 0.5
                local g = color[2] * 0.5 + glow * color[2] * 0.5
                local b = color[3] * 0.5 + glow * color[3] * 0.5
                imageData:setPixel(x, y, r, g, b, 0.8 + glow * 0.2)
            else
                imageData:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end

    local texture = love.graphics.newImage(imageData)
    texture:setFilter("nearest", "nearest")
    return texture
end

-- Potion bottle texture
function Sprites.createPotionTexture(color)
    local size = 32
    local imageData = love.image.newImageData(size, size)

    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local cx = x - size / 2
            local cy = y - size / 2

            -- Bottle neck (top)
            local neckTop = -size * 0.4
            local neckBot = -size * 0.2
            local neckWidth = size * 0.1

            -- Bottle body (bottom)
            local bodyTop = -size * 0.15
            local bodyBot = size * 0.4
            local bodyWidth = size * 0.3

            local alpha = 0
            local r, g, b = 0, 0, 0

            -- Draw neck
            if cy > neckTop and cy < neckBot and math.abs(cx) < neckWidth then
                alpha = 1
                r, g, b = 0.4, 0.4, 0.5  -- Glass color
            end

            -- Draw body
            if cy > bodyTop and cy < bodyBot then
                local widthAtY = bodyWidth * (1 - math.abs(cy - (bodyTop + bodyBot) / 2) / ((bodyBot - bodyTop) / 2) * 0.3)
                if math.abs(cx) < widthAtY then
                    alpha = 1
                    -- Liquid inside
                    local liquidTop = bodyTop + (bodyBot - bodyTop) * 0.15
                    if cy > liquidTop then
                        local glow = 0.7 + math.sin(cx * 0.5 + cy * 0.3) * 0.2
                        r = color[1] * glow
                        g = color[2] * glow
                        b = color[3] * glow
                    else
                        r, g, b = 0.3, 0.3, 0.4  -- Empty glass
                    end

                    -- Glass edge highlight
                    if math.abs(math.abs(cx) - widthAtY) < 2 then
                        r = r + 0.2
                        g = g + 0.2
                        b = b + 0.2
                    end
                end
            end

            if alpha > 0 then
                imageData:setPixel(x, y, math.min(1, r), math.min(1, g), math.min(1, b), alpha)
            else
                imageData:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end

    local texture = love.graphics.newImage(imageData)
    texture:setFilter("nearest", "nearest")
    return texture
end

-- Gold coins texture
function Sprites.createGoldTexture()
    local size = 32
    local imageData = love.image.newImageData(size, size)

    -- Draw 3 stacked coins
    local coins = {
        {0, 5, 8},      -- x offset, y offset, radius
        {-4, 0, 7},
        {5, -3, 6},
    }

    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local cx = x - size / 2
            local cy = y - size / 2

            local alpha = 0
            local r, g, b = 0, 0, 0

            for _, coin in ipairs(coins) do
                local dx = cx - coin[1]
                local dy = cy - coin[2]
                local dist = math.sqrt(dx * dx + dy * dy)

                if dist < coin[3] then
                    alpha = 1
                    local shine = 1 - dist / coin[3]
                    r = 0.8 + shine * 0.2
                    g = 0.65 + shine * 0.2
                    b = 0.1 + shine * 0.1

                    -- Edge darkening
                    if dist > coin[3] - 2 then
                        r = r * 0.7
                        g = g * 0.6
                        b = b * 0.5
                    end
                end
            end

            if alpha > 0 then
                imageData:setPixel(x, y, r, g, b, alpha)
            else
                imageData:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end

    local texture = love.graphics.newImage(imageData)
    texture:setFilter("nearest", "nearest")
    return texture
end

-- Key texture
function Sprites.createKeyTexture()
    local size = 32
    local imageData = love.image.newImageData(size, size)

    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local cx = x - size / 2
            local cy = y - size / 2

            local alpha = 0
            local r, g, b = 0.75, 0.6, 0.15  -- Gold/bronze

            -- Key ring (circle at top)
            local ringY = -size * 0.25
            local ringOuterR = size * 0.2
            local ringInnerR = size * 0.1
            local ringDist = math.sqrt(cx * cx + (cy - ringY) * (cy - ringY))

            if ringDist < ringOuterR and ringDist > ringInnerR then
                alpha = 1
            end

            -- Key shaft
            local shaftTop = -size * 0.05
            local shaftBot = size * 0.35
            local shaftWidth = size * 0.08

            if cy > shaftTop and cy < shaftBot and math.abs(cx) < shaftWidth then
                alpha = 1
            end

            -- Key teeth
            if cy > size * 0.15 and cy < size * 0.35 then
                if cx > shaftWidth and cx < shaftWidth + size * 0.15 then
                    if math.floor(cy / 4) % 2 == 0 then
                        alpha = 1
                    end
                end
            end

            if alpha > 0 then
                -- Add shine
                local shine = 0.8 + (cx + cy) * 0.01
                imageData:setPixel(x, y, r * shine, g * shine, b * shine, alpha)
            else
                imageData:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end

    local texture = love.graphics.newImage(imageData)
    texture:setFilter("nearest", "nearest")
    return texture
end

-- Sword texture
function Sprites.createSwordTexture()
    local size = 48
    local imageData = love.image.newImageData(size, size)

    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local cx = x - size / 2
            local cy = y - size / 2

            local alpha = 0
            local r, g, b = 0.7, 0.7, 0.8  -- Steel color

            -- Blade
            local bladeTop = -size * 0.45
            local bladeBot = size * 0.15
            local bladeWidth = size * 0.06

            -- Tapered blade
            if cy > bladeTop and cy < bladeBot then
                local taper = 1 - (cy - bladeTop) / (bladeBot - bladeTop) * 0.7
                if math.abs(cx) < bladeWidth * taper then
                    alpha = 1
                    -- Blade shine
                    if cx < 0 then
                        r, g, b = 0.85, 0.85, 0.95
                    end
                end
            end

            -- Cross guard
            local guardY = size * 0.15
            local guardWidth = size * 0.25
            local guardHeight = size * 0.06

            if math.abs(cy - guardY) < guardHeight and math.abs(cx) < guardWidth then
                alpha = 1
                r, g, b = 0.5, 0.4, 0.2  -- Bronze guard
            end

            -- Handle
            local handleTop = size * 0.2
            local handleBot = size * 0.4
            local handleWidth = size * 0.05

            if cy > handleTop and cy < handleBot and math.abs(cx) < handleWidth then
                alpha = 1
                r, g, b = 0.4, 0.25, 0.1  -- Brown leather
                -- Wrap pattern
                if math.floor(cy / 3) % 2 == 0 then
                    r, g, b = 0.35, 0.2, 0.08
                end
            end

            -- Pommel
            local pommelY = size * 0.42
            local pommelR = size * 0.06
            local pommelDist = math.sqrt(cx * cx + (cy - pommelY) * (cy - pommelY))

            if pommelDist < pommelR then
                alpha = 1
                r, g, b = 0.6, 0.5, 0.2  -- Gold pommel
            end

            if alpha > 0 then
                imageData:setPixel(x, y, r, g, b, alpha)
            else
                imageData:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end

    local texture = love.graphics.newImage(imageData)
    texture:setFilter("nearest", "nearest")
    return texture
end

-- Gem texture
function Sprites.createGemTexture()
    local size = 32
    local imageData = love.image.newImageData(size, size)

    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local cx = x - size / 2
            local cy = y - size / 2

            local alpha = 0
            local r, g, b = 0, 0, 0

            -- Diamond shape
            local gemSize = size * 0.35
            local dist = math.abs(cx) + math.abs(cy)

            if dist < gemSize then
                alpha = 1
                -- Faceted look
                local facet = math.floor((math.atan2(cy, cx) + math.pi) / (math.pi / 4)) % 8
                local brightness = 0.5 + (facet % 2) * 0.3

                -- Purple gem with color variation
                r = 0.7 * brightness + (1 - dist / gemSize) * 0.3
                g = 0.2 * brightness
                b = 0.9 * brightness + (1 - dist / gemSize) * 0.1

                -- Center sparkle
                if dist < gemSize * 0.3 then
                    r = r + 0.3
                    g = g + 0.2
                    b = b + 0.2
                end
            end

            if alpha > 0 then
                imageData:setPixel(x, y, math.min(1, r), math.min(1, g), math.min(1, b), alpha)
            else
                imageData:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end

    local texture = love.graphics.newImage(imageData)
    texture:setFilter("nearest", "nearest")
    return texture
end

function Sprites.createPillarTexture()
    local size = 64
    local imageData = love.image.newImageData(size, size)

    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local cx = x - size / 2
            local width = size * 0.2

            if math.abs(cx) < width then
                -- Stone pillar
                local shade = 0.4 + (math.random() - 0.5) * 0.1
                shade = shade - math.abs(cx) / width * 0.15
                imageData:setPixel(x, y, shade, shade * 0.95, shade * 0.9, 1)
            else
                imageData:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end

    local texture = love.graphics.newImage(imageData)
    texture:setFilter("nearest", "nearest")
    return texture
end

-- Player character texture (seen from behind in third-person)
function Sprites.createPlayerTexture()
    local size = 64
    local imageData = love.image.newImageData(size, size)

    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local cx = x - size / 2
            local cy = y - size / 2

            local alpha = 0
            local r, g, b = 0, 0, 0

            -- Head (circle at top)
            local headY = -size * 0.3
            local headRadius = size * 0.14
            local headDist = math.sqrt(cx * cx + (cy - headY) * (cy - headY))

            -- Hair (slightly larger than head, on top)
            local hairY = headY - 2
            local hairRadius = headRadius + 2
            local hairDist = math.sqrt(cx * cx + (cy - hairY) * (cy - hairY))

            -- Body (torso)
            local bodyTop = -size * 0.15
            local bodyBottom = size * 0.2
            local bodyWidth = size * 0.22

            -- Cloak (wider, flowing)
            local cloakTop = -size * 0.12
            local cloakBottom = size * 0.42
            local cloakWidth = size * 0.28

            -- Arms
            local armTop = -size * 0.1
            local armBottom = size * 0.15
            local armWidth = size * 0.08

            -- Legs
            local legTop = size * 0.2
            local legBottom = size * 0.42
            local legWidth = size * 0.08
            local legSpacing = size * 0.06

            -- Draw cloak (behind everything)
            if cy > cloakTop and cy < cloakBottom then
                local widthAtY = cloakWidth * (0.8 + (cy - cloakTop) / (cloakBottom - cloakTop) * 0.4)
                if math.abs(cx) < widthAtY then
                    alpha = 1
                    -- Dark green cloak
                    local shade = 0.8 - (math.abs(cx) / widthAtY) * 0.3
                    r = 0.15 * shade
                    g = 0.35 * shade
                    b = 0.15 * shade
                    -- Cloak fold lines
                    if math.abs(cx) > widthAtY * 0.4 and math.abs(cx) < widthAtY * 0.45 then
                        r = r * 0.7
                        g = g * 0.7
                        b = b * 0.7
                    end
                end
            end

            -- Draw body (brown leather armor)
            if cy > bodyTop and cy < bodyBottom and math.abs(cx) < bodyWidth then
                alpha = 1
                local shade = 1 - (math.abs(cx) / bodyWidth) * 0.3
                r = 0.45 * shade
                g = 0.30 * shade
                b = 0.15 * shade
                -- Belt
                if cy > size * 0.12 and cy < size * 0.17 then
                    r = 0.35
                    g = 0.25
                    b = 0.10
                    -- Belt buckle
                    if math.abs(cx) < 3 then
                        r, g, b = 0.7, 0.6, 0.2
                    end
                end
            end

            -- Draw arms (on sides of body)
            if cy > armTop and cy < armBottom then
                local leftArm = cx < -(bodyWidth - 2) and cx > -(bodyWidth + armWidth)
                local rightArm = cx > (bodyWidth - 2) and cx < (bodyWidth + armWidth)
                if leftArm or rightArm then
                    alpha = 1
                    -- Skin tone for forearms, armor for upper
                    if cy < size * 0.05 then
                        r, g, b = 0.4, 0.28, 0.14  -- Armor
                    else
                        r, g, b = 0.85, 0.65, 0.5  -- Skin
                    end
                end
            end

            -- Draw legs
            if cy > legTop and cy < legBottom then
                local leftLeg = math.abs(cx + legSpacing) < legWidth
                local rightLeg = math.abs(cx - legSpacing) < legWidth
                if leftLeg or rightLeg then
                    alpha = 1
                    r, g, b = 0.3, 0.2, 0.12  -- Dark brown pants
                end
            end

            -- Draw head (on top of everything)
            if headDist < headRadius then
                alpha = 1
                r, g, b = 0.85, 0.65, 0.5  -- Skin tone (back of head)
            end

            -- Draw hair over head
            if hairDist < hairRadius and cy < headY + 4 then
                alpha = 1
                local shade = 0.8 + (cx / hairRadius) * 0.2
                r = 0.3 * shade
                g = 0.2 * shade
                b = 0.1 * shade
            end

            -- Boots
            if cy > size * 0.38 and cy < size * 0.45 then
                local leftBoot = math.abs(cx + legSpacing) < legWidth + 2
                local rightBoot = math.abs(cx - legSpacing) < legWidth + 2
                if leftBoot or rightBoot then
                    alpha = 1
                    r, g, b = 0.25, 0.15, 0.08
                end
            end

            if alpha > 0 then
                imageData:setPixel(x, y, math.max(0, math.min(1, r)), math.max(0, math.min(1, g)), math.max(0, math.min(1, b)), alpha)
            else
                imageData:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end

    local texture = love.graphics.newImage(imageData)
    texture:setFilter("nearest", "nearest")
    return texture
end

-- Set/update the player sprite for third-person view
function Sprites.setPlayerSprite(x, y, dirX, dirY, visible)
    if visible then
        if not playerSpriteId or not sprites[playerSpriteId] then
            -- Create player sprite
            playerSpriteId = Sprites.add(x, y, "decoration", {
                texture = "player",
                scale = 0.9,
                name = "Player",
                isPlayerSprite = true,
            })
            local sprite = sprites[playerSpriteId]
            if sprite then
                sprite.isPlayerSprite = true
                sprite.canPickup = false
            end
        else
            -- Update position
            local sprite = sprites[playerSpriteId]
            sprite.x = x
            sprite.y = y
        end
    else
        -- Remove player sprite when switching to first-person
        if playerSpriteId and sprites[playerSpriteId] then
            sprites[playerSpriteId] = nil
        end
        playerSpriteId = nil
    end
end

-- Check if a sprite is the player sprite
function Sprites.isPlayerSprite(id)
    return id == playerSpriteId
end

-- Add a sprite to the world
function Sprites.add(x, y, spriteType, data)
    local id = nextSpriteId
    nextSpriteId = nextSpriteId + 1
    local textureName = spriteType
    if data and data.texture then
        textureName = data.texture
    end

    -- Default health based on type
    local health = nil
    local maxHealth = nil
    local hostile = false
    local damage = 0
    local attackCooldown = 0
    local speed = 0

    if spriteType == "npc" then
        health = (data and data.health) or 30
        maxHealth = health
        hostile = (data and data.hostile) or false
        damage = (data and data.damage) or 5
        speed = (data and data.speed) or 0  -- NPCs don't move by default
    elseif spriteType == "enemy" then
        health = (data and data.health) or 50
        maxHealth = health
        hostile = true  -- Enemies are always hostile
        damage = (data and data.damage) or 10
        speed = (data and data.speed) or 1.5  -- Enemies move toward player
    end

    sprites[id] = {
        id = id,
        x = x,
        y = y,
        type = spriteType,
        texture = textureName,
        scale = (data and data.scale) or 1.0,
        vOffset = (data and data.vOffset) or 0,  -- Vertical offset
        name = (data and data.name) or nil,
        -- Item-specific data
        itemType = (data and data.itemType) or nil,
        canPickup = (spriteType == "item"),
        spawnTime = love.timer.getTime(),  -- For bobbing animation
        -- Combat data
        health = health,
        maxHealth = maxHealth,
        hostile = hostile,
        damage = damage,
        speed = speed,
        attackCooldown = 0,
        lastHitTime = 0,
    }
    return id
end

-- Add an item to the world (convenience function)
function Sprites.addItem(x, y, itemType, data)
    local itemDef = Sprites.ITEMS[itemType]
    if not itemDef then
        print("Warning: Unknown item type: " .. tostring(itemType))
        itemDef = Sprites.ITEMS.gold  -- Fallback
    end

    data = data or {}
    data.texture = itemDef.texture
    data.itemType = itemType
    data.scale = data.scale or 0.5
    data.vOffset = data.vOffset or 10  -- Items float slightly above ground

    return Sprites.add(x, y, "item", data)
end

-- Remove a sprite
function Sprites.remove(id)
    sprites[id] = nil
end

-- Check for items near player and pick them up
function Sprites.checkPickup(playerX, playerY)
    local pickedUp = {}

    for id, sprite in pairs(sprites) do
        if sprite.canPickup and sprite.type == "item" then
            local dx = sprite.x - playerX
            local dy = sprite.y - playerY
            local dist = math.sqrt(dx * dx + dy * dy)

            if dist < PICKUP_RADIUS then
                local itemDef = Sprites.ITEMS[sprite.itemType]
                if itemDef then
                    table.insert(pickedUp, {
                        id = id,
                        itemType = sprite.itemType,
                        name = itemDef.name,
                        value = itemDef.value,
                        stat = itemDef.stat,
                        color = itemDef.color,
                    })
                end
            end
        end
    end

    -- Remove picked up items and trigger callbacks
    for _, item in ipairs(pickedUp) do
        Sprites.remove(item.id)

        -- Trigger pickup callbacks
        for _, callback in ipairs(pickupCallbacks) do
            callback(item)
        end
    end

    return pickedUp
end

-- Get nearby item for interaction hint (not auto-pickup)
function Sprites.getNearbyItem(playerX, playerY, maxDist)
    maxDist = maxDist or 1.5
    local nearest = nil
    local nearestDist = maxDist

    for id, sprite in pairs(sprites) do
        if sprite.canPickup and sprite.type == "item" then
            local dx = sprite.x - playerX
            local dy = sprite.y - playerY
            local dist = math.sqrt(dx * dx + dy * dy)

            if dist < nearestDist then
                nearest = sprite
                nearestDist = dist
            end
        end
    end

    return nearest, nearestDist
end

-- Clear all sprites
function Sprites.clear()
    sprites = {}
    playerSpriteId = nil
    nextSpriteId = 1
end

-- Get all sprites
function Sprites.getAll()
    return sprites
end

-- Get sprite texture
function Sprites.getTexture(name)
    return spriteTextures[name]
end

-- Render all sprites (called after walls)
function Sprites.render(player, zBuffer, screenWidth, screenHeight)
    local posX, posY = player.x, player.y
    local dirX, dirY = player.dirX, player.dirY
    local planeX, planeY = player.planeX, player.planeY
    local hShift = player.horizonShift or 0
    local currentTime = love.timer.getTime()

    -- Calculate sprite distances and sort
    local spriteOrder = {}
    for id, sprite in pairs(sprites) do
        local dx = sprite.x - posX
        local dy = sprite.y - posY
        local dist = dx * dx + dy * dy  -- No need to sqrt, just for sorting
        table.insert(spriteOrder, {sprite = sprite, dist = dist})
    end

    -- Sort back to front (furthest first)
    table.sort(spriteOrder, function(a, b) return a.dist > b.dist end)

    -- Render each sprite
    for _, entry in ipairs(spriteOrder) do
        local sprite = entry.sprite
        local spriteX = sprite.x - posX
        local spriteY = sprite.y - posY

        -- Transform sprite with inverse camera matrix
        local invDet = 1.0 / (planeX * dirY - dirX * planeY)
        local transformX = invDet * (dirY * spriteX - dirX * spriteY)
        local transformY = invDet * (-planeY * spriteX + planeX * spriteY)

        -- Sprite is behind player
        if transformY <= 0.1 then
            goto continue
        end

        local spriteScreenX = math.floor((screenWidth / 2) * (1 + transformX / transformY))

        -- Calculate sprite height
        local spriteHeight = math.abs(math.floor(screenHeight / transformY)) * sprite.scale

        -- Add bobbing animation for items
        local vOffset = sprite.vOffset
        if sprite.type == "item" then
            local bobTime = (currentTime - (sprite.spawnTime or 0)) * ITEM_BOB_SPEED
            vOffset = vOffset + math.sin(bobTime) * ITEM_BOB_HEIGHT
        end

        local drawStartY = math.floor(-spriteHeight / 2 + screenHeight / 2 + vOffset + hShift)
        local drawEndY = math.floor(spriteHeight / 2 + screenHeight / 2 + vOffset + hShift)

        -- Calculate sprite width
        local spriteWidth = math.abs(math.floor(screenHeight / transformY)) * sprite.scale
        local drawStartX = math.floor(-spriteWidth / 2 + spriteScreenX)
        local drawEndX = math.floor(spriteWidth / 2 + spriteScreenX)

        -- Get texture
        local texture = spriteTextures[sprite.texture]
        if not texture then
            texture = spriteTextures.npc
        end

        local texWidth = texture:getWidth()
        local texHeight = texture:getHeight()

        -- Draw sprite columns
        for stripe = math.max(0, drawStartX), math.min(screenWidth - 1, drawEndX) do
            local texX = math.floor((stripe - drawStartX) * texWidth / spriteWidth)
            texX = math.max(0, math.min(texWidth - 1, texX))

            -- Only draw if in front of wall (z-buffer check)
            if transformY < (zBuffer[stripe] or 1e30) then
                -- Distance shading
                local shade = 1 - math.min(transformY / 15, 0.7)

                -- Items glow slightly
                if sprite.type == "item" then
                    local itemDef = Sprites.ITEMS[sprite.itemType]
                    if itemDef and itemDef.color then
                        local glow = 0.8 + math.sin(currentTime * 4) * 0.2
                        local c = itemDef.color
                        love.graphics.setColor(
                            shade * (0.5 + c[1] * 0.5 * glow),
                            shade * (0.5 + c[2] * 0.5 * glow),
                            shade * (0.5 + c[3] * 0.5 * glow)
                        )
                    else
                        love.graphics.setColor(shade, shade, shade)
                    end
                else
                    love.graphics.setColor(shade, shade, shade)
                end

                local quad = love.graphics.newQuad(
                    texX, 0,
                    1, texHeight,
                    texWidth, texHeight
                )

                local scaleY = spriteHeight / texHeight

                love.graphics.draw(
                    texture,
                    quad,
                    stripe,
                    math.max(0, drawStartY),
                    0,
                    1,
                    scaleY
                )
            end
        end

        -- Draw health bar above sprite (only for entities with health)
        if sprite.health and sprite.maxHealth and sprite.health < sprite.maxHealth then
            local barWidth = spriteWidth * 0.8
            local barHeight = 4
            local barX = spriteScreenX - barWidth / 2
            local barY = drawStartY - 10

            if barY > 0 and spriteScreenX > 0 and spriteScreenX < screenWidth then
                -- Background
                love.graphics.setColor(0.2, 0.2, 0.2, 0.8)
                love.graphics.rectangle("fill", barX, barY, barWidth, barHeight)

                -- Health fill
                local healthPct = sprite.health / sprite.maxHealth
                local healthColor = sprite.hostile and {0.8, 0.2, 0.2} or {0.2, 0.8, 0.2}
                love.graphics.setColor(healthColor[1], healthColor[2], healthColor[3])
                love.graphics.rectangle("fill", barX, barY, barWidth * healthPct, barHeight)

                -- Damage flash
                if sprite.lastHitTime and (currentTime - sprite.lastHitTime) < 0.2 then
                    love.graphics.setColor(1, 1, 1, 0.5)
                    love.graphics.rectangle("fill", barX, barY, barWidth, barHeight)
                end
            end
        end

        ::continue::
    end

    love.graphics.setColor(1, 1, 1)
end

-- Update enemy AI (movement and attacks)
-- Requires Doors module to be passed in for door interaction
function Sprites.updateAI(dt, playerX, playerY, map, onEnemyAttack, Doors)
    for id, sprite in pairs(sprites) do
        if sprite.isPlayerSprite then goto continue_ai end
        if sprite.hostile and sprite.health and sprite.health > 0 then
            local dx = playerX - sprite.x
            local dy = playerY - sprite.y
            local dist = math.sqrt(dx * dx + dy * dy)

            -- Normalize direction
            if dist > 0.1 then
                dx = dx / dist
                dy = dy / dist
            end

            -- Move toward player if not too close
            if sprite.speed > 0 and dist > 1.5 then
                local newX = sprite.x + dx * sprite.speed * dt
                local newY = sprite.y + dy * sprite.speed * dt

                -- Check for doors in the way and open them
                if Doors then
                    local checkX = math.floor(sprite.x + dx * 0.5)
                    local checkY = math.floor(sprite.y + dy * 0.5)
                    if Doors.isClosedDoorAt(checkX, checkY) then
                        Doors.openAt(checkX, checkY)
                    end
                end

                -- Check wall collision (allow through open doors via tile 10)
                local tileX = map:getTile(math.floor(newX), math.floor(sprite.y))
                local tileY = map:getTile(math.floor(sprite.x), math.floor(newY))

                -- Can walk on empty tiles, stairs, and through open doors
                local canMoveX = tileX == 0 or tileX == 10 or tileX == 11 or tileX == 12
                local canMoveY = tileY == 0 or tileY == 10 or tileY == 11 or tileY == 12

                -- For doors, also check if passable
                if tileX == 10 and Doors then
                    canMoveX = Doors.isPassable(math.floor(newX), math.floor(sprite.y))
                end
                if tileY == 10 and Doors then
                    canMoveY = Doors.isPassable(math.floor(sprite.x), math.floor(newY))
                end

                if canMoveX then
                    sprite.x = newX
                end
                if canMoveY then
                    sprite.y = newY
                end
            end

            -- Attack if close enough
            if dist < 1.8 then
                sprite.attackCooldown = sprite.attackCooldown - dt
                if sprite.attackCooldown <= 0 then
                    sprite.attackCooldown = 1.5  -- Attack every 1.5 seconds
                    if onEnemyAttack then
                        onEnemyAttack(sprite)
                    end
                end
            end
        end
        ::continue_ai::
    end
end

-- Damage a sprite by ID
function Sprites.damage(id, amount)
    local sprite = sprites[id]
    if sprite and sprite.health then
        sprite.health = sprite.health - amount
        sprite.lastHitTime = love.timer.getTime()
        if sprite.health <= 0 then
            return true, sprite  -- Killed
        end
        return false, sprite  -- Damaged but alive
    end
    return false, nil
end

-- Get item count by type
function Sprites.getItemCount(itemType)
    local count = 0
    for _, sprite in pairs(sprites) do
        if sprite.type == "item" and sprite.itemType == itemType then
            count = count + 1
        end
    end
    return count
end

-- Get total item count
function Sprites.getTotalItemCount()
    local count = 0
    for _, sprite in pairs(sprites) do
        if sprite.type == "item" then
            count = count + 1
        end
    end
    return count
end

return Sprites
