--[[
    Third-Person Camera Module
    Fixed offset behind and above the player. No collision, no bobbing.
    Toggle with V key. Mouse wheel zooms in/out.

    The camera returns a table with the same fields as the player
    (x, y, dirX, dirY, planeX, planeY) plus horizonShift for
    the downward-looking angle.
]]

local Camera = {}

-- Camera state
local enabled = false          -- Third-person mode active
local distance = 1.8           -- Camera distance behind player
local targetDistance = 1.8     -- Target distance (for zoom)
local minDistance = 0.8        -- Minimum zoom distance
local maxDistance = 4.0        -- Maximum zoom distance

-- Shoulder offset (perpendicular to look direction, positive = right)
local shoulderOffset = 0.3

-- Horizon shift: negative = looking down (raised camera angle)
-- Render height is 200, horizon normally at 100. -30 puts it at 70.
-- Reduced from -55 to -30 for better visibility ahead
local horizonShift = -30

-- Zoom smoothing only (position snaps, no lerp)
local zoomLerpSpeed = 8.0

-- Current camera state
local camState = {
    x = 0, y = 0,
    dirX = 1, dirY = 0,
    planeX = 0, planeY = 0.66,
    horizonShift = 0,
    minRenderDist = 0,  -- Skip walls closer than this (camera-to-player gap)
}

function Camera.init()
    enabled = false
    distance = 1.8
    targetDistance = 1.8
end

function Camera.toggle()
    enabled = not enabled
    return enabled
end

function Camera.isEnabled()
    return enabled
end

function Camera.zoom(amount)
    if not enabled then return end
    targetDistance = targetDistance - amount * 0.3
    targetDistance = math.max(minDistance, math.min(maxDistance, targetDistance))
end

function Camera.update(player, dt, map)
    if not enabled then
        -- First-person: camera = player exactly
        camState.x = player.x
        camState.y = player.y
        camState.dirX = player.dirX
        camState.dirY = player.dirY
        camState.planeX = player.planeX
        camState.planeY = player.planeY
        camState.horizonShift = 0
        camState.minRenderDist = 0
        return camState
    end

    -- Smooth zoom only
    distance = distance + (targetDistance - distance) * zoomLerpSpeed * dt
    distance = math.max(minDistance, math.min(maxDistance, distance))

    -- Right direction (perpendicular to forward, for shoulder offset)
    local planeMag = math.sqrt(player.planeX * player.planeX + player.planeY * player.planeY)
    local rightX = 0
    local rightY = 0
    if planeMag > 0.01 then
        rightX = player.planeX / planeMag
        rightY = player.planeY / planeMag
    end

    -- Fixed camera position: behind player + shoulder offset
    -- No collision, no lerp - camera passes through walls freely
    camState.x = player.x - player.dirX * distance + rightX * shoulderOffset
    camState.y = player.y - player.dirY * distance + rightY * shoulderOffset

    -- Camera always looks in player's direction
    camState.dirX = player.dirX
    camState.dirY = player.dirY
    camState.planeX = player.planeX
    camState.planeY = player.planeY
    camState.horizonShift = horizonShift

    -- Distance from camera to player - walls closer than this are between
    -- camera and player and should not be rendered
    local dx = player.x - camState.x
    local dy = player.y - camState.y
    camState.minRenderDist = math.sqrt(dx * dx + dy * dy)

    return camState
end

function Camera.getState()
    return camState
end

function Camera.getDistance()
    return distance
end

return Camera
