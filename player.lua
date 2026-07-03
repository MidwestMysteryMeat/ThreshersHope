--[[
    Player Module
    Handles movement, collision detection, mouse look, swimming, and depth control
    Extended for underwater city builder with pitch (vertical look) and swim bobbing
]]

local Player = {}

-- Movement constants
local MOVE_SPEED = 3.0      -- Units per second
local SWIM_SPEED = 2.2      -- Slower when swimming in open water
local ROT_SPEED = 2.0       -- Radians per second (keyboard)
local MOUSE_SENS = 0.003    -- Mouse sensitivity (horizontal)
local PITCH_SENS = 0.004    -- Mouse sensitivity (vertical)
local COLLISION_RADIUS = 0.35 -- Player collision size
local MAX_PITCH = 1.2       -- Max pitch (radians, ~69 degrees)

-- Swimming bob animation
local BOB_SPEED = 2.5       -- Oscillation speed
local BOB_AMOUNT = 3.0      -- Pixels of horizon shift from bob
local SWIM_BOB_SPEED = 1.5  -- Slower, more floaty bob when swimming
local SWIM_BOB_AMOUNT = 5.0 -- Larger bob when swimming

-- Cached math
local math_sin = math.sin
local math_cos = math.cos
local math_abs = math.abs
local math_max = math.max
local math_min = math.min

function Player.create(x, y)
    local player = {
        -- Position
        x = x or 2,
        y = y or 2,

        -- Direction vector (initially facing right)
        dirX = 1,
        dirY = 0,

        -- Camera plane (perpendicular to direction, determines FOV)
        planeX = 0,
        planeY = 0.66,

        -- Vertical look (pitch) - affects horizon line
        pitch = 0,           -- Current pitch in radians
        horizonShift = 0,    -- Pixel offset for horizon (computed from pitch)

        -- Swimming state
        isSwimming = false,  -- True when in open water (not in habitat)
        isInHabitat = false, -- True when inside a powered habitat
        swimBobTimer = 0,    -- Animation timer for swim bob
        walkBobTimer = 0,    -- Animation timer for walk bob
        moveActive = false,  -- True if player moved this frame

        -- Depth control
        depthInput = 0,      -- -1 = ascending, +1 = descending, 0 = neutral

        -- Speed modifier (from hunger, equipment, etc.)
        speedMultiplier = 1.0,
    }

    return player
end

function Player.update(player, dt, map)
    local baseSpeed = player.isSwimming and SWIM_SPEED or MOVE_SPEED
    local moveSpeed = baseSpeed * player.speedMultiplier * dt
    local rotSpeed = ROT_SPEED * dt
    player.moveActive = false

    -- Forward/Backward (W/S)
    if love.keyboard.isDown("w") or love.keyboard.isDown("up") then
        Player.move(player, player.dirX * moveSpeed, player.dirY * moveSpeed, map)
        player.moveActive = true
    end
    if love.keyboard.isDown("s") or love.keyboard.isDown("down") then
        Player.move(player, -player.dirX * moveSpeed, -player.dirY * moveSpeed, map)
        player.moveActive = true
    end

    -- Strafe Left/Right (A/D)
    if love.keyboard.isDown("a") then
        Player.move(player, -player.planeX * moveSpeed, -player.planeY * moveSpeed, map)
        player.moveActive = true
    end
    if love.keyboard.isDown("d") then
        Player.move(player, player.planeX * moveSpeed, player.planeY * moveSpeed, map)
        player.moveActive = true
    end

    -- Depth control (Space = ascend, LCtrl = descend) — only when swimming
    player.depthInput = 0
    if player.isSwimming then
        if love.keyboard.isDown("space") then
            player.depthInput = -1  -- Ascend
        end
        if love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") then
            player.depthInput = 1   -- Descend
        end
    end

    -- Keyboard rotation (arrow keys, backup for mouse)
    if love.keyboard.isDown("left") then
        Player.rotate(player, -rotSpeed)
    end
    if love.keyboard.isDown("right") then
        Player.rotate(player, rotSpeed)
    end

    -- Update bob animation
    if player.isSwimming then
        -- Continuous gentle bob when swimming (even when still)
        player.swimBobTimer = player.swimBobTimer + dt * SWIM_BOB_SPEED
        local swimBob = math_sin(player.swimBobTimer) * SWIM_BOB_AMOUNT
        -- Add movement bob on top
        if player.moveActive then
            player.walkBobTimer = player.walkBobTimer + dt * BOB_SPEED * 2
            swimBob = swimBob + math_sin(player.walkBobTimer) * BOB_AMOUNT * 0.5
        end
        player.horizonShift = swimBob + player.pitch * 200
    else
        -- Normal walk bob (only when moving)
        if player.moveActive then
            player.walkBobTimer = player.walkBobTimer + dt * BOB_SPEED * 2
            local walkBob = math_sin(player.walkBobTimer) * BOB_AMOUNT
            player.horizonShift = walkBob + player.pitch * 200
        else
            -- Settle back to neutral
            local target = player.pitch * 200
            player.horizonShift = player.horizonShift + (target - player.horizonShift) * dt * 8
        end
    end
end

function Player.move(player, dx, dy, map)
    local newX = player.x + dx
    local newY = player.y + dy

    -- Check X movement
    if not Player.collidesAt(newX, player.y, map) then
        player.x = newX
    elseif not Player.collidesAt(player.x + dx * 0.5, player.y, map) then
        player.x = player.x + dx * 0.5
    end

    -- Check Y movement
    if not Player.collidesAt(player.x, newY, map) then
        player.y = newY
    elseif not Player.collidesAt(player.x, player.y + dy * 0.5, map) then
        player.y = player.y + dy * 0.5
    end
end

function Player.collidesAt(x, y, map)
    local r = COLLISION_RADIUS

    local checks = {
        {x - r, y - r},
        {x + r, y - r},
        {x - r, y + r},
        {x + r, y + r},
    }

    for _, pos in ipairs(checks) do
        if not map:isWalkable(pos[1], pos[2]) then
            return true
        end
    end

    return false
end

function Player.rotate(player, angle)
    local oldDirX = player.dirX
    player.dirX = player.dirX * math_cos(angle) - player.dirY * math_sin(angle)
    player.dirY = oldDirX * math_sin(angle) + player.dirY * math_cos(angle)

    local oldPlaneX = player.planeX
    player.planeX = player.planeX * math_cos(angle) - player.planeY * math_sin(angle)
    player.planeY = oldPlaneX * math_sin(angle) + player.planeY * math_cos(angle)
end

function Player.mouseLook(player, dx, dy)
    -- Horizontal rotation
    local angle = dx * MOUSE_SENS
    Player.rotate(player, angle)

    -- Vertical pitch (mouse Y)
    player.pitch = player.pitch - dy * PITCH_SENS
    player.pitch = math_max(-MAX_PITCH, math_min(MAX_PITCH, player.pitch))
end

-- Set swimming state (called by main.lua based on whether player is in habitat)
function Player.setSwimming(player, swimming)
    player.isSwimming = swimming
end

function Player.setInHabitat(player, inHabitat)
    player.isInHabitat = inHabitat
end

function Player.setSpeedMultiplier(player, mult)
    player.speedMultiplier = mult
end

-- Get player's angle in degrees (for debugging/display)
function Player.getAngle(player)
    return math.deg(math.atan2(player.dirY, player.dirX))
end

-- Get tile position
function Player.getTilePos(player)
    return math.floor(player.x), math.floor(player.y)
end

return Player
