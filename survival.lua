--[[
    Survival System
    Manages player vital stats for an underwater city builder raycaster:
    oxygen, hunger, health, and depth pressure.
    Integrates with habitat zones, O2 generators, suit upgrades, and food sources.
]]

local Survival = {}

-- Cached math functions for hot-path performance
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local math_abs = math.abs

-- =============================================================================
-- Constants
-- =============================================================================

-- Oxygen
local O2_MAX_DEFAULT          = 100
local O2_DRAIN_RATE           = 1.0    -- Per second when outside habitat
local O2_REFILL_RATE          = 5.0    -- Per second when in habitat or near generator
local O2_DAMAGE_RATE          = 3.0    -- Health damage per second at 0 O2

-- Hunger
local HUNGER_MAX_DEFAULT      = 100
local HUNGER_DRAIN_RATE       = 0.5    -- Per second, always ticking
local HUNGER_SPEED_THRESHOLD  = 25     -- Below this, movement penalty applies
local HUNGER_SPEED_MULTIPLIER = 0.6    -- Speed multiplier when starving
local HUNGER_DAMAGE_RATE      = 1.0    -- Health damage per second at 0 hunger

-- Health
local HEALTH_MAX_DEFAULT      = 100
local HEALTH_REGEN_RATE       = 0.5    -- Per second when well-fed and has O2
local HEALTH_REGEN_HUNGER_MIN = 75     -- Hunger must be above this to regenerate
local HEALTH_REGEN_O2_MIN     = 10     -- O2 must be above this to regenerate

-- Pressure
local PRESSURE_BASE_DEPTH     = 0      -- Surface depth (no pressure)
local PRESSURE_DAMAGE_RATE    = 5.0    -- Health damage per second beyond suit rating
local PRESSURE_DAMAGE_SCALE   = 0.02   -- Damage scales with excess depth
local SUIT_RATING_DEFAULT     = 100    -- Default max safe depth in meters

-- Warning thresholds
local O2_WARN_LOW             = 30
local O2_WARN_CRITICAL        = 10
local HUNGER_WARN_LOW         = 30
local HUNGER_WARN_CRITICAL    = 10
local HEALTH_WARN_LOW         = 30
local HEALTH_WARN_CRITICAL    = 15
local PRESSURE_WARN_HIGH      = 0.7
local PRESSURE_WARN_CRITICAL  = 0.9

-- =============================================================================
-- Module-local state
-- =============================================================================

local state = {
    o2         = O2_MAX_DEFAULT,
    maxO2      = O2_MAX_DEFAULT,
    hunger     = HUNGER_MAX_DEFAULT,
    maxHunger  = HUNGER_MAX_DEFAULT,
    health     = HEALTH_MAX_DEFAULT,
    maxHealth  = HEALTH_MAX_DEFAULT,
    pressure   = 0,       -- Normalized 0-1, 1 = critical
    suitRating = SUIT_RATING_DEFAULT,
    alive      = true,
    depth      = 0,       -- Current depth in meters (raw value from context)
}

-- Damage log for debugging / UI feedback
local lastDamageSource = nil
local lastDamageTime   = 0

-- =============================================================================
-- Internal helpers
-- =============================================================================

-- Clamp a value between lo and hi
local function clamp(value, lo, hi)
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

-- Compute normalized pressure from depth and suit rating.
-- Returns 0 at surface, approaches 1 as depth approaches or exceeds suit rating.
local function computePressure(depth, suitRating)
    if depth <= PRESSURE_BASE_DEPTH then
        return 0
    end
    local safeRating = math_max(suitRating, 1) -- avoid division by zero
    return clamp(depth / safeRating, 0, 1)
end

-- =============================================================================
-- Public API
-- =============================================================================

--- Reset all survival stats to defaults.
function Survival.init()
    state.o2         = O2_MAX_DEFAULT
    state.maxO2      = O2_MAX_DEFAULT
    state.hunger     = HUNGER_MAX_DEFAULT
    state.maxHunger  = HUNGER_MAX_DEFAULT
    state.health     = HEALTH_MAX_DEFAULT
    state.maxHealth  = HEALTH_MAX_DEFAULT
    state.pressure   = 0
    state.suitRating = SUIT_RATING_DEFAULT
    state.alive      = true
    state.depth      = 0
    lastDamageSource = nil
    lastDamageTime   = 0
end

--- Main update tick. Call once per frame.
-- @param dt           Delta time in seconds.
-- @param context      Table with fields:
--   inHabitat         (boolean) Player is inside a sealed habitat.
--   depth             (number)  Current depth in meters.
--   suitRating        (number)  Max safe depth the suit allows.
--   nearO2Generator   (boolean) Player is near an active O2 generator.
function Survival.update(dt, context)
    if not state.alive then
        return
    end

    -- Validate context defensively; callers may pass partial tables
    local ctx = context or {}
    local inHabitat      = ctx.inHabitat == true
    local depth          = ctx.depth or 0
    local suitRating     = ctx.suitRating or state.suitRating
    local nearO2Gen      = ctx.nearO2Generator == true

    state.depth      = depth
    state.suitRating = suitRating

    -- -----------------------------------------------------------------
    -- Oxygen
    -- -----------------------------------------------------------------
    if inHabitat or nearO2Gen then
        -- Refill oxygen
        state.o2 = math_min(state.maxO2, state.o2 + O2_REFILL_RATE * dt)
    else
        -- Drain oxygen
        state.o2 = math_max(0, state.o2 - O2_DRAIN_RATE * dt)
    end

    -- Suffocation damage when O2 is depleted
    if state.o2 <= 0 then
        Survival.takeDamage(O2_DAMAGE_RATE * dt, "suffocation")
    end

    -- -----------------------------------------------------------------
    -- Hunger
    -- -----------------------------------------------------------------
    state.hunger = math_max(0, state.hunger - HUNGER_DRAIN_RATE * dt)

    -- Starvation damage when hunger is depleted
    if state.hunger <= 0 then
        Survival.takeDamage(HUNGER_DAMAGE_RATE * dt, "starvation")
    end

    -- -----------------------------------------------------------------
    -- Pressure
    -- -----------------------------------------------------------------
    state.pressure = computePressure(depth, suitRating)

    -- Pressure damage when depth exceeds suit rating
    if depth > suitRating then
        local excessDepth = depth - suitRating
        local pressureDmg = PRESSURE_DAMAGE_RATE * (1 + excessDepth * PRESSURE_DAMAGE_SCALE) * dt
        Survival.takeDamage(pressureDmg, "pressure")
    end

    -- -----------------------------------------------------------------
    -- Health regeneration
    -- -----------------------------------------------------------------
    if state.hunger > HEALTH_REGEN_HUNGER_MIN and state.o2 > HEALTH_REGEN_O2_MIN then
        state.health = math_min(state.maxHealth, state.health + HEALTH_REGEN_RATE * dt)
    end

    -- -----------------------------------------------------------------
    -- Death check
    -- -----------------------------------------------------------------
    if state.health <= 0 then
        state.health = 0
        state.alive = false
    end
end

-- =============================================================================
-- Getters
-- =============================================================================

function Survival.getO2()
    return state.o2
end

function Survival.getMaxO2()
    return state.maxO2
end

function Survival.getHunger()
    return state.hunger
end

function Survival.getMaxHunger()
    return state.maxHunger
end

function Survival.getHealth()
    return state.health
end

function Survival.getMaxHealth()
    return state.maxHealth
end

--- Returns the current normalized pressure level (0 = safe, 1 = critical).
function Survival.getPressure()
    return state.pressure
end

--- Returns true if the player is alive.
function Survival.isAlive()
    return state.alive
end

--- Returns the speed multiplier based on hunger.
-- 1.0 when hunger is adequate, reduced when starving.
function Survival.getSpeedMultiplier()
    if state.hunger < HUNGER_SPEED_THRESHOLD then
        -- Linearly interpolate between full penalty and no penalty
        local t = state.hunger / HUNGER_SPEED_THRESHOLD
        return HUNGER_SPEED_MULTIPLIER + (1 - HUNGER_SPEED_MULTIPLIER) * t
    end
    return 1.0
end

-- =============================================================================
-- Actions
-- =============================================================================

--- Apply damage to the player.
-- @param amount  Damage amount (positive number).
-- @param source  String identifying the damage source (e.g. "enemy", "pressure").
function Survival.takeDamage(amount, source)
    if not state.alive then return end
    if amount <= 0 then return end

    state.health = math_max(0, state.health - amount)
    lastDamageSource = source or "unknown"
    lastDamageTime = love.timer.getTime()

    if state.health <= 0 then
        state.health = 0
        state.alive = false
    end
end

--- Heal the player.
-- @param amount  Heal amount (positive number).
function Survival.heal(amount)
    if not state.alive then return end
    if amount <= 0 then return end

    state.health = math_min(state.maxHealth, state.health + amount)
end

--- Consume food to restore hunger.
-- @param amount  Hunger points to restore (positive number).
function Survival.consumeFood(amount)
    if not state.alive then return end
    if amount <= 0 then return end

    state.hunger = math_min(state.maxHunger, state.hunger + amount)
end

-- =============================================================================
-- Warnings
-- =============================================================================

--- Returns an array of active warning strings describing the player's condition.
-- Ordered from most critical to least critical.
function Survival.getWarnings()
    local warnings = {}

    if not state.alive then
        warnings[#warnings + 1] = "DEAD"
        return warnings
    end

    -- Health warnings
    if state.health <= HEALTH_WARN_CRITICAL then
        warnings[#warnings + 1] = "CRITICAL: Health extremely low!"
    elseif state.health <= HEALTH_WARN_LOW then
        warnings[#warnings + 1] = "WARNING: Health low"
    end

    -- Oxygen warnings
    if state.o2 <= 0 then
        warnings[#warnings + 1] = "CRITICAL: No oxygen! Taking damage!"
    elseif state.o2 <= O2_WARN_CRITICAL then
        warnings[#warnings + 1] = "CRITICAL: Oxygen nearly depleted!"
    elseif state.o2 <= O2_WARN_LOW then
        warnings[#warnings + 1] = "WARNING: Oxygen low"
    end

    -- Hunger warnings
    if state.hunger <= 0 then
        warnings[#warnings + 1] = "CRITICAL: Starving! Taking damage!"
    elseif state.hunger <= HUNGER_WARN_CRITICAL then
        warnings[#warnings + 1] = "CRITICAL: Severe hunger!"
    elseif state.hunger <= HUNGER_WARN_LOW then
        warnings[#warnings + 1] = "WARNING: Getting hungry"
    end

    -- Pressure warnings
    if state.pressure >= PRESSURE_WARN_CRITICAL then
        warnings[#warnings + 1] = "CRITICAL: Extreme pressure! Suit failing!"
    elseif state.pressure >= PRESSURE_WARN_HIGH then
        warnings[#warnings + 1] = "WARNING: High pressure - approaching suit limit"
    end

    -- Hunger speed penalty notification
    if state.hunger > 0 and state.hunger < HUNGER_SPEED_THRESHOLD then
        warnings[#warnings + 1] = "Hunger slowing movement"
    end

    return warnings
end

-- =============================================================================
-- Setters for max stat upgrades
-- =============================================================================

function Survival.setMaxO2(value)
    state.maxO2 = math_max(1, value)
    state.o2 = math_min(state.o2, state.maxO2)
end

function Survival.setMaxHunger(value)
    state.maxHunger = math_max(1, value)
    state.hunger = math_min(state.hunger, state.maxHunger)
end

function Survival.setMaxHealth(value)
    state.maxHealth = math_max(1, value)
    state.health = math_min(state.health, state.maxHealth)
end

-- =============================================================================
-- Save / Load
-- =============================================================================

--- Returns a table of all survival data for serialization.
function Survival.getSaveData()
    return {
        o2         = state.o2,
        maxO2      = state.maxO2,
        hunger     = state.hunger,
        maxHunger  = state.maxHunger,
        health     = state.health,
        maxHealth  = state.maxHealth,
        suitRating = state.suitRating,
        alive      = state.alive,
        depth      = state.depth,
    }
end

--- Restore survival state from previously saved data.
-- Gracefully handles nil or partial data tables.
function Survival.loadSaveData(data)
    if not data then return end

    state.o2         = data.o2         or O2_MAX_DEFAULT
    state.maxO2      = data.maxO2      or O2_MAX_DEFAULT
    state.hunger     = data.hunger     or HUNGER_MAX_DEFAULT
    state.maxHunger  = data.maxHunger  or HUNGER_MAX_DEFAULT
    state.health     = data.health     or HEALTH_MAX_DEFAULT
    state.maxHealth  = data.maxHealth  or HEALTH_MAX_DEFAULT
    state.suitRating = data.suitRating or SUIT_RATING_DEFAULT
    state.alive      = data.alive
    state.depth      = data.depth      or 0

    -- Handle the boolean default: if alive was not saved, assume alive when health > 0
    if state.alive == nil then
        state.alive = state.health > 0
    end

    -- Clamp values to prevent corruption
    state.o2      = clamp(state.o2,      0, state.maxO2)
    state.hunger  = clamp(state.hunger,  0, state.maxHunger)
    state.health  = clamp(state.health,  0, state.maxHealth)
    state.pressure = computePressure(state.depth, state.suitRating)
end

-- =============================================================================
-- Debug / Introspection
-- =============================================================================

--- Returns the raw state table (read-only intent; used for HUD rendering).
function Survival.getState()
    return state
end

--- Returns the source of the last damage taken and when it occurred.
function Survival.getLastDamage()
    return lastDamageSource, lastDamageTime
end

return Survival
