--[[
    Crew / Population System
    Manages rescued survivors and citizen role assignments for an
    underwater city builder raycaster.

    Survivors are found as sprites in the world and rescued when the
    player approaches within rescue range. Each crew member has a name,
    a role, and can be assigned to a building tile. Assigned crew provide
    a multiplicative bonus to the building they occupy, based on their role.

    Crew capacity is limited by the number of habitat_module buildings
    placed in the world (2 crew per module).
]]

local Crew = {}

-- Cached math functions for hot-path performance
local math_floor = math.floor
local math_min   = math.min
local math_max   = math.max

-- =============================================================================
-- Constants
-- =============================================================================

local CREW_PER_HABITAT        = 2       -- Max crew granted per habitat_module
local DEFAULT_ROLE_BONUS      = 0.10    -- Base bonus per assigned crew member
local RESCUE_RADIUS           = 1.5     -- Tile distance to auto-rescue a survivor

-- =============================================================================
-- Role definitions
-- =============================================================================

local ROLES = {
    engineer = {
        id          = "engineer",
        name        = "Engineer",
        description = "Boosts power output of assigned building.",
        bonusType   = "power",
        bonusMult   = 0.20,
        color       = {0.9, 0.7, 0.2},
    },
    scientist = {
        id          = "scientist",
        name        = "Scientist",
        description = "Boosts research speed of assigned building.",
        bonusType   = "research",
        bonusMult   = 0.25,
        color       = {0.3, 0.6, 0.9},
    },
    guard = {
        id          = "guard",
        name        = "Guard",
        description = "Boosts turret damage and range of assigned building.",
        bonusType   = "defense",
        bonusMult   = 0.15,
        color       = {0.8, 0.3, 0.3},
    },
    medic = {
        id          = "medic",
        name        = "Medic",
        description = "Boosts healing output of assigned building.",
        bonusType   = "healing",
        bonusMult   = 0.20,
        color       = {0.3, 0.9, 0.4},
    },
    worker = {
        id          = "worker",
        name        = "Worker",
        description = "General purpose. Provides a small bonus to any building.",
        bonusType   = "general",
        bonusMult   = DEFAULT_ROLE_BONUS,
        color       = {0.7, 0.7, 0.7},
    },
}

-- Ordered role list for deterministic UI iteration
local ROLE_ORDER = {"engineer", "scientist", "guard", "medic", "worker"}

-- =============================================================================
-- Name generation pools
-- =============================================================================

local FIRST_NAMES = {
    "Adams", "Blake", "Chen", "Diaz", "Ellis",
    "Flynn", "Grant", "Hayes", "Ivanova", "Jensen",
    "Kovac", "Lin", "Mason", "Nguyen", "Ortiz",
    "Park", "Quinn", "Reyes", "Singh", "Torres",
    "Ueda", "Vasquez", "Webb", "Xu", "Young",
    "Zhao", "Brooks", "Cruz", "Dahl", "Erikson",
}

local RANKS = {
    "PO3", "PO2", "PO1", "CPO", "SCPO",
    "SN", "SA", "FN", "BM3", "MK2",
    "ET1", "OS2", "EM3", "DC1", "GM2",
}

-- =============================================================================
-- Module-local state
-- =============================================================================

local nextId     = 1
local members    = {}     -- { [crewId] = memberData }
local assignments = {}    -- { ["tileX,tileY"] = { crewId1, crewId2, ... } }

-- =============================================================================
-- Internal helpers
-- =============================================================================

local function tileKey(tileX, tileY)
    return math_floor(tileX) .. "," .. math_floor(tileY)
end

--- Count the total number of habitat_module buildings in the placed buildings list.
--- @param placedBuildings table  Array or map of placed buildings, each with a .type field.
--- @return number  Total habitat module count.
local function countHabitats(placedBuildings)
    if not placedBuildings then return 0 end

    local count = 0
    for _, building in pairs(placedBuildings) do
        if building.type == "habitat_module" or building.buildingType == "habitat_module" then
            count = count + 1
        end
    end
    return count
end

--- Generate a random crew name from the name pools.
local function generateName()
    local rank = RANKS[math.random(#RANKS)]
    local name = FIRST_NAMES[math.random(#FIRST_NAMES)]
    return rank .. " " .. name
end

--- Pick a random role id.
local function randomRole()
    return ROLE_ORDER[math.random(#ROLE_ORDER)]
end

--- Remove a crewId from the assignments index for a given tile key.
local function removeFromAssignmentIndex(key, crewId)
    local list = assignments[key]
    if not list then return end

    for i = #list, 1, -1 do
        if list[i] == crewId then
            table.remove(list, i)
            break
        end
    end

    -- Clean up empty lists
    if #list == 0 then
        assignments[key] = nil
    end
end

-- =============================================================================
-- Public API -- Lifecycle
-- =============================================================================

--- Reset all crew state to empty.
function Crew.init()
    nextId      = 1
    members     = {}
    assignments = {}
end

-- =============================================================================
-- Public API -- Crew management
-- =============================================================================

--- Add a new crew member.
--- @param name string|nil  Display name (auto-generated if nil).
--- @param role string|nil  Role id from ROLES (defaults to "worker").
--- @return number  The new crew member's id.
function Crew.addMember(name, role)
    local id = nextId
    nextId = nextId + 1

    -- Validate role; fall back to worker
    if not role or not ROLES[role] then
        role = "worker"
    end

    members[id] = {
        id               = id,
        name             = name or generateName(),
        role             = role,
        assignedBuilding = nil,   -- "tileX,tileY" or nil
        rescuedTime      = love.timer.getTime(),
        morale           = 1.0,   -- 0-1, reserved for future use
    }

    return id
end

--- Remove a crew member entirely.
--- Also cleans up any building assignment.
--- @param crewId number
function Crew.removeMember(crewId)
    local member = members[crewId]
    if not member then return end

    -- Unassign first
    if member.assignedBuilding then
        removeFromAssignmentIndex(member.assignedBuilding, crewId)
    end

    members[crewId] = nil
end

--- Assign a crew member to a building at the given tile coordinates.
--- If the member is already assigned elsewhere, they are unassigned first.
--- @param crewId number
--- @param buildingTileX number  Integer tile X of the building.
--- @param buildingTileY number  Integer tile Y of the building.
--- @return boolean  True if assignment succeeded.
function Crew.assign(crewId, buildingTileX, buildingTileY)
    local member = members[crewId]
    if not member then return false end

    local key = tileKey(buildingTileX, buildingTileY)

    -- Unassign from previous building if applicable
    if member.assignedBuilding then
        removeFromAssignmentIndex(member.assignedBuilding, crewId)
    end

    -- Add to new assignment
    if not assignments[key] then
        assignments[key] = {}
    end
    assignments[key][#assignments[key] + 1] = crewId

    member.assignedBuilding = key
    return true
end

--- Unassign a crew member from their current building.
--- @param crewId number
function Crew.unassign(crewId)
    local member = members[crewId]
    if not member then return end

    if member.assignedBuilding then
        removeFromAssignmentIndex(member.assignedBuilding, crewId)
        member.assignedBuilding = nil
    end
end

-- =============================================================================
-- Public API -- Queries
-- =============================================================================

--- Get the total number of active crew members.
--- @return number
function Crew.getCount()
    local count = 0
    for _ in pairs(members) do
        count = count + 1
    end
    return count
end

--- Get the maximum crew capacity based on placed habitat_module buildings.
--- @param placedBuildings table|nil  The placed buildings collection.
--- @return number
function Crew.getCapacity(placedBuildings)
    return countHabitats(placedBuildings) * CREW_PER_HABITAT
end

--- Get a single crew member's data by id.
--- @param crewId number
--- @return table|nil  Member data table, or nil if not found.
function Crew.getMember(crewId)
    return members[crewId]
end

--- Get all crew members as a table keyed by id.
--- Returns the internal table (read-only intent).
--- @return table
function Crew.getAll()
    return members
end

--- Get the list of crew assigned to a specific building tile.
--- @param tileX number
--- @param tileY number
--- @return table  Array of member data tables (may be empty).
function Crew.getAssignedTo(tileX, tileY)
    local key = tileKey(tileX, tileY)
    local list = assignments[key]
    if not list then return {} end

    local result = {}
    for _, crewId in ipairs(list) do
        local member = members[crewId]
        if member then
            result[#result + 1] = member
        end
    end
    return result
end

--- Calculate the role-based bonus multiplier for a building at the given tile.
--- Returns a value >= 1.0. Each assigned crew member adds their role's bonus.
--- For example, 2 engineers assigned to a power building = 1.0 + 0.20 + 0.20 = 1.40.
--- @param tileX number
--- @param tileY number
--- @return number  Multiplicative bonus (1.0 = no bonus).
function Crew.getRoleBonus(tileX, tileY)
    local key = tileKey(tileX, tileY)
    local list = assignments[key]
    if not list or #list == 0 then return 1.0 end

    local bonus = 1.0
    for _, crewId in ipairs(list) do
        local member = members[crewId]
        if member then
            local roleDef = ROLES[member.role]
            if roleDef then
                bonus = bonus + roleDef.bonusMult * member.morale
            else
                bonus = bonus + DEFAULT_ROLE_BONUS
            end
        end
    end
    return bonus
end

--- Get a specific role bonus type breakdown for a building tile.
--- Returns a table { power = X, research = Y, defense = Z, healing = W, general = V }
--- where each value is the total bonus from that type of crew at this tile.
--- @param tileX number
--- @param tileY number
--- @return table  Bonus breakdown by type.
function Crew.getRoleBonusBreakdown(tileX, tileY)
    local key = tileKey(tileX, tileY)
    local list = assignments[key]
    local breakdown = { power = 0, research = 0, defense = 0, healing = 0, general = 0 }

    if not list then return breakdown end

    for _, crewId in ipairs(list) do
        local member = members[crewId]
        if member then
            local roleDef = ROLES[member.role]
            if roleDef then
                local bonusType = roleDef.bonusType
                breakdown[bonusType] = (breakdown[bonusType] or 0) + roleDef.bonusMult * member.morale
            end
        end
    end

    return breakdown
end

--- Get the list of all available role definitions.
--- @return table  Array of role definition tables in display order.
function Crew.getAvailableRoles()
    local result = {}
    for _, roleId in ipairs(ROLE_ORDER) do
        result[#result + 1] = ROLES[roleId]
    end
    return result
end

--- Get a single role definition by id.
--- @param roleId string
--- @return table|nil
function Crew.getRole(roleId)
    return ROLES[roleId]
end

--- Get the number of unassigned crew members.
--- @return number
function Crew.getUnassignedCount()
    local count = 0
    for _, member in pairs(members) do
        if not member.assignedBuilding then
            count = count + 1
        end
    end
    return count
end

--- Get all unassigned crew members.
--- @return table  Array of member data tables.
function Crew.getUnassigned()
    local result = {}
    for _, member in pairs(members) do
        if not member.assignedBuilding then
            result[#result + 1] = member
        end
    end
    return result
end

--- Get crew members filtered by role.
--- @param roleId string
--- @return table  Array of member data tables.
function Crew.getByRole(roleId)
    local result = {}
    for _, member in pairs(members) do
        if member.role == roleId then
            result[#result + 1] = member
        end
    end
    return result
end

-- =============================================================================
-- Public API -- Update
-- =============================================================================

--- Main update tick. Handles rescue proximity checks and capacity enforcement.
--- @param dt number  Delta time in seconds.
--- @param placedBuildings table|nil  Placed buildings for habitat capacity check.
function Crew.update(dt, placedBuildings)
    -- Capacity is not enforced by removing crew; it only prevents new rescues.
    -- This avoids the punishing case of destroying a habitat and losing crew.
    -- The UI should warn the player when over capacity.
end

-- =============================================================================
-- Public API -- Save / Load
-- =============================================================================

--- Serialize all crew data for saving.
--- @return table
function Crew.getSaveData()
    local memberList = {}
    for id, member in pairs(members) do
        memberList[#memberList + 1] = {
            id               = member.id,
            name             = member.name,
            role             = member.role,
            assignedBuilding = member.assignedBuilding,
            rescuedTime      = member.rescuedTime,
            morale           = member.morale,
        }
    end

    return {
        nextId  = nextId,
        members = memberList,
    }
end

--- Restore crew state from saved data.
--- Gracefully handles nil or partial data.
--- @param data table|nil
function Crew.loadSaveData(data)
    if not data then return end

    Crew.init()

    nextId = data.nextId or 1

    if data.members then
        for _, saved in ipairs(data.members) do
            if saved.id and saved.name then
                local id = saved.id
                local role = saved.role
                if not ROLES[role] then
                    role = "worker"
                end

                members[id] = {
                    id               = id,
                    name             = saved.name,
                    role             = role,
                    assignedBuilding = saved.assignedBuilding,
                    rescuedTime      = saved.rescuedTime or 0,
                    morale           = saved.morale or 1.0,
                }

                -- Rebuild assignment index
                if saved.assignedBuilding then
                    local key = saved.assignedBuilding
                    if not assignments[key] then
                        assignments[key] = {}
                    end
                    assignments[key][#assignments[key] + 1] = id
                end

                -- Ensure nextId stays ahead of all loaded ids
                if id >= nextId then
                    nextId = id + 1
                end
            end
        end
    end
end

return Crew
