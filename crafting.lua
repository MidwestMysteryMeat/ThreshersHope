--[[
    Crafting / Recipe System
    Defines recipes, manages crafting logic, and runs a single-slot crafting queue
    for an underwater city builder raycaster (LOVE 2D).

    Recipes convert input resources into output items. Some recipes require
    research_lab tech to be unlocked first. Crafting is time-based (1-5 seconds)
    and the player can queue one craft at a time.

    Inventory is a plain table of { resource_id = count, ... } passed by
    reference; the system modifies it directly when starting or cancelling a craft.
]]

local Crafting = {}

-- Cached math functions for hot-path performance
local math_floor = math.floor
local math_min   = math.min
local math_max   = math.max

-- Font cache (matches project convention)
local fontCache = {}
local function getFont(size)
    if not fontCache[size] then
        fontCache[size] = love.graphics.newFont(size)
    end
    return fontCache[size]
end

-- =============================================================================
-- Recipe Definitions
-- =============================================================================

-- Category order for sorted display
local CATEGORY_ORDER = { "materials", "equipment", "consumables" }
local CATEGORY_LABELS = {
    materials    = "Materials",
    equipment    = "Equipment",
    consumables  = "Consumables",
}

-- Master recipe list keyed by id for O(1) lookup.
-- Also stored as an ordered array (Crafting.RECIPES) for iteration.
local recipeIndex = {}

local RECIPES = {
    -- ===========================
    -- Materials
    -- ===========================
    {
        id          = "composite",
        name        = "Composite Plate",
        category    = "materials",
        inputs      = { scrap_metal = 2, crystal = 1 },
        output      = { id = "composite", amount = 1 },
        craftTime   = 2.0,
        techRequired = nil,
        description = "Reinforced building material.",
    },
    {
        id          = "circuit_board",
        name        = "Circuit Board",
        category    = "materials",
        inputs      = { electronics = 1, crystal = 1 },
        output      = { id = "circuit_board", amount = 1 },
        craftTime   = 3.0,
        techRequired = nil,
        description = "Precision electronic component for advanced devices.",
    },
    {
        id          = "biofilter",
        name        = "Biofilter",
        category    = "materials",
        inputs      = { biomass = 1, electronics = 1 },
        output      = { id = "biofilter", amount = 1 },
        craftTime   = 2.0,
        techRequired = nil,
        description = "Organic membrane that purifies water and air.",
    },

    -- ===========================
    -- Synthesis (depth resources -> main ingredients)
    -- ===========================
    {
        id          = "coral_to_biomass",
        name        = "Synthesize Biomass (Coral)",
        category    = "materials",
        inputs      = { coral = 2 },
        output      = { id = "biomass", amount = 3 },
        craftTime   = 1.5,
        techRequired = nil,
        description = "Break down coral fragments into usable organic biomass.",
    },
    {
        id          = "rare_minerals_to_crystal",
        name        = "Refine Crystal (Minerals)",
        category    = "materials",
        inputs      = { rare_minerals = 2 },
        output      = { id = "crystal", amount = 2 },
        craftTime   = 2.0,
        techRequired = nil,
        description = "Refine rare mineral deposits into luminescent crystals.",
    },
    {
        id          = "rare_minerals_to_titanium",
        name        = "Smelt Titanium (Minerals)",
        category    = "materials",
        inputs      = { rare_minerals = 3 },
        output      = { id = "titanium", amount = 1 },
        craftTime   = 3.0,
        techRequired = nil,
        description = "Extract titanium from rare mineral ore.",
    },
    {
        id          = "biolum_to_electronics",
        name        = "Bioelectronics (Flora)",
        category    = "materials",
        inputs      = { bioluminescent_flora = 2 },
        output      = { id = "electronics", amount = 2 },
        craftTime   = 2.5,
        techRequired = nil,
        description = "Convert bioluminescent proteins into bioelectric components.",
    },
    {
        id          = "biolum_to_biomass",
        name        = "Process Flora (Biomass)",
        category    = "materials",
        inputs      = { bioluminescent_flora = 1 },
        output      = { id = "biomass", amount = 2 },
        craftTime   = 1.0,
        techRequired = nil,
        description = "Process deep-sea flora into biomass.",
    },
    {
        id          = "pressure_crystal_to_crystal",
        name        = "Refine Crystal (Pressure)",
        category    = "materials",
        inputs      = { pressure_crystals = 1 },
        output      = { id = "crystal", amount = 3 },
        craftTime   = 2.0,
        techRequired = nil,
        description = "Split pressure-formed crystals into usable crystal shards.",
    },
    {
        id          = "abyssal_to_titanium",
        name        = "Smelt Titanium (Abyssal)",
        category    = "materials",
        inputs      = { abyssal_ore = 1 },
        output      = { id = "titanium", amount = 2 },
        craftTime   = 3.0,
        techRequired = nil,
        description = "Abyssal ore contains dense titanium compounds.",
    },
    {
        id          = "abyssal_to_electronics",
        name        = "Extract Electronics (Abyssal)",
        category    = "materials",
        inputs      = { abyssal_ore = 2 },
        output      = { id = "electronics", amount = 3 },
        craftTime   = 3.5,
        techRequired = nil,
        description = "The abyssal ore's crystalline lattice yields electronic-grade materials.",
    },

    -- ===========================
    -- Equipment
    -- ===========================
    {
        id          = "dive_suit_mk2",
        name        = "Dive Suit Mk2",
        category    = "equipment",
        inputs      = { titanium = 3, composite = 2 },
        output      = { id = "dive_suit_mk2", amount = 1 },
        craftTime   = 5.0,
        techRequired = "research_lab",
        description = "Advanced pressure suit rated for extreme depths.",
    },
    {
        id          = "rebreather",
        name        = "Rebreather",
        category    = "equipment",
        inputs      = { biofilter = 2, circuit_board = 1 },
        output      = { id = "rebreather", amount = 1 },
        craftTime   = 4.0,
        techRequired = "research_lab",
        description = "Closed-loop breathing apparatus. Extends dive time.",
    },
    {
        id          = "flare_gun",
        name        = "Flare Gun",
        category    = "equipment",
        inputs      = { scrap_metal = 2, electronics = 1 },
        output      = { id = "flare_gun", amount = 1 },
        craftTime   = 3.0,
        techRequired = nil,
        description = "Signal flare launcher. Lights up dark waters.",
    },
    {
        id          = "repair_kit",
        name        = "Repair Kit",
        category    = "equipment",
        inputs      = { scrap_metal = 2, composite = 1 },
        output      = { id = "repair_kit", amount = 1 },
        craftTime   = 2.0,
        techRequired = nil,
        description = "Patch kit for hull breaches and equipment damage.",
    },

    -- ===========================
    -- Consumables
    -- ===========================
    {
        id          = "ration_pack",
        name        = "Ration Pack",
        category    = "consumables",
        inputs      = { biomass = 2 },
        output      = { id = "ration_pack", amount = 1 },
        craftTime   = 1.0,
        techRequired = nil,
        description = "Compressed nutrient bar. Restores hunger.",
    },
    {
        id          = "med_pack",
        name        = "Med Pack",
        category    = "consumables",
        inputs      = { biomass = 1, biofilter = 1 },
        output      = { id = "med_pack", amount = 1 },
        craftTime   = 2.0,
        techRequired = nil,
        description = "Field medical kit. Restores health.",
    },
    {
        id          = "o2_canister",
        name        = "O2 Canister",
        category    = "consumables",
        inputs      = { scrap_metal = 1, biofilter = 1 },
        output      = { id = "o2_canister", amount = 1 },
        craftTime   = 2.0,
        techRequired = nil,
        description = "Portable oxygen supply. Refills O2.",
    },
}

-- Expose the ordered recipe list
Crafting.RECIPES = RECIPES

-- Build the fast-lookup index
for i = 1, #RECIPES do
    local r = RECIPES[i]
    recipeIndex[r.id] = r
end

-- =============================================================================
-- Crafting Queue State
-- =============================================================================

local craftState = {
    active      = false,  -- true while a craft is in progress
    recipeId    = nil,    -- id of the recipe being crafted
    elapsed     = 0,      -- seconds elapsed
    duration    = 0,      -- total craft time for the current recipe
    inventory   = nil,    -- reference to the inventory table supplied at startCraft
}

-- =============================================================================
-- Internal helpers
-- =============================================================================

--- Check whether the inventory has at least the required amount of a resource.
--- @param inv table  Inventory table { resource_id = count }
--- @param resourceId string
--- @param amount number
--- @return boolean
local function hasResource(inv, resourceId, amount)
    return (inv[resourceId] or 0) >= amount
end

--- Deduct recipe inputs from the inventory. Assumes canCraft was checked first.
--- @param inv table
--- @param inputs table  { resource_id = amount, ... }
local function deductInputs(inv, inputs)
    for resId, amount in pairs(inputs) do
        inv[resId] = (inv[resId] or 0) - amount
        -- Clamp to zero to prevent floating-point drift into negatives
        if inv[resId] <= 0 then
            inv[resId] = nil
        end
    end
end

--- Return recipe inputs to the inventory (used on cancel).
--- @param inv table
--- @param inputs table
local function returnInputs(inv, inputs)
    for resId, amount in pairs(inputs) do
        inv[resId] = (inv[resId] or 0) + amount
    end
end

-- =============================================================================
-- Public API
-- =============================================================================

--- Initialise (or reset) the crafting system.
function Crafting.init()
    craftState.active    = false
    craftState.recipeId  = nil
    craftState.elapsed   = 0
    craftState.duration  = 0
    craftState.inventory = nil
end

--- Retrieve a recipe definition by its id.
--- @param recipeId string
--- @return table|nil  Recipe definition or nil if not found
function Crafting.getRecipe(recipeId)
    if not recipeId then return nil end
    return recipeIndex[recipeId]
end

--- Determine whether a recipe can be crafted right now.
--- @param recipeId string
--- @param inventory table  { resource_id = count }
--- @param unlockedTechs table|nil  Set of unlocked tech ids { tech_id = true }
--- @return boolean  canCraft
--- @return string|nil  reason (only when canCraft is false)
function Crafting.canCraft(recipeId, inventory, unlockedTechs)
    if not recipeId or not inventory then
        return false, "Invalid arguments"
    end

    local recipe = recipeIndex[recipeId]
    if not recipe then
        return false, "Unknown recipe"
    end

    -- Check tech requirement
    if recipe.techRequired then
        local techs = unlockedTechs or {}
        if not techs[recipe.techRequired] then
            return false, "Requires: " .. recipe.techRequired
        end
    end

    -- Check that we are not already crafting
    if craftState.active then
        return false, "Already crafting"
    end

    -- Check each input resource
    for resId, amount in pairs(recipe.inputs) do
        if not hasResource(inventory, resId, amount) then
            local have = inventory[resId] or 0
            return false, "Need " .. amount .. " " .. resId .. " (have " .. have .. ")"
        end
    end

    return true, nil
end

--- Start crafting a recipe. Deducts inputs from inventory immediately.
--- @param recipeId string
--- @param inventory table  Mutable inventory table (modified by reference)
--- @return boolean  true if craft started, false on failure
function Crafting.startCraft(recipeId, inventory)
    if not recipeId or not inventory then
        return false
    end

    -- Re-validate before committing (tech check omitted here -- caller
    -- should have already used canCraft which includes tech validation;
    -- we still guard against missing resources to be safe)
    local recipe = recipeIndex[recipeId]
    if not recipe then
        return false
    end

    if craftState.active then
        return false
    end

    -- Verify resources one more time defensively
    for resId, amount in pairs(recipe.inputs) do
        if not hasResource(inventory, resId, amount) then
            return false
        end
    end

    -- Commit: deduct inputs and start the timer
    deductInputs(inventory, recipe.inputs)

    craftState.active    = true
    craftState.recipeId  = recipeId
    craftState.elapsed   = 0
    craftState.duration  = recipe.craftTime
    craftState.inventory = inventory

    return true
end

--- Tick the crafting timer. Returns the completed item id when a craft
--- finishes, or nil while in progress / idle.
--- @param dt number  Delta time in seconds
--- @return string|nil  output item id on completion
function Crafting.update(dt)
    if not craftState.active then
        return nil
    end

    craftState.elapsed = craftState.elapsed + dt

    if craftState.elapsed >= craftState.duration then
        -- Craft complete
        local recipe = recipeIndex[craftState.recipeId]
        if recipe and craftState.inventory then
            -- Grant output to inventory
            local outId = recipe.output.id
            local outAmt = recipe.output.amount
            craftState.inventory[outId] = (craftState.inventory[outId] or 0) + outAmt
        end

        local completedId = recipe and recipe.output.id or nil

        -- Reset craft state
        craftState.active    = false
        craftState.recipeId  = nil
        craftState.elapsed   = 0
        craftState.duration  = 0
        craftState.inventory = nil

        return completedId
    end

    return nil
end

--- Cancel the current craft and return consumed resources to the inventory.
function Crafting.cancelCraft()
    if not craftState.active then
        return
    end

    local recipe = recipeIndex[craftState.recipeId]
    if recipe and craftState.inventory then
        returnInputs(craftState.inventory, recipe.inputs)
    end

    craftState.active    = false
    craftState.recipeId  = nil
    craftState.elapsed   = 0
    craftState.duration  = 0
    craftState.inventory = nil
end

--- Is the system currently crafting?
--- @return boolean
function Crafting.isCrafting()
    return craftState.active
end

--- Get the current craft progress as a normalised value.
--- @return number  0.0 (just started) to 1.0 (complete), 0.0 when idle
function Crafting.getCraftProgress()
    if not craftState.active or craftState.duration <= 0 then
        return 0
    end
    return math_min(1.0, craftState.elapsed / craftState.duration)
end

--- Get the recipe definition for the item currently being crafted.
--- @return table|nil  Recipe definition or nil when idle
function Crafting.getCraftingRecipe()
    if not craftState.active then
        return nil
    end
    return recipeIndex[craftState.recipeId]
end

--- Build a list of all recipes the player can currently craft given their
--- inventory and unlocked techs. Returns an array of recipe definitions
--- (references, not copies).
--- @param inventory table  { resource_id = count }
--- @param unlockedTechs table|nil  { tech_id = true }
--- @return table  Array of recipe definitions that pass canCraft
function Crafting.getAvailableRecipes(inventory, unlockedTechs)
    local available = {}
    if not inventory then
        return available
    end

    for i = 1, #RECIPES do
        local recipe = RECIPES[i]
        local ok, _ = Crafting.canCraft(recipe.id, inventory, unlockedTechs)
        if ok then
            available[#available + 1] = recipe
        end
    end
    return available
end

-- =============================================================================
-- HUD Rendering
-- =============================================================================

-- Color palette for the crafting HUD
local HUD_BG          = { 0.05, 0.08, 0.12, 0.85 }
local HUD_BORDER      = { 0.20, 0.50, 0.65, 0.90 }
local HUD_BAR_BG      = { 0.10, 0.15, 0.20, 1.00 }
local HUD_BAR_FILL    = { 0.25, 0.70, 0.85, 1.00 }
local HUD_BAR_DONE    = { 0.30, 0.90, 0.40, 1.00 }
local HUD_TEXT_NAME    = { 0.85, 0.92, 1.00, 1.00 }
local HUD_TEXT_PERCENT = { 0.65, 0.75, 0.80, 1.00 }

--- Draw a small crafting-in-progress bar on the HUD.
--- Only renders when a craft is active.
--- @param screenW number  Window width
--- @param screenH number  Window height
function Crafting.drawHUD(screenW, screenH)
    if not craftState.active then
        return
    end

    local recipe = recipeIndex[craftState.recipeId]
    if not recipe then
        return
    end

    local barW = 200
    local barH = 16
    local padX = 10
    local padY = 8
    local panelW = barW + padX * 2
    local panelH = barH + padY * 2 + 20  -- extra 20 for label text

    -- Position: top-center of screen
    local panelX = math_floor((screenW - panelW) / 2)
    local panelY = 10

    -- Background panel
    love.graphics.setColor(HUD_BG[1], HUD_BG[2], HUD_BG[3], HUD_BG[4])
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 6, 6)

    -- Border
    love.graphics.setColor(HUD_BORDER[1], HUD_BORDER[2], HUD_BORDER[3], HUD_BORDER[4])
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 6, 6)

    -- Label: recipe name
    local labelFont = getFont(12)
    love.graphics.setFont(labelFont)
    love.graphics.setColor(HUD_TEXT_NAME[1], HUD_TEXT_NAME[2], HUD_TEXT_NAME[3], HUD_TEXT_NAME[4])
    love.graphics.print("Crafting: " .. recipe.name, panelX + padX, panelY + padY)

    -- Progress bar background
    local barX = panelX + padX
    local barY = panelY + padY + 18
    love.graphics.setColor(HUD_BAR_BG[1], HUD_BAR_BG[2], HUD_BAR_BG[3], HUD_BAR_BG[4])
    love.graphics.rectangle("fill", barX, barY, barW, barH, 3, 3)

    -- Progress bar fill
    local progress = Crafting.getCraftProgress()
    local fillColor = (progress >= 0.99) and HUD_BAR_DONE or HUD_BAR_FILL
    love.graphics.setColor(fillColor[1], fillColor[2], fillColor[3], fillColor[4])
    if progress > 0 then
        local fillW = math_max(1, math_floor(barW * progress))
        love.graphics.rectangle("fill", barX, barY, fillW, barH, 3, 3)
    end

    -- Percentage text centered on bar
    local pctText = math_floor(progress * 100) .. "%"
    local pctFont = getFont(11)
    love.graphics.setFont(pctFont)
    local textW = pctFont:getWidth(pctText)
    love.graphics.setColor(HUD_TEXT_PERCENT[1], HUD_TEXT_PERCENT[2], HUD_TEXT_PERCENT[3], HUD_TEXT_PERCENT[4])
    love.graphics.print(pctText, barX + math_floor((barW - textW) / 2), barY + 1)

    -- Restore default color
    love.graphics.setColor(1, 1, 1, 1)
end

-- =============================================================================
-- Save / Load
-- =============================================================================

--- Serialize crafting state for persistence.
--- Note: the inventory reference is NOT serialized -- the caller must re-supply
--- the inventory on load if a craft was in progress. In practice, saving mid-craft
--- is handled by storing the deducted inputs separately so they can be returned
--- on load if the player never resumes.
--- @return table
function Crafting.getSaveData()
    if not craftState.active then
        return { active = false }
    end

    local recipe = recipeIndex[craftState.recipeId]
    return {
        active   = true,
        recipeId = craftState.recipeId,
        elapsed  = craftState.elapsed,
        duration = craftState.duration,
        -- Store the deducted inputs so they can be returned if load cannot resume
        inputs   = recipe and recipe.inputs or nil,
    }
end

--- Restore crafting state from save data.
--- @param data table|nil  Previously saved data from getSaveData()
--- @param inventory table|nil  Current inventory reference to re-attach
function Crafting.loadSaveData(data, inventory)
    -- Always reset first
    Crafting.init()

    if not data then return end
    if not data.active then return end

    local recipe = recipeIndex[data.recipeId]
    if not recipe then
        -- Recipe no longer exists (game version mismatch); return stored inputs
        if data.inputs and inventory then
            returnInputs(inventory, data.inputs)
        end
        return
    end

    -- Resume the craft in progress
    craftState.active    = true
    craftState.recipeId  = data.recipeId
    craftState.elapsed   = data.elapsed or 0
    craftState.duration  = data.duration or recipe.craftTime
    craftState.inventory = inventory
end

return Crafting
