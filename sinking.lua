--[[
    Sinking Phase Intro System
    Manages the 10-minute ship flooding sequence that serves as the
    game's opening act. The USCGC Thresher's Hope gradually floods
    from stern (high X) to bow (low X), giving the player time to
    scavenge supplies before the ship reaches the ocean floor.

    During the sinking phase:
    - Water rises section by section (stern floods first)
    - Unflooded rooms act as air pockets (O2 does not drain)
    - Warnings fire at 3 min, 1 min, and 30 sec remaining
    - On completion, the game transitions to survival mode

    Designed to work with the Flooding module for per-tile water
    levels. Call Sinking.setFloodingModule(Flooding) before use.
]]

local Sinking = {}

-- Cached math functions for hot paths
local math_floor = math.floor
local math_min   = math.min
local math_max   = math.max
local math_abs   = math.abs
local math_sin   = math.sin

-- ============================================================
-- Constants
-- ============================================================

local SINK_DURATION       = 420    -- 7 minutes in seconds
local AIR_POCKET_THRESHOLD = 0.7   -- Water level below this = breathable air
local SECTION_COUNT       = 8      -- Ship divided into N sections along X axis

-- Warning thresholds in seconds remaining
local WARNING_3MIN   = 180
local WARNING_1MIN   = 60
local WARNING_30SEC  = 30

-- Warning messages (keyed by threshold for dedup)
local WARNING_MESSAGES = {
    [WARNING_3MIN]  = "WARNING: Ship flooding fast! 3 minutes until full submersion!",
    [WARNING_1MIN]  = "CRITICAL: 1 minute until the ship is fully underwater!",
    [WARNING_30SEC] = "EMERGENCY: 30 seconds! The ship is going under!",
}

local COMPLETION_MESSAGE = "The USCGC Thresher's Hope has sunk. Oxygen survival begins."

-- HUD colors (normalized 0-1)
local COLOR_BAR_BG        = {0.08, 0.08, 0.12, 0.85}
local COLOR_BAR_FILL      = {0.12, 0.35, 0.55}
local COLOR_BAR_FILL_WARN = {0.65, 0.25, 0.10}
local COLOR_BAR_BORDER    = {0.25, 0.45, 0.60, 0.9}
local COLOR_TIMER_NORMAL  = {0.75, 0.85, 0.95}
local COLOR_TIMER_WARN    = {1.0,  0.6,  0.2}
local COLOR_TIMER_CRIT    = {1.0,  0.25, 0.2}
local COLOR_LABEL         = {0.55, 0.65, 0.75}
local COLOR_WARNING_BG    = {0.0, 0.0, 0.0, 0.75}
local COLOR_WARNING_TEXT  = {1.0, 0.85, 0.3}
local COLOR_COMPLETE_TEXT = {0.4, 0.8, 1.0}

-- HUD layout
local HUD_BAR_WIDTH   = 220
local HUD_BAR_HEIGHT  = 14
local HUD_PADDING     = 10
local HUD_CORNER_R    = 4

-- Warning display
local WARNING_DISPLAY_DURATION = 4.0  -- Seconds to show each warning on screen

-- Font cache
local fontCache = {}
local function getFont(size)
    if not fontCache[size] then
        fontCache[size] = love.graphics.newFont(size)
    end
    return fontCache[size]
end

-- ============================================================
-- Module-local state
-- ============================================================

local state = {
    active          = false,   -- Currently in sinking phase
    complete        = false,   -- Sinking phase finished
    elapsed         = 0,       -- Seconds elapsed since sinking started
    progress        = 0,       -- Normalized 0-1 flooding progress

    -- Map extents (set during init or first update with map data)
    mapMinX         = 1,
    mapMaxX         = 24,

    -- Section flood schedule: computed on init
    -- Each entry: { startProgress, endProgress }
    -- Index 1 = stern (highest X), index N = bow (lowest X)
    sections        = {},

    -- Warning tracking (which thresholds have already fired)
    firedWarnings   = {},

    -- Active warning display
    activeWarning       = nil,   -- Current warning string being displayed
    activeWarningTimer  = 0,     -- Countdown for display duration

    -- Completion flag for single-fire event
    completionFired = false,
}

-- Reference to the Flooding module (injected via setFloodingModule)
local floodingModule = nil

-- ============================================================
-- Internal helpers
-- ============================================================

local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

--- Build the section flood schedule based on map X extents.
--- Sections are ordered stern-to-bow (highest X first, lowest X last).
--- Each section has a start and end progress value within 0-1.
--- Earlier sections (stern) start flooding sooner and finish sooner.
local function buildSections()
    local sections = {}
    local totalX = state.mapMaxX - state.mapMinX + 1
    if totalX < 1 then totalX = 1 end

    local sectionWidth = totalX / SECTION_COUNT

    -- Overlap factor: sections begin flooding slightly before the previous
    -- one finishes, creating a smooth wave rather than discrete steps.
    local overlap = 0.15

    for i = 1, SECTION_COUNT do
        -- i=1 is stern (highest X), i=SECTION_COUNT is bow (lowest X)
        local t = (i - 1) / SECTION_COUNT

        -- Start progress: section i begins flooding at this overall progress
        local startP = math_max(0, t - overlap)
        -- End progress: section i is fully flooded by this overall progress
        -- Last section must finish at exactly 1.0
        local endP = math_min(1.0, t + (1.0 / SECTION_COUNT) + overlap * 0.5)

        sections[i] = {
            startProgress = startP,
            endProgress   = endP,
            -- X range this section covers (stern = high X, bow = low X)
            xMin = math_floor(state.mapMaxX - i * sectionWidth) + 1,
            xMax = math_floor(state.mapMaxX - (i - 1) * sectionWidth),
        }
    end

    -- Ensure the last section ends at exactly 1.0
    if sections[SECTION_COUNT] then
        sections[SECTION_COUNT].endProgress = 1.0
    end

    -- Ensure the first section starts at exactly 0.0
    if sections[1] then
        sections[1].startProgress = 0.0
    end

    state.sections = sections
end

--- Compute the local flood level for a given section index at the current
--- overall progress. Returns 0-1 where 0 = dry, 1 = fully flooded.
local function getSectionFloodLevel(sectionIndex)
    local sec = state.sections[sectionIndex]
    if not sec then return 0 end

    local p = state.progress
    if p <= sec.startProgress then
        return 0
    elseif p >= sec.endProgress then
        return 1
    end

    -- Linear ramp within the section's active flood window
    local span = sec.endProgress - sec.startProgress
    if span <= 0 then return 1 end
    return (p - sec.startProgress) / span
end

--- Determine which section a tile X coordinate belongs to.
--- Returns section index (1 = stern, SECTION_COUNT = bow), or nil if outside.
local function getSectionForTileX(tileX)
    for i = 1, SECTION_COUNT do
        local sec = state.sections[i]
        if sec and tileX >= sec.xMin and tileX <= sec.xMax then
            return i
        end
    end
    -- Fallback: clamp to nearest section
    if tileX >= state.mapMaxX then
        return 1  -- Stern
    end
    return SECTION_COUNT  -- Bow
end

--- Format seconds as MM:SS.
local function formatTime(seconds)
    if seconds <= 0 then return "00:00" end
    local s = math_floor(seconds)
    local mins = math_floor(s / 60)
    local secs = s % 60
    return string.format("%02d:%02d", mins, secs)
end

-- ============================================================
-- Public API -- lifecycle
-- ============================================================

--- Initialize the sinking phase.
--- @param mapMinX number  Minimum tile X of the ship (bow end)
--- @param mapMaxX number  Maximum tile X of the ship (stern end)
function Sinking.init(mapMinX, mapMaxX)
    state.active          = true
    state.complete        = false
    state.elapsed         = 0
    state.progress        = 0
    state.mapMinX         = mapMinX or 1
    state.mapMaxX         = mapMaxX or 24
    state.firedWarnings   = {}
    state.activeWarning   = nil
    state.activeWarningTimer = 0
    state.completionFired = false

    buildSections()
end

--- Main update tick. Call once per frame while sinking is active.
--- Returns an events table containing any warnings or completion triggers
--- that fired this frame. Callers can inspect this to play sounds, show
--- UI notifications, or trigger transitions.
---
--- @param dt number  Delta time in seconds
--- @return table  Events: { warnings = {string,...}, completed = bool }
function Sinking.update(dt)
    local events = { warnings = {}, completed = false }

    if not state.active or state.complete then
        -- Still tick down the warning display timer even after completion
        if state.activeWarningTimer > 0 then
            state.activeWarningTimer = state.activeWarningTimer - dt
            if state.activeWarningTimer <= 0 then
                state.activeWarning = nil
            end
        end
        return events
    end

    -- Advance elapsed time
    state.elapsed = state.elapsed + dt
    state.progress = clamp01(state.elapsed / SINK_DURATION)

    -- Update the Flooding module with per-section water levels
    if floodingModule then
        -- Set room-wide water level to overall progress (used for submerged overlay)
        floodingModule.setRoomWaterLevel(state.progress)
    end

    -- Check time-based warnings
    local remaining = SINK_DURATION - state.elapsed

    for threshold, message in pairs(WARNING_MESSAGES) do
        if remaining <= threshold and not state.firedWarnings[threshold] then
            state.firedWarnings[threshold] = true
            events.warnings[#events.warnings + 1] = message
            -- Set active warning for HUD display
            state.activeWarning = message
            state.activeWarningTimer = WARNING_DISPLAY_DURATION
        end
    end

    -- Tick down warning display timer
    if state.activeWarningTimer > 0 then
        state.activeWarningTimer = state.activeWarningTimer - dt
        if state.activeWarningTimer <= 0 then
            state.activeWarning = nil
        end
    end

    -- Check for completion
    if state.progress >= 1.0 and not state.completionFired then
        state.complete = true
        state.completionFired = true
        state.progress = 1.0
        events.completed = true
        -- Fire completion warning
        state.activeWarning = COMPLETION_MESSAGE
        state.activeWarningTimer = WARNING_DISPLAY_DURATION * 1.5
    end

    return events
end

-- ============================================================
-- Query API
-- ============================================================

--- Returns true if the sinking phase is currently active (ongoing).
--- @return boolean
function Sinking.isActive()
    return state.active and not state.complete
end

--- Returns true if the sinking phase has finished.
--- @return boolean
function Sinking.isComplete()
    return state.complete
end

--- Returns the overall flooding progress (0 = dry, 1 = fully sunk).
--- @return number
function Sinking.getProgress()
    return state.progress
end

--- Returns seconds remaining until the ship is fully sunk.
--- @return number
function Sinking.getTimeRemaining()
    local remaining = SINK_DURATION - state.elapsed
    if remaining < 0 then return 0 end
    return remaining
end

--- Determine whether the player is in an air pocket at the given tile.
--- An air pocket exists when the tile is inside the ship (walkable) and
--- the local water level at that position is below AIR_POCKET_THRESHOLD.
---
--- @param playerTileX number  Player's tile X coordinate
--- @param playerTileY number  Player's tile Y coordinate
--- @param map         table   Map object with :getTile(x, y) method
--- @return boolean
function Sinking.isPlayerInAirPocket(playerTileX, playerTileY, map)
    local tx = math_floor(playerTileX)
    local ty = math_floor(playerTileY)

    -- The player must be inside the ship (on a walkable tile)
    if map then
        local tile = map:getTile(tx, ty)
        -- Walls and solid tiles are not air pockets
        if tile > 0 and tile ~= 10 and tile ~= 11 and tile ~= 12 then
            return false
        end
    end

    -- Check water level at this tile
    local waterLevel = Sinking.getWaterLevelAtTile(tx, ty)
    return waterLevel < AIR_POCKET_THRESHOLD
end

--- Get the water level at a specific tile based on the sinking schedule.
--- This is the sinking-phase contribution; the Flooding module may add
--- additional water from breach points independently.
---
--- @param tileX number  Tile X coordinate
--- @param tileY number  Tile Y coordinate (unused but included for API consistency)
--- @return number  Water level 0-1
function Sinking.getWaterLevelAtTile(tileX, tileY)
    if not state.active and not state.complete then
        return 0
    end

    if state.complete then
        return 1.0
    end

    local tx = math_floor(tileX)
    local sectionIdx = getSectionForTileX(tx)
    return getSectionFloodLevel(sectionIdx)
end

--- Immediately complete the sinking phase. Used for debug/skip.
function Sinking.skip()
    if state.complete then return end

    state.elapsed = SINK_DURATION
    state.progress = 1.0
    state.complete = true
    state.completionFired = true

    -- Set flooding to maximum
    if floodingModule then
        floodingModule.setRoomWaterLevel(1.0)
    end

    -- Display completion message
    state.activeWarning = COMPLETION_MESSAGE
    state.activeWarningTimer = WARNING_DISPLAY_DURATION * 1.5
end

-- ============================================================
-- Flooding module integration
-- ============================================================

--- Inject a reference to the Flooding module so Sinking can drive
--- room-wide water levels and per-tile flood data.
--- @param flooding table  The Flooding module table
function Sinking.setFloodingModule(flooding)
    floodingModule = flooding
end

--- Get the injected Flooding module reference (may be nil).
--- @return table|nil
function Sinking.getFloodingModule()
    return floodingModule
end

-- ============================================================
-- HUD rendering
-- ============================================================

--- Draw the sinking-phase HUD overlay.
--- Shows a countdown timer, flooding progress bar, and any active warnings.
---
--- @param screenW number  Screen width in pixels
--- @param screenH number  Screen height in pixels
function Sinking.drawHUD(screenW, screenH)
    if not state.active and not state.complete then
        -- Only draw lingering warnings after completion
        if state.activeWarning and state.activeWarningTimer > 0 then
            Sinking._drawWarning(screenW, screenH)
        end
        return
    end

    love.graphics.push("all")

    local remaining = Sinking.getTimeRemaining()
    local progress  = state.progress

    -- Position: top-center of screen
    local panelW = HUD_BAR_WIDTH + HUD_PADDING * 2 + 80
    local panelH = 58
    local panelX = (screenW - panelW) / 2
    local panelY = 8

    -- Panel background
    love.graphics.setColor(COLOR_BAR_BG[1], COLOR_BAR_BG[2], COLOR_BAR_BG[3], COLOR_BAR_BG[4])
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, HUD_CORNER_R, HUD_CORNER_R)

    -- Panel border
    love.graphics.setColor(COLOR_BAR_BORDER[1], COLOR_BAR_BORDER[2], COLOR_BAR_BORDER[3], COLOR_BAR_BORDER[4])
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH, HUD_CORNER_R, HUD_CORNER_R)

    -- Label
    local labelFont = getFont(11)
    love.graphics.setFont(labelFont)
    love.graphics.setColor(COLOR_LABEL[1], COLOR_LABEL[2], COLOR_LABEL[3])
    love.graphics.print("SHIP FLOODING", panelX + HUD_PADDING, panelY + 4)

    -- Timer
    local timerFont = getFont(16)
    love.graphics.setFont(timerFont)

    local timerColor
    if remaining <= WARNING_30SEC then
        -- Pulse the critical timer for urgency
        local pulse = 0.5 + 0.5 * math_abs(math_sin(state.elapsed * 4))
        timerColor = {
            COLOR_TIMER_CRIT[1] * pulse + (1 - pulse) * 0.5,
            COLOR_TIMER_CRIT[2] * pulse,
            COLOR_TIMER_CRIT[3] * pulse,
        }
    elseif remaining <= WARNING_1MIN then
        timerColor = COLOR_TIMER_WARN
    else
        timerColor = COLOR_TIMER_NORMAL
    end

    local timeStr = formatTime(remaining)
    local timerW = timerFont:getWidth(timeStr)
    love.graphics.setColor(timerColor[1], timerColor[2], timerColor[3])
    love.graphics.print(timeStr, panelX + panelW - HUD_PADDING - timerW, panelY + 4)

    -- Progress bar
    local barX = panelX + HUD_PADDING
    local barY = panelY + 24
    local barW = panelW - HUD_PADDING * 2
    local barH = HUD_BAR_HEIGHT

    -- Bar background
    love.graphics.setColor(0.04, 0.04, 0.08)
    love.graphics.rectangle("fill", barX, barY, barW, barH, 2, 2)

    -- Bar fill: color shifts from blue to orange/red as flooding progresses
    local fillColor
    if progress > 0.75 then
        local t = (progress - 0.75) / 0.25
        fillColor = {
            COLOR_BAR_FILL[1] + (COLOR_BAR_FILL_WARN[1] - COLOR_BAR_FILL[1]) * t,
            COLOR_BAR_FILL[2] + (COLOR_BAR_FILL_WARN[2] - COLOR_BAR_FILL[2]) * t,
            COLOR_BAR_FILL[3] + (COLOR_BAR_FILL_WARN[3] - COLOR_BAR_FILL[3]) * t,
        }
    else
        fillColor = COLOR_BAR_FILL
    end

    love.graphics.setColor(fillColor[1], fillColor[2], fillColor[3])
    love.graphics.rectangle("fill", barX, barY, barW * progress, barH, 2, 2)

    -- Bar border
    love.graphics.setColor(COLOR_BAR_BORDER[1], COLOR_BAR_BORDER[2], COLOR_BAR_BORDER[3], 0.5)
    love.graphics.rectangle("line", barX, barY, barW, barH, 2, 2)

    -- Percentage text on bar
    local pctFont = getFont(10)
    love.graphics.setFont(pctFont)
    local pctStr = math_floor(progress * 100) .. "%"
    local pctW = pctFont:getWidth(pctStr)
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.print(pctStr, barX + (barW - pctW) / 2, barY + 1)

    -- Section markers on the bar (small tick marks showing section boundaries)
    love.graphics.setColor(1, 1, 1, 0.2)
    for i = 1, SECTION_COUNT - 1 do
        local tickX = barX + (barW * i / SECTION_COUNT)
        love.graphics.line(tickX, barY, tickX, barY + barH)
    end

    -- Status text below bar
    local statusFont = getFont(10)
    love.graphics.setFont(statusFont)
    local statusStr
    if state.complete then
        statusStr = "SUNK"
    elseif progress < 0.1 then
        statusStr = "Stern flooding"
    elseif progress < 0.5 then
        statusStr = "Mid-ship flooding"
    elseif progress < 0.85 then
        statusStr = "Bow flooding"
    else
        statusStr = "Ship almost submerged"
    end
    love.graphics.setColor(COLOR_LABEL[1], COLOR_LABEL[2], COLOR_LABEL[3], 0.8)
    love.graphics.print(statusStr, barX, barY + barH + 3)

    love.graphics.pop()

    -- Draw active warning overlay (separate push/pop for layering)
    if state.activeWarning and state.activeWarningTimer > 0 then
        Sinking._drawWarning(screenW, screenH)
    end
end

--- Internal: draw the current warning message as a centered overlay.
--- Fades out over the last second of display.
function Sinking._drawWarning(screenW, screenH)
    local alpha = 1.0
    if state.activeWarningTimer < 1.0 then
        alpha = math_max(0, state.activeWarningTimer)
    end

    love.graphics.push("all")

    local warnFont = getFont(16)
    love.graphics.setFont(warnFont)

    local text = state.activeWarning
    local textW = warnFont:getWidth(text)
    local textH = warnFont:getHeight()

    local boxW = textW + 40
    local boxH = textH + 20
    local boxX = (screenW - boxW) / 2
    local boxY = screenH * 0.28

    -- Background
    love.graphics.setColor(
        COLOR_WARNING_BG[1],
        COLOR_WARNING_BG[2],
        COLOR_WARNING_BG[3],
        COLOR_WARNING_BG[4] * alpha
    )
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 6, 6)

    -- Border with warning color
    local borderColor
    if state.complete then
        borderColor = COLOR_COMPLETE_TEXT
    else
        borderColor = COLOR_WARNING_TEXT
    end
    love.graphics.setColor(borderColor[1], borderColor[2], borderColor[3], alpha * 0.8)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 6, 6)

    -- Text
    local textColor
    if state.complete then
        textColor = COLOR_COMPLETE_TEXT
    else
        textColor = COLOR_WARNING_TEXT
    end
    love.graphics.setColor(textColor[1], textColor[2], textColor[3], alpha)
    love.graphics.print(text, boxX + 20, boxY + 10)

    love.graphics.pop()
end

-- ============================================================
-- Serialization
-- ============================================================

--- Returns a table of all sinking state for serialization.
--- @return table
function Sinking.getSaveData()
    local firedCopy = {}
    for k, v in pairs(state.firedWarnings) do
        firedCopy[k] = v
    end

    return {
        active          = state.active,
        complete        = state.complete,
        elapsed         = state.elapsed,
        progress        = state.progress,
        mapMinX         = state.mapMinX,
        mapMaxX         = state.mapMaxX,
        firedWarnings   = firedCopy,
        completionFired = state.completionFired,
    }
end

--- Restore sinking state from previously saved data.
--- Gracefully handles nil or partial data tables.
--- @param data table|nil
function Sinking.loadSaveData(data)
    if not data then return end

    state.active          = data.active or false
    state.complete        = data.complete or false
    state.elapsed         = data.elapsed or 0
    state.progress        = clamp01(data.progress or 0)
    state.mapMinX         = data.mapMinX or 1
    state.mapMaxX         = data.mapMaxX or 24
    state.completionFired = data.completionFired or false

    -- Restore fired warnings
    state.firedWarnings = {}
    if data.firedWarnings then
        for k, v in pairs(data.firedWarnings) do
            state.firedWarnings[k] = v
        end
    end

    -- Clear transient display state
    state.activeWarning      = nil
    state.activeWarningTimer = 0

    -- Rebuild section schedule from restored map extents
    buildSections()

    -- Sync flooding module to restored progress
    if floodingModule and state.active then
        floodingModule.setRoomWaterLevel(state.progress)
    end
end

-- ============================================================
-- Debug / introspection
-- ============================================================

--- Returns the raw state table (read-only intent; used for debug display).
--- @return table
function Sinking.getState()
    return state
end

--- Returns the section schedule table (read-only intent; used for debug).
--- @return table
function Sinking.getSections()
    return state.sections
end

--- Returns the sink duration constant.
--- @return number
function Sinking.getDuration()
    return SINK_DURATION
end

return Sinking
