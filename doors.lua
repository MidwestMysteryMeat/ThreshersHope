--[[
    Door System
    Handles interactive doors that swing open 90 degrees
]]

local Doors = {}

-- Door states
Doors.STATE = {
    CLOSED = 0,
    OPENING = 1,
    OPEN = 2,
    CLOSING = 3,
}

-- Door configuration
local DOOR_SPEED = 2.0        -- Radians per second
local DOOR_OPEN_ANGLE = math.pi / 2  -- 90 degrees
local DOOR_STAY_OPEN = 3.0    -- Seconds before auto-close
local INTERACT_DISTANCE = 2.0 -- How close player must be

-- Active doors in the current map
local doors = {}

function Doors.init()
    doors = {}
end

-- Register a door at a map position
-- direction: "ns" (north-south, blocks east-west movement) or "ew" (east-west, blocks north-south movement)
function Doors.add(x, y, direction)
    local id = x .. "," .. y
    doors[id] = {
        x = x,
        y = y,
        direction = direction or "ew",  -- "ew" = spans east-west, "ns" = spans north-south
        state = Doors.STATE.CLOSED,
        angle = 0,              -- Current rotation (0 = closed, pi/2 = open)
        timer = 0,              -- Timer for auto-close
    }
    return id
end

-- Get door at position
function Doors.getAt(x, y)
    local id = x .. "," .. y
    return doors[id]
end

-- Get all doors
function Doors.getAll()
    return doors
end

-- Check if position has a door
function Doors.isDoor(x, y)
    return doors[x .. "," .. y] ~= nil
end

-- Check if door is passable (open enough)
function Doors.isPassable(x, y)
    local door = doors[x .. "," .. y]
    if not door then return true end
    return door.angle > DOOR_OPEN_ANGLE * 0.7  -- 70% open = passable
end

-- Interact with nearest door
function Doors.interact(playerX, playerY, playerDirX, playerDirY)
    local nearestDoor = nil
    local nearestDist = INTERACT_DISTANCE

    for id, door in pairs(doors) do
        -- Calculate distance to door center
        local doorCenterX = door.x + 0.5
        local doorCenterY = door.y + 0.5
        local dx = doorCenterX - playerX
        local dy = doorCenterY - playerY
        local dist = math.sqrt(dx * dx + dy * dy)

        -- Check if player is facing the door (dot product)
        if dist > 0.1 then
            local dirToDoorX = dx / dist
            local dirToDoorY = dy / dist
            local dot = playerDirX * dirToDoorX + playerDirY * dirToDoorY

            if dist < nearestDist and dot > 0.2 then  -- Must be somewhat facing door
                nearestDist = dist
                nearestDoor = door
            end
        end
    end

    if nearestDoor then
        if nearestDoor.state == Doors.STATE.CLOSED then
            nearestDoor.state = Doors.STATE.OPENING
            return true, "Opening door..."
        elseif nearestDoor.state == Doors.STATE.OPEN then
            nearestDoor.state = Doors.STATE.CLOSING
            nearestDoor.timer = 0
            return true, "Closing door..."
        end
    end

    return false, nil
end

-- Update all doors
function Doors.update(dt)
    for id, door in pairs(doors) do
        if door.state == Doors.STATE.OPENING then
            door.angle = door.angle + DOOR_SPEED * dt
            if door.angle >= DOOR_OPEN_ANGLE then
                door.angle = DOOR_OPEN_ANGLE
                door.state = Doors.STATE.OPEN
                door.timer = 0
            end

        elseif door.state == Doors.STATE.OPEN then
            door.timer = door.timer + dt
            if door.timer >= DOOR_STAY_OPEN then
                door.state = Doors.STATE.CLOSING
            end

        elseif door.state == Doors.STATE.CLOSING then
            door.angle = door.angle - DOOR_SPEED * dt
            if door.angle <= 0 then
                door.angle = 0
                door.state = Doors.STATE.CLOSED
            end
        end
    end
end

--[[
    Ray-Door Intersection
    Returns hit info if ray hits door, nil otherwise

    Door is modeled as a thin line segment in the middle of the cell:
    - When closed (angle=0): door fills middle of cell
    - When opening: door rotates from hinge point
    - When open (angle=90): door is against the wall, mostly out of the way
]]
function Doors.rayIntersect(door, rayOriginX, rayOriginY, rayDirX, rayDirY)
    if not door then return nil end

    -- Door cell center
    local cellCenterX = door.x + 0.5
    local cellCenterY = door.y + 0.5

    -- Calculate door endpoints based on direction and angle
    local p1x, p1y, p2x, p2y
    local cosA = math.cos(door.angle)
    local sinA = math.sin(door.angle)

    if door.direction == "ew" then
        -- East-West door (blocks north-south movement when closed)
        -- Hinge on the west edge of cell
        local hingeX = door.x
        local hingeY = cellCenterY

        -- Door extends east from hinge, rotates northward when opening
        p1x = hingeX
        p1y = hingeY
        p2x = hingeX + cosA  -- When closed, extends to door.x + 1
        p2y = hingeY - sinA  -- When opening, swings north
    else
        -- North-South door (blocks east-west movement when closed)
        -- Hinge on the north edge of cell
        local hingeX = cellCenterX
        local hingeY = door.y

        -- Door extends south from hinge, rotates eastward when opening
        p1x = hingeX
        p1y = hingeY
        p2x = hingeX + sinA  -- When opening, swings east
        p2y = hingeY + cosA  -- When closed, extends to door.y + 1
    end

    -- Line segment intersection using parametric form
    -- Ray: R(t) = rayOrigin + t * rayDir, t >= 0
    -- Segment: S(s) = p1 + s * (p2 - p1), 0 <= s <= 1

    local segDirX = p2x - p1x
    local segDirY = p2y - p1y

    -- Cross product of ray direction and segment direction
    local cross = rayDirX * segDirY - rayDirY * segDirX

    -- Check if parallel (cross product near zero)
    if math.abs(cross) < 0.0001 then
        return nil
    end

    -- Vector from ray origin to segment start
    local dx = p1x - rayOriginX
    local dy = p1y - rayOriginY

    -- Calculate t (distance along ray) and s (position along segment)
    local t = (dx * segDirY - dy * segDirX) / cross
    local s = (dx * rayDirY - dy * rayDirX) / cross

    -- Check if intersection is valid:
    -- t > 0 means intersection is in front of ray
    -- 0 <= s <= 1 means intersection is on the door segment
    if t > 0.01 and s >= 0 and s <= 1 then
        return {
            distance = t,
            texCoord = s,  -- 0-1 along door surface for texturing
            hitX = rayOriginX + t * rayDirX,
            hitY = rayOriginY + t * rayDirY,
        }
    end

    return nil
end

-- Open a door at position (for NPC use)
function Doors.openAt(x, y)
    local id = math.floor(x) .. "," .. math.floor(y)
    local door = doors[id]
    if door and door.state == Doors.STATE.CLOSED then
        door.state = Doors.STATE.OPENING
        return true
    end
    return false
end

-- Check if there's a closed door at position
function Doors.isClosedDoorAt(x, y)
    local id = math.floor(x) .. "," .. math.floor(y)
    local door = doors[id]
    return door and door.state == Doors.STATE.CLOSED
end

-- Get save data
function Doors.getSaveData()
    local data = {}
    for id, door in pairs(doors) do
        data[id] = {
            x = door.x,
            y = door.y,
            direction = door.direction,
            state = door.state,
            angle = door.angle,
        }
    end
    return data
end

-- Load save data
function Doors.loadSaveData(data)
    if not data then return end
    doors = {}
    for id, doorData in pairs(data) do
        doors[id] = {
            x = doorData.x,
            y = doorData.y,
            direction = doorData.direction,
            state = doorData.state,
            angle = doorData.angle,
            timer = 0,
        }
    end
end

return Doors
