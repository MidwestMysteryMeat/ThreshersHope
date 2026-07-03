--[[
    Narrative / Story System
    Manages discoverable log entries, story progression triggers, and a
    codex viewer for an underwater city builder raycaster.

    Log entries are found as pickup items in the world. Each log has an id,
    title, text body, category, and ordering number. Categories group logs
    for the codex viewer. Story events are triggered by gameplay milestones
    and display narrative messages.

    The story of the USCGC Thresher's Hope:
    A Coast Guard cutter sank in deep water during a storm. The player, a
    survivor, must build an underwater base, rescue crew, and uncover what
    lies in the deep -- or find a way back to the surface.
]]

local Narrative = {}

-- Cached math functions
local math_floor = math.floor
local math_min   = math.min
local math_max   = math.max

-- =============================================================================
-- Font cache
-- =============================================================================

local fontCache = {}
local function getFont(size)
    if not fontCache[size] then
        fontCache[size] = love.graphics.newFont(size)
    end
    return fontCache[size]
end

-- =============================================================================
-- Categories
-- =============================================================================

local CATEGORIES = {
    { id = "ship_log",   name = "Ship's Log",     color = {0.7, 0.7, 0.8} },
    { id = "personal",   name = "Personal Logs",   color = {0.6, 0.8, 0.7} },
    { id = "scientific", name = "Scientific Notes", color = {0.5, 0.7, 0.9} },
    { id = "warning",    name = "Warnings",         color = {0.9, 0.5, 0.3} },
    { id = "precursor",  name = "Precursor",        color = {0.7, 0.4, 0.9} },
}

-- Category id -> definition for quick lookup
local CATEGORY_MAP = {}
for _, cat in ipairs(CATEGORIES) do
    CATEGORY_MAP[cat.id] = cat
end

-- =============================================================================
-- Log definitions (20 entries telling the story)
-- =============================================================================

Narrative.LOGS = {
    -- =========================================================================
    -- SHIP'S LOG -- The sinking and its immediate aftermath
    -- =========================================================================
    {
        id       = "ship_log_01",
        title    = "Captain's Log - Final Entry",
        text     = "USCGC Thresher's Hope, 0347 hours. Storm came out of nowhere -- not on any forecast, not on radar until it was on top of us. Hull breach on the port side below the waterline. We are taking on water faster than the pumps can handle. I have ordered all hands to abandon ship. God help us, we are 200 miles from the nearest coast.\n\nTo whoever reads this: we did not go down without a fight.\n\n-- Captain R. Morales",
        category = "ship_log",
        order    = 1,
    },
    {
        id       = "ship_log_02",
        title    = "Bridge Recording Fragment",
        text     = "[AUTOMATED LOG - BRIDGE INSTRUMENTS]\nTimestamp: 03:52:17\nDepth below keel: READING ERROR\nWind speed: 94 knots\nBarometric pressure: 27.2 inHg (CRITICAL LOW)\n\nNote: Barometric pressure dropped 1.8 inHg in 11 minutes. This is not consistent with any known meteorological phenomenon. Forwarding to NOAA for review.\n\n[TRANSMISSION FAILED - ANTENNA ARRAY OFFLINE]",
        category = "ship_log",
        order    = 2,
    },
    {
        id       = "ship_log_03",
        title    = "Damage Control Report",
        text     = "DC Team Alpha reporting. Compartments 3 through 7 are flooded. Bulkhead between 7 and 8 is holding but I can hear it groaning. The water -- it's not right. It's warm. Seawater shouldn't be warm at this depth.\n\nAlso, the hull breach pattern doesn't match storm damage. It looks like something punched through from the outside. Edges bent inward, not outward.\n\nI'm sealing what I can. Someone needs to see this.\n\n-- DC1 Kovac",
        category = "ship_log",
        order    = 3,
    },
    {
        id       = "ship_log_04",
        title    = "Last Radio Transmission",
        text     = "[RADIO LOG - ENCRYPTED CG CHANNEL]\n\nTHRESHER'S HOPE: Mayday, mayday, mayday. This is USCGC Thresher's Hope, position approximately--\n[STATIC]\nTHRESHER'S HOPE: --going down. Repeat, we are going down. Crew abandoning ship. Request immediate--\n[STATIC]\nDISTRICT 7: Thresher's Hope, District Seven. Say again your position.\nTHRESHER'S HOPE: Position is-- [PAUSE] --that can't be right. The GPS is showing coordinates in the mid-Atlantic. We were in the Gulf. How did--\n[SIGNAL LOST]",
        category = "ship_log",
        order    = 4,
    },

    -- =========================================================================
    -- PERSONAL LOGS -- Crew members' experiences after the sinking
    -- =========================================================================
    {
        id       = "personal_01",
        title    = "PO2 Chen - Day 1",
        text     = "I woke up on the ocean floor inside what's left of the forward section. My dive suit's emergency seal held. Air for maybe six hours.\n\nI can see others through the portholes -- some moving, some not. The water here is crystal clear despite the depth. I can see the bottom, stretching out in every direction. Rocky formations, some kind of vegetation I've never seen in any manual.\n\nThe ship split into three sections on the way down. I need to find the others.\n\nI need to find air.",
        category = "personal",
        order    = 1,
    },
    {
        id       = "personal_02",
        title    = "SN Adams - First Shelter",
        text     = "We got lucky. The engine room section landed mostly intact, and the watertight doors held on decks 2 and 3. We've got a pocket of trapped air in here -- stale, but breathable.\n\nSix of us so far. Chen, myself, Kovac, Torres, Park, and Webb. No sign of the Captain or the bridge crew.\n\nKovac says she can rig the backup generator if we can find fuel. Torres found some ration packs floating in the galley. It's not much.\n\nWe're alive. For now, that's enough.",
        category = "personal",
        order    = 2,
    },
    {
        id       = "personal_03",
        title    = "CPO Torres - The Outside",
        text     = "I went outside today in a salvaged dive rig. Had to see what we're dealing with.\n\nWe're deeper than any recreational diver has ever been, but somehow the pressure isn't crushing us. The suits' gauges read 180 meters, but my body feels like I'm at 30. Something about this water is different.\n\nThere are structures down here. Not natural formations -- I mean walls. Arches. Carved stone covered in symbols, half-buried in sediment. They look ancient. Impossibly ancient.\n\nWe are not the first to find this place.",
        category = "personal",
        order    = 3,
    },
    {
        id       = "personal_04",
        title    = "BM3 Park - Night Watch",
        text     = "Can't sleep. None of us can. It's the sounds. The hull creaks -- that's normal for a wreck settling. But there's something else. A low thrumming, almost below hearing. It comes and goes, like breathing.\n\nWebb says it's thermal vents. Torres says it's tidal currents hitting the rock formations. Nobody says what we're all thinking.\n\nSomething is out there. Something big. I saw a shadow pass over the viewport during my watch. Blocked out all the bioluminescence for a full three seconds.\n\nThree. Seconds.",
        category = "personal",
        order    = 4,
    },
    {
        id       = "personal_05",
        title    = "EM3 Webb - Engineering Notes",
        text     = "Good news and bad news. Good: I got the backup generator running. We have power. Lights, heating, the water recycler. Bad: fuel will last maybe two weeks at conservation rates.\n\nBut here's the thing -- the crystal formations Chen found? They conduct electricity. Not like copper, not like anything I've studied. They amplify it. I wired a small piece into the generator's output circuit and got 40 percent more wattage from the same fuel burn.\n\nI don't understand the physics. But I'll take it.\n\nWe can build something here. We have to.",
        category = "personal",
        order    = 5,
    },

    -- =========================================================================
    -- SCIENTIFIC NOTES -- Discoveries about the environment
    -- =========================================================================
    {
        id       = "scientific_01",
        title    = "Water Analysis - Anomalous Properties",
        text     = "ANALYSIS LOG - PO1 Singh (Medical/Science)\n\nThe seawater here does not match any known oceanic composition. Key findings:\n- Dissolved oxygen content is 340 percent above normal\n- Trace minerals include compounds not in the periodic table\n- Water pressure is locally reduced in a roughly spherical zone, radius ~2 km\n- Temperature is stable at 12C despite thermal vent proximity\n\nHypothesis: Something is maintaining this environment artificially. The reduced pressure zone is the only reason we survived the descent. Whatever is down here wanted us alive.\n\nOr needed us alive.",
        category = "scientific",
        order    = 1,
    },
    {
        id       = "scientific_02",
        title    = "Biological Survey - Local Fauna",
        text     = "Day 9. Cataloging organisms observed near the base.\n\nSmall bioluminescent fish, schooling behavior. Non-aggressive. Some are drawn to our lights.\n\nLarger eel-like creatures, 2-3 meters. Territorial but avoidable. Electric discharge capability -- stay clear.\n\nCrustaceans in the rock formations. Edible (Torres confirmed, voluntarily). Taste like crab. Rich in protein.\n\nAnd then there are the shadows. Something much larger patrols the perimeter of the pressure zone. Never comes close enough to identify. Sonar returns are... confused. As if the creature absorbs sound.\n\nClassification: Unknown. Threat level: Unknown. Recommendation: Do not attract attention.",
        category = "scientific",
        order    = 2,
    },
    {
        id       = "scientific_03",
        title    = "Crystal Formation Analysis",
        text     = "The crystals are not geological. They are grown. Under magnification, the internal structure shows repeating lattice patterns too perfect for natural formation. They pulse with a faint light when subjected to electrical current -- not heat luminescence, something else.\n\nMore importantly: they respond to proximity. When a human stands within one meter, the crystal's light output increases measurably. It's reacting to us. To our bioelectric field.\n\nWebb has been using them for power. I have been wondering if we should stop.\n\nThe crystals are technology. The question is: whose?",
        category = "scientific",
        order    = 3,
    },
    {
        id       = "scientific_04",
        title    = "Depth Zone Mapping",
        text     = "We've established the basic structure of this region:\n\nZone 1 - The Shallows (0-50m): Wreck site, initial base. Rich in salvageable scrap.\nZone 2 - Mid-Depth (50-150m): Crystal deposits, thermal vents. Moderate fauna.\nZone 3 - The Deep (150-300m): Precursor ruins begin. Hostile fauna. Pressure anomalies.\nZone 4 - The Abyss (300-500m): Extensive ruins. Unknown structures. Extreme danger.\nZone 5 - The Trench (500m+): Uncharted. Sonar cannot penetrate. The thrumming sound originates here.\n\nNo one has gone below 300 meters and returned. I'm not sure I want to know why.\n\nBut we have to. The answer to getting home is down there. I'm certain of it.",
        category = "scientific",
        order    = 4,
    },

    -- =========================================================================
    -- WARNINGS -- Danger and escalation
    -- =========================================================================
    {
        id       = "warning_01",
        title    = "Emergency Beacon - Do Not Approach",
        text     = "[AUTOMATED EMERGENCY BEACON - REPEATING]\n\nATTENTION: Survivor camp at grid reference DELTA-7 has been abandoned. Breach event at 0200 hours. Hull failure was not structural -- external force applied to reinforced wall.\n\nFour crew members unaccounted for.\n\nDo NOT approach DELTA-7. Do NOT use active sonar in the vicinity.\n\nSomething heard us. Something came.\n\n[BEACON SIGNAL DEGRADES]",
        category = "warning",
        order    = 1,
    },
    {
        id       = "warning_02",
        title    = "Quarantine Notice - Sector 9",
        text     = "BY ORDER OF ACTING COMMANDER CHEN:\n\nSector 9 (deep cavern system, bearing 270 from main base) is hereby quarantined. No personnel are to enter without escort and full environmental suits.\n\nReason: Recon team reported disorientation, auditory hallucinations, and compulsive behavior near the large precursor structure at sector center. ET1 Vasquez had to be physically restrained from walking into an unlit tunnel. She says something was calling her.\n\nShe says it knew her name.\n\nQuarantine is effective immediately and indefinite.",
        category = "warning",
        order    = 2,
    },
    {
        id       = "warning_03",
        title    = "Leviathan Protocol",
        text     = "To all surviving crew and personnel:\n\nWe have confirmed the existence of at least one macro-fauna organism exceeding 40 meters in length. Designation: LEVIATHAN.\n\nBehavioral observations:\n- Patrols the boundary of the reduced-pressure zone\n- Appears to be territorial, not predatory (it is guarding something)\n- Reacts aggressively to active sonar, bright lights, and large movements\n- Has NOT breached the inner perimeter -- yet\n\nProtocol: Minimize acoustic signature. No unnecessary external lighting. Travel in pairs. If you see it, DO NOT RUN. Stay still. Wait for it to pass.\n\nIt is ancient. It is patient. Do not give it a reason.",
        category = "warning",
        order    = 3,
    },

    -- =========================================================================
    -- PRECURSOR -- The deep mystery
    -- =========================================================================
    {
        id       = "precursor_01",
        title    = "Ruin Translation - Fragment Alpha",
        text     = "[PARTIAL TRANSLATION - PRECURSOR GLYPHS]\n\nContext: Wall inscription, Sector 9 entrance\n\n\"...those who descend are chosen. The deep provides. The deep protects. The deep remembers.\"\n\n\"...a city beneath the water, built for those who would endure. When the surface world ends, the builders will remain.\"\n\n\"...the guardian sleeps at the threshold. It wakes for the unworthy. It guides the chosen.\"\n\nNote: These inscriptions pre-date any known human civilization by a factor I cannot calculate. The language shares structural elements with Proto-Indo-European but is far, far older.\n\nWhoever built this place anticipated our arrival. Not humanity's arrival. Ours.",
        category = "precursor",
        order    = 1,
    },
    {
        id       = "precursor_02",
        title    = "Ruin Translation - Fragment Beta",
        text     = "[PARTIAL TRANSLATION - PRECURSOR GLYPHS]\n\nContext: Central chamber, Abyss-level ruin complex\n\n\"...the storm is not weather. It is a door. When the conditions align, the door opens and the sea takes what is meant for the deep.\"\n\n\"...the builders came from above, long before the ice. They saw what was coming. They built downward.\"\n\n\"...the crystals are seeds. They grow in the presence of thought. They are the walls and the light and the memory of this place.\"\n\n\"...the Ascent is earned, not given. Build. Survive. Prove worthy. Then the deep releases you -- or you become part of it, as we did.\"\n\nI think the storm that sank us was not an accident. I think this place called us here.",
        category = "precursor",
        order    = 2,
    },
    {
        id       = "precursor_03",
        title    = "The Signal From Below",
        text     = "I went deeper than anyone else. Past the abyss, into the trench. Alone.\n\nThe thrumming is not a sound. It is a signal. Repeating. Patient. It has been repeating for longer than human civilization has existed.\n\nAt the bottom of the trench there is a structure. Not ruins -- intact. Pristine. Lights still on after millennia. A door, sealed, with a single glyph above it.\n\nThe glyph translates to one word: WELCOME.\n\nI did not open it. I am not ready. None of us are. Not yet.\n\nBut we will be. We will build what we need, learn what we must, and when we are ready, we will open that door.\n\nAnd we will either find our way home, or discover why we were brought here.\n\n-- Acting Commander Chen",
        category = "precursor",
        order    = 3,
    },
}

-- Build lookup tables from LOGS
local logById    = {}   -- { [logId] = logDef }
local logOrder   = {}   -- Array of log ids sorted by (category, order)
for _, log in ipairs(Narrative.LOGS) do
    logById[log.id] = log
end

-- Sort for codex display: group by category order, then by log order
do
    -- Build category order map
    local catOrder = {}
    for i, cat in ipairs(CATEGORIES) do
        catOrder[cat.id] = i
    end

    -- Build sorted log id list
    for _, log in ipairs(Narrative.LOGS) do
        logOrder[#logOrder + 1] = log.id
    end
    table.sort(logOrder, function(a, b)
        local la = logById[a]
        local lb = logById[b]
        local ca = catOrder[la.category] or 99
        local cb = catOrder[lb.category] or 99
        if ca ~= cb then return ca < cb end
        return (la.order or 0) < (lb.order or 0)
    end)
end

-- =============================================================================
-- Story events (triggered by gameplay milestones)
-- =============================================================================

local EVENTS = {
    first_base = {
        id      = "first_base",
        message = "You seal the last panel into place. Air hisses into the chamber. For the first time since the sinking, you take a breath that doesn't taste of saltwater and fear. This is home now.",
    },
    first_crew = {
        id      = "first_crew",
        message = "A figure moves in the murky water outside -- human. You pull them through the airlock. They cough, gasp, stare at you with wide eyes. 'I thought I was the only one left,' they whisper. You are not alone.",
    },
    first_power = {
        id      = "first_power",
        message = "The generator coughs, sputters, and catches. Lights flicker on throughout the habitat. In the sudden brightness, you can see the full extent of what you've built. It's ugly. It's crude. It's beautiful.",
    },
    first_research = {
        id      = "first_research",
        message = "The scanner hums to life, painting the surrounding seabed in ghostly green. Deposits of crystal, veins of metal, and -- there. Structures. Not natural. Not human. Old beyond reckoning.",
    },
    first_deep = {
        id      = "first_deep",
        message = "The pressure gauge climbs past 150 meters. Your hull groans. Something moves in the darkness below -- vast and slow. You've crossed into territory that doesn't belong to the living.",
    },
    first_precursor = {
        id      = "first_precursor",
        message = "The symbols on the wall glow when you approach. Not light -- something else. Understanding. For a moment, you can read them as clearly as English, and what they say makes your blood run cold.",
    },
    first_death = {
        id      = "first_death",
        message = "The sea takes its due. Despite everything -- the walls you built, the air you made, the light you coaxed from crystal and wire -- someone didn't make it. The ocean reminds you: you are guests here. Nothing more.",
    },
    ten_crew = {
        id      = "ten_crew",
        message = "Ten survivors. Ten souls pulled from the wreck and the water. Each one a miracle. Each one a responsibility. You look at the faces around the mess table and see something you haven't seen in weeks: hope.",
    },
    all_tech = {
        id      = "all_tech",
        message = "The final piece clicks into place. Every system online. Every mystery catalogued, every crystal mapped, every precursor glyph translated. You understand now -- what this place is, why the storm brought you here, what waits at the bottom of the trench. The only question left is: are you ready?",
    },
    surface_signal = {
        id      = "surface_signal",
        message = "The signal punches through a kilometer of water and rock, screaming upward at the speed of light. Somewhere, a satellite turns its antenna. Somewhere, a radio operator sits up straight. Somewhere, rescue is coming. But as you watch the signal strength meter climb, you glance toward the trench. The door is still down there. Waiting. You could go up. Or you could go down. The choice -- the real choice -- is finally yours.",
    },
}

-- Track which events have been triggered
local triggeredEvents = {}

-- =============================================================================
-- Module-local state
-- =============================================================================

local discovered = {}  -- { [logId] = true }

-- Log viewer state
local viewerState = {
    open           = false,
    selectedLog    = nil,    -- logId currently being read
    scrollOffset   = 0,
    categoryFilter = nil,    -- nil = all
}

-- =============================================================================
-- Public API -- Lifecycle
-- =============================================================================

--- Reset all narrative state.
function Narrative.init()
    discovered      = {}
    triggeredEvents = {}
    viewerState.open           = false
    viewerState.selectedLog    = nil
    viewerState.scrollOffset   = 0
    viewerState.categoryFilter = nil
end

-- =============================================================================
-- Public API -- Log discovery
-- =============================================================================

--- Mark a log as discovered and return its definition.
--- @param logId string
--- @return table|nil  Log definition if it exists, nil otherwise.
function Narrative.discoverLog(logId)
    local log = logById[logId]
    if not log then return nil end

    discovered[logId] = true
    return log
end

--- Get all discovered log definitions, sorted by category and order.
--- @return table  Array of log definition tables.
function Narrative.getDiscoveredLogs()
    local result = {}
    for _, logId in ipairs(logOrder) do
        if discovered[logId] then
            result[#result + 1] = logById[logId]
        end
    end
    return result
end

--- Check if a specific log has been discovered.
--- @param logId string
--- @return boolean
function Narrative.isDiscovered(logId)
    return discovered[logId] == true
end

--- Get the total number of logs.
--- @return number
function Narrative.getTotalLogCount()
    return #Narrative.LOGS
end

--- Get the number of discovered logs.
--- @return number
function Narrative.getDiscoveredCount()
    local count = 0
    for _ in pairs(discovered) do
        count = count + 1
    end
    return count
end

--- Get all log ids (for spawning logs in the world).
--- @return table  Array of log id strings.
function Narrative.getAllLogIds()
    return logOrder
end

--- Get undiscovered log ids (useful for deciding which to spawn).
--- @return table  Array of log id strings not yet discovered.
function Narrative.getUndiscoveredLogIds()
    local result = {}
    for _, logId in ipairs(logOrder) do
        if not discovered[logId] then
            result[#result + 1] = logId
        end
    end
    return result
end

--- Get a log definition by id without discovering it.
--- @param logId string
--- @return table|nil
function Narrative.getLog(logId)
    return logById[logId]
end

-- =============================================================================
-- Public API -- Story events
-- =============================================================================

--- Trigger a story event and return its message.
--- Each event can only trigger once per playthrough.
--- @param eventId string
--- @return string|nil  Narrative message, or nil if event unknown or already triggered.
function Narrative.triggerEvent(eventId)
    if not eventId then return nil end
    if triggeredEvents[eventId] then return nil end

    local event = EVENTS[eventId]
    if not event then return nil end

    triggeredEvents[eventId] = true
    return event.message
end

--- Check if an event has been triggered.
--- @param eventId string
--- @return boolean
function Narrative.isEventTriggered(eventId)
    return triggeredEvents[eventId] == true
end

--- Get all available event ids.
--- @return table  Array of event id strings.
function Narrative.getEventIds()
    local result = {}
    for eventId in pairs(EVENTS) do
        result[#result + 1] = eventId
    end
    table.sort(result)
    return result
end

-- =============================================================================
-- Public API -- Progress
-- =============================================================================

--- Get the overall story discovery progress as a 0-1 fraction.
--- Combines log discovery (70 percent weight) and event triggers (30 percent).
--- @return number  0-1 progress value.
function Narrative.getProgress()
    local totalLogs   = #Narrative.LOGS
    local foundLogs   = 0
    for _ in pairs(discovered) do
        foundLogs = foundLogs + 1
    end

    local totalEvents = 0
    local firedEvents = 0
    for _ in pairs(EVENTS) do
        totalEvents = totalEvents + 1
    end
    for _ in pairs(triggeredEvents) do
        firedEvents = firedEvents + 1
    end

    local logProgress   = totalLogs > 0 and (foundLogs / totalLogs) or 0
    local eventProgress = totalEvents > 0 and (firedEvents / totalEvents) or 0

    return logProgress * 0.7 + eventProgress * 0.3
end

-- =============================================================================
-- Public API -- Categories
-- =============================================================================

--- Get all category definitions.
--- @return table  Array of category tables { id, name, color }.
function Narrative.getCategories()
    return CATEGORIES
end

--- Get category definition by id.
--- @param categoryId string
--- @return table|nil
function Narrative.getCategory(categoryId)
    return CATEGORY_MAP[categoryId]
end

-- =============================================================================
-- Public API -- Log viewer UI
-- =============================================================================

--- Toggle the log viewer open/closed.
--- @return boolean  New open state.
function Narrative.toggleViewer()
    viewerState.open = not viewerState.open
    if not viewerState.open then
        viewerState.selectedLog = nil
    end
    return viewerState.open
end

--- Check if the log viewer is open.
--- @return boolean
function Narrative.isViewerOpen()
    return viewerState.open
end

--- Select a log for reading in the viewer.
--- @param logId string|nil  Pass nil to deselect.
function Narrative.selectLog(logId)
    viewerState.selectedLog = logId
    viewerState.scrollOffset = 0
end

--- Scroll the log text.
--- @param amount number  Positive scrolls down, negative scrolls up.
function Narrative.scrollLog(amount)
    viewerState.scrollOffset = math_max(0, viewerState.scrollOffset + amount)
end

--- Set the category filter for the log list.
--- @param categoryId string|nil  Pass nil to show all categories.
function Narrative.setCategoryFilter(categoryId)
    viewerState.categoryFilter = categoryId
end

--- Render the log viewer / codex UI.
--- @param screenW number  Screen width in pixels.
--- @param screenH number  Screen height in pixels.
function Narrative.drawLogViewer(screenW, screenH)
    if not viewerState.open then return end

    local titleFont = getFont(18)
    local bodyFont  = getFont(13)
    local smallFont = getFont(11)

    -- Dimensions
    local panelW = math_min(700, screenW - 40)
    local panelH = math_min(500, screenH - 40)
    local panelX = (screenW - panelW) / 2
    local panelY = (screenH - panelH) / 2

    local listW = 200
    local readW = panelW - listW - 10

    love.graphics.push()

    -- Darken background
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, screenW, screenH)

    -- Panel background
    love.graphics.setColor(0.08, 0.10, 0.14, 0.95)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 8, 8)

    -- Panel border
    love.graphics.setColor(0.25, 0.35, 0.50, 0.8)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 8, 8)
    love.graphics.setLineWidth(1)

    -- Title bar
    love.graphics.setFont(titleFont)
    love.graphics.setColor(0.6, 0.75, 0.9)
    love.graphics.print("CODEX", panelX + 10, panelY + 8)

    -- Progress indicator
    love.graphics.setFont(smallFont)
    local progress = Narrative.getProgress()
    local progressText = string.format("%.0f%% discovered", progress * 100)
    love.graphics.setColor(0.5, 0.6, 0.7)
    love.graphics.print(progressText, panelX + panelW - smallFont:getWidth(progressText) - 10, panelY + 12)

    -- Close hint
    love.graphics.setColor(0.4, 0.4, 0.5)
    love.graphics.print("[ESC/TAB to close]", panelX + panelW - smallFont:getWidth("[ESC/TAB to close]") - 10, panelY + panelH - 18)

    -- Category tabs
    local tabX = panelX + 10
    local tabY = panelY + 32
    love.graphics.setFont(smallFont)

    -- "All" tab
    local allColor = (viewerState.categoryFilter == nil) and {0.8, 0.85, 0.9} or {0.4, 0.45, 0.5}
    love.graphics.setColor(allColor[1], allColor[2], allColor[3])
    love.graphics.print("All", tabX, tabY)
    tabX = tabX + smallFont:getWidth("All") + 12

    for _, cat in ipairs(CATEGORIES) do
        local isActive = (viewerState.categoryFilter == cat.id)
        local c = cat.color
        if isActive then
            love.graphics.setColor(c[1], c[2], c[3])
        else
            love.graphics.setColor(c[1] * 0.5, c[2] * 0.5, c[3] * 0.5)
        end
        love.graphics.print(cat.name, tabX, tabY)
        tabX = tabX + smallFont:getWidth(cat.name) + 12
        if tabX > panelX + panelW - 20 then
            break
        end
    end

    -- Separator line
    love.graphics.setColor(0.2, 0.25, 0.35)
    love.graphics.line(panelX + 5, tabY + 16, panelX + panelW - 5, tabY + 16)

    -- Log list (left panel)
    local listX = panelX + 10
    local listY = tabY + 22
    local listH = panelH - (listY - panelY) - 25
    local entryH = 22

    -- Clip region for list
    love.graphics.setScissor(listX, listY, listW, listH)
    love.graphics.setFont(smallFont)

    local filteredLogs = {}
    for _, logId in ipairs(logOrder) do
        if discovered[logId] then
            local log = logById[logId]
            if not viewerState.categoryFilter or log.category == viewerState.categoryFilter then
                filteredLogs[#filteredLogs + 1] = log
            end
        end
    end

    for i, log in ipairs(filteredLogs) do
        local ey = listY + (i - 1) * entryH
        if ey + entryH < listY or ey > listY + listH then
            goto continue_draw
        end

        local isSelected = (viewerState.selectedLog == log.id)
        if isSelected then
            love.graphics.setColor(0.15, 0.20, 0.30, 0.8)
            love.graphics.rectangle("fill", listX, ey, listW - 5, entryH - 2, 3, 3)
        end

        local catDef = CATEGORY_MAP[log.category]
        local c = catDef and catDef.color or {0.6, 0.6, 0.6}
        love.graphics.setColor(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6)
        love.graphics.rectangle("fill", listX, ey + 2, 3, entryH - 6)

        if isSelected then
            love.graphics.setColor(1, 1, 1)
        else
            love.graphics.setColor(0.7, 0.75, 0.8)
        end

        -- Truncate title to fit list width
        local title = log.title
        local maxTitleW = listW - 20
        while smallFont:getWidth(title) > maxTitleW and #title > 4 do
            title = title:sub(1, #title - 4) .. "..."
        end
        love.graphics.print(title, listX + 8, ey + 3)

        ::continue_draw::
    end

    love.graphics.setScissor()

    -- Separator between list and reader
    love.graphics.setColor(0.2, 0.25, 0.35)
    love.graphics.line(panelX + listW + 5, listY, panelX + listW + 5, panelY + panelH - 25)

    -- Reading pane (right panel)
    local readX = panelX + listW + 15
    local readY = listY
    local readH = listH

    if viewerState.selectedLog and logById[viewerState.selectedLog] then
        local log = logById[viewerState.selectedLog]

        -- Log title
        love.graphics.setFont(titleFont)
        local catDef = CATEGORY_MAP[log.category]
        local titleColor = catDef and catDef.color or {0.7, 0.8, 0.9}
        love.graphics.setColor(titleColor[1], titleColor[2], titleColor[3])
        love.graphics.print(log.title, readX, readY)

        -- Category label
        love.graphics.setFont(smallFont)
        local catName = catDef and catDef.name or log.category
        love.graphics.setColor(0.5, 0.55, 0.6)
        love.graphics.print(catName, readX, readY + 22)

        -- Body text with word wrap
        love.graphics.setFont(bodyFont)
        love.graphics.setColor(0.8, 0.82, 0.85)
        local textTop = readY + 42
        local textH = readH - 42

        love.graphics.setScissor(readX, textTop, readW - 10, textH)

        -- Simple word-wrap rendering
        local wrapWidth = readW - 20
        local lineHeight = bodyFont:getHeight() + 2
        local curY = textTop - viewerState.scrollOffset

        -- Split text into paragraphs, then wrap each
        for paragraph in (log.text .. "\n"):gmatch("(.-)\n") do
            if #paragraph == 0 then
                curY = curY + lineHeight * 0.5
            else
                -- Word wrap
                local words = {}
                for word in paragraph:gmatch("%S+") do
                    words[#words + 1] = word
                end

                local line = ""
                for _, word in ipairs(words) do
                    local testLine = #line > 0 and (line .. " " .. word) or word
                    if bodyFont:getWidth(testLine) > wrapWidth and #line > 0 then
                        if curY + lineHeight > textTop - lineHeight and curY < textTop + textH + lineHeight then
                            love.graphics.print(line, readX, curY)
                        end
                        curY = curY + lineHeight
                        line = word
                    else
                        line = testLine
                    end
                end
                -- Print remaining text in the line
                if #line > 0 then
                    if curY + lineHeight > textTop - lineHeight and curY < textTop + textH + lineHeight then
                        love.graphics.print(line, readX, curY)
                    end
                    curY = curY + lineHeight
                end
            end
        end

        love.graphics.setScissor()

        -- Scroll indicator
        if viewerState.scrollOffset > 0 then
            love.graphics.setColor(0.5, 0.6, 0.7, 0.6)
            love.graphics.polygon("fill",
                readX + readW / 2 - 6, textTop + 4,
                readX + readW / 2 + 6, textTop + 4,
                readX + readW / 2, textTop - 2
            )
        end
    else
        -- No log selected
        love.graphics.setFont(bodyFont)
        love.graphics.setColor(0.4, 0.45, 0.5)
        local noSelText = "Select a log entry to read."
        love.graphics.print(noSelText, readX + (readW - bodyFont:getWidth(noSelText)) / 2, readY + readH / 2 - 10)
    end

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

-- =============================================================================
-- Public API -- Save / Load
-- =============================================================================

--- Serialize narrative state for saving.
--- @return table
function Narrative.getSaveData()
    local discoveredList = {}
    for logId in pairs(discovered) do
        discoveredList[#discoveredList + 1] = logId
    end

    local eventList = {}
    for eventId in pairs(triggeredEvents) do
        eventList[#eventList + 1] = eventId
    end

    return {
        discovered = discoveredList,
        events     = eventList,
    }
end

--- Restore narrative state from saved data.
--- Gracefully handles nil or partial data.
--- @param data table|nil
function Narrative.loadSaveData(data)
    if not data then return end

    Narrative.init()

    if data.discovered then
        for _, logId in ipairs(data.discovered) do
            -- Only restore logs that still exist
            if logById[logId] then
                discovered[logId] = true
            end
        end
    end

    if data.events then
        for _, eventId in ipairs(data.events) do
            if EVENTS[eventId] then
                triggeredEvents[eventId] = true
            end
        end
    end
end

return Narrative
