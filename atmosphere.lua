--[[
    Atmosphere System
    Creates oppressive, unsettling environments with dynamic lighting,
    breathing fog, flickering lights, and reduced visibility.
    Conditions ease when the player establishes a base.
]]

local Atmosphere = {}

-- Current atmosphere state (interpolated live values)
local state = {
    -- Core atmosphere values (these fluctuate)
    fogDensity = 0.12,
    fogColor = {0.05, 0.05, 0.08},
    ambient = 0.3,
    maxViewDist = 32,          -- Max ray steps

    -- Dynamic effects
    flickerIntensity = 0,      -- How much light flickers (0-1)
    flickerValue = 0,          -- Current flicker offset
    flickerTimer = 0,
    nextFlickerTime = 0,

    breathCycle = 0,           -- Fog breathing oscillation phase
    breathSpeed = 0.4,         -- How fast fog breathes
    breathDepth = 0,           -- How much fog oscillates (0-1)

    vignetteStrength = 0,      -- Screen edge darkness (0-1)
    vignetteRadius = 0.7,      -- Inner radius of clear area

    desaturation = 0,          -- Color desaturation amount (0-1)
    colorShift = {0, 0, 0},    -- RGB shift toward cold/sickly tones

    -- Disturbance pulses (sudden subtle darkening)
    disturbTimer = 0,
    disturbInterval = 8,       -- Seconds between disturbances
    disturbActive = false,
    disturbValue = 0,          -- Current disturbance darkness (0-1)

    -- Base status
    baseEstablished = false,
    baseTransition = 0,        -- 0 = full hostile, 1 = full safe (smooth transition)
}

-- Atmosphere presets per environment (hostile = no base, safe = base established)
-- These define the TARGET values that the system interpolates toward
local presets = {
    --===========================================
    -- DUNGEON: Damp, claustrophobic, torchlit
    --===========================================
    dungeon = {
        hostile = {
            fogDensity = 0.22,
            fogColor = {0.03, 0.02, 0.05},
            ambient = 0.15,
            maxViewDist = 14,
            flickerIntensity = 0.35,     -- Torches guttering
            breathSpeed = 0.3,
            breathDepth = 0.25,
            vignetteStrength = 0.65,
            vignetteRadius = 0.55,
            desaturation = 0.3,
            colorShift = {-0.02, -0.03, 0.01},  -- Cold blue undertone
            disturbInterval = 6,
        },
        safe = {
            fogDensity = 0.08,
            fogColor = {0.06, 0.05, 0.07},
            ambient = 0.45,
            maxViewDist = 28,
            flickerIntensity = 0.08,
            breathSpeed = 0.15,
            breathDepth = 0.05,
            vignetteStrength = 0.15,
            vignetteRadius = 0.8,
            desaturation = 0.0,
            colorShift = {0.02, 0.01, -0.01},  -- Warm torchlight
            disturbInterval = 30,
        },
    },

    --===========================================
    -- TOWN: Overcast but visible, unsettled without order
    --===========================================
    town = {
        hostile = {
            fogDensity = 0.10,
            fogColor = {0.35, 0.33, 0.38},
            ambient = 0.50,
            maxViewDist = 22,
            flickerIntensity = 0.10,
            breathSpeed = 0.2,
            breathDepth = 0.15,
            vignetteStrength = 0.30,
            vignetteRadius = 0.65,
            desaturation = 0.25,
            colorShift = {-0.03, -0.02, 0.0},   -- Desaturated, grey
            disturbInterval = 12,
        },
        safe = {
            fogDensity = 0.03,
            fogColor = {0.7, 0.75, 0.85},
            ambient = 0.90,
            maxViewDist = 32,
            flickerIntensity = 0.0,
            breathSpeed = 0.1,
            breathDepth = 0.0,
            vignetteStrength = 0.0,
            vignetteRadius = 0.9,
            desaturation = 0.0,
            colorShift = {0.0, 0.0, 0.0},
            disturbInterval = 999,
        },
    },

    --===========================================
    -- DESERT: Scorching haze, sand in lungs
    --===========================================
    desert = {
        hostile = {
            fogDensity = 0.16,
            fogColor = {0.55, 0.45, 0.30},
            ambient = 0.55,
            maxViewDist = 16,
            flickerIntensity = 0.20,      -- Heat shimmer
            breathSpeed = 0.5,
            breathDepth = 0.30,           -- Sandstorm pulses
            vignetteStrength = 0.50,
            vignetteRadius = 0.50,
            desaturation = 0.15,
            colorShift = {0.05, 0.02, -0.05},   -- Oppressive heat yellow
            disturbInterval = 5,           -- Frequent sand gusts
        },
        safe = {
            fogDensity = 0.05,
            fogColor = {0.95, 0.9, 0.75},
            ambient = 1.0,
            maxViewDist = 32,
            flickerIntensity = 0.0,
            breathSpeed = 0.1,
            breathDepth = 0.0,
            vignetteStrength = 0.05,
            vignetteRadius = 0.85,
            desaturation = 0.0,
            colorShift = {0.0, 0.0, 0.0},
            disturbInterval = 999,
        },
    },

    --===========================================
    -- FOREST: Canopy chokes light, things move in the dark
    --===========================================
    forest = {
        hostile = {
            fogDensity = 0.20,
            fogColor = {0.12, 0.18, 0.10},
            ambient = 0.22,
            maxViewDist = 12,
            flickerIntensity = 0.25,      -- Dappled shifting light
            breathSpeed = 0.35,
            breathDepth = 0.20,
            vignetteStrength = 0.70,
            vignetteRadius = 0.45,
            desaturation = 0.20,
            colorShift = {-0.04, 0.02, -0.04},  -- Sickly green
            disturbInterval = 4,
        },
        safe = {
            fogDensity = 0.06,
            fogColor = {0.3, 0.4, 0.3},
            ambient = 0.65,
            maxViewDist = 30,
            flickerIntensity = 0.05,
            breathSpeed = 0.2,
            breathDepth = 0.03,
            vignetteStrength = 0.10,
            vignetteRadius = 0.8,
            desaturation = 0.0,
            colorShift = {0.0, 0.01, 0.0},
            disturbInterval = 999,
        },
    },

    --===========================================
    -- VOID: The worst. Barely visible. Reality frays.
    --===========================================
    void = {
        hostile = {
            fogDensity = 0.30,
            fogColor = {0.06, 0.02, 0.10},
            ambient = 0.10,
            maxViewDist = 10,
            flickerIntensity = 0.50,      -- Reality distortion
            breathSpeed = 0.6,
            breathDepth = 0.40,           -- Heavy pulsing
            vignetteStrength = 0.85,
            vignetteRadius = 0.35,
            desaturation = 0.45,
            colorShift = {0.03, -0.05, 0.06},   -- Purple-sick
            disturbInterval = 3,           -- Frequent horror pulses
        },
        safe = {
            fogDensity = 0.12,
            fogColor = {0.08, 0.05, 0.12},
            ambient = 0.30,
            maxViewDist = 22,
            flickerIntensity = 0.12,
            breathSpeed = 0.25,
            breathDepth = 0.08,
            vignetteStrength = 0.30,
            vignetteRadius = 0.65,
            desaturation = 0.10,
            colorShift = {0.01, -0.01, 0.02},
            disturbInterval = 15,
        },
    },

    --===========================================
    -- UNDERWATER: Ocean floor exploration
    --===========================================
    underwater = {
        hostile = {
            fogDensity = 0.12,
            fogColor = {0.03, 0.08, 0.14},
            ambient = 0.35,
            maxViewDist = 18,
            flickerIntensity = 0.12,      -- Bioluminescent flicker
            breathSpeed = 0.3,
            breathDepth = 0.15,           -- Water current pulses
            vignetteStrength = 0.50,
            vignetteRadius = 0.50,
            desaturation = 0.20,
            colorShift = {-0.03, -0.01, 0.04},  -- Blue-shift underwater
            disturbInterval = 8,
        },
        safe = {
            fogDensity = 0.04,
            fogColor = {0.06, 0.12, 0.20},
            ambient = 0.65,
            maxViewDist = 28,
            flickerIntensity = 0.04,
            breathSpeed = 0.12,
            breathDepth = 0.04,
            vignetteStrength = 0.15,
            vignetteRadius = 0.80,
            desaturation = 0.03,
            colorShift = {-0.01, 0.0, 0.02},
            disturbInterval = 25,
        },
    },

    --===========================================
    -- WRECK: Sinking/sunken ship interior
    --===========================================
    wreck = {
        hostile = {
            fogDensity = 0.03,
            fogColor = {0.12, 0.15, 0.22},    -- Brighter blue-grey fog (visible!)
            ambient = 0.75,
            maxViewDist = 36,
            flickerIntensity = 0.08,
            breathSpeed = 0.2,
            breathDepth = 0.05,
            vignetteStrength = 0.10,
            vignetteRadius = 0.80,
            desaturation = 0.08,
            colorShift = {-0.005, -0.005, 0.01},
            disturbInterval = 12,
        },
        safe = {
            fogDensity = 0.05,
            fogColor = {0.12, 0.14, 0.20},
            ambient = 0.70,
            maxViewDist = 28,
            flickerIntensity = 0.08,
            breathSpeed = 0.15,
            breathDepth = 0.05,
            vignetteStrength = 0.15,
            vignetteRadius = 0.75,
            desaturation = 0.05,
            colorShift = {0.0, -0.01, 0.02},
            disturbInterval = 20,
        },
    },

    --===========================================
    -- HABITAT: Player-built underwater base
    --===========================================
    habitat = {
        hostile = {
            fogDensity = 0.05,
            fogColor = {0.15, 0.2, 0.25},
            ambient = 0.55,
            maxViewDist = 26,
            flickerIntensity = 0.08,
            breathSpeed = 0.15,
            breathDepth = 0.08,
            vignetteStrength = 0.25,
            vignetteRadius = 0.7,
            desaturation = 0.10,
            colorShift = {0.0, 0.0, 0.01},
            disturbInterval = 15,
        },
        safe = {
            fogDensity = 0.02,
            fogColor = {0.3, 0.35, 0.4},
            ambient = 0.85,
            maxViewDist = 32,
            flickerIntensity = 0.0,
            breathSpeed = 0.1,
            breathDepth = 0.0,
            vignetteStrength = 0.05,
            vignetteRadius = 0.9,
            desaturation = 0.0,
            colorShift = {0.01, 0.01, 0.0},
            disturbInterval = 999,
        },
    },

    --===========================================
    -- DEEP_OCEAN: Abyssal depths
    --===========================================
    deep_ocean = {
        hostile = {
            fogDensity = 0.35,
            fogColor = {0.01, 0.02, 0.06},
            ambient = 0.08,
            maxViewDist = 8,
            flickerIntensity = 0.30,      -- Abyssal bioluminescence
            breathSpeed = 0.5,
            breathDepth = 0.35,
            vignetteStrength = 0.90,
            vignetteRadius = 0.30,
            desaturation = 0.40,
            colorShift = {-0.03, -0.04, 0.06},
            disturbInterval = 3,
        },
        safe = {
            fogDensity = 0.15,
            fogColor = {0.03, 0.05, 0.1},
            ambient = 0.25,
            maxViewDist = 18,
            flickerIntensity = 0.08,
            breathSpeed = 0.2,
            breathDepth = 0.10,
            vignetteStrength = 0.40,
            vignetteRadius = 0.60,
            desaturation = 0.15,
            colorShift = {-0.01, -0.01, 0.03},
            disturbInterval = 10,
        },
    },

    --===========================================
    -- CASTLE: Cold stone, drafts snuff candles
    --===========================================
    castle = {
        hostile = {
            fogDensity = 0.14,
            fogColor = {0.20, 0.22, 0.28},
            ambient = 0.30,
            maxViewDist = 18,
            flickerIntensity = 0.30,      -- Candles in draft
            breathSpeed = 0.25,
            breathDepth = 0.18,
            vignetteStrength = 0.55,
            vignetteRadius = 0.55,
            desaturation = 0.25,
            colorShift = {-0.02, -0.02, 0.02},  -- Cold stone blue
            disturbInterval = 8,
        },
        safe = {
            fogDensity = 0.04,
            fogColor = {0.5, 0.55, 0.6},
            ambient = 0.75,
            maxViewDist = 32,
            flickerIntensity = 0.03,
            breathSpeed = 0.1,
            breathDepth = 0.02,
            vignetteStrength = 0.08,
            vignetteRadius = 0.85,
            desaturation = 0.0,
            colorShift = {0.01, 0.0, 0.0},
            disturbInterval = 999,
        },
    },

    --===========================================
    -- SURFACE: Bright open water, calm
    --===========================================
    surface = {
        hostile = {
            fogDensity = 0.04,
            fogColor = {0.15, 0.30, 0.40},
            ambient = 0.65,
            maxViewDist = 30,
            flickerIntensity = 0.04,
            breathSpeed = 0.2,
            breathDepth = 0.04,
            vignetteStrength = 0.2,
            vignetteRadius = 0.7,
            desaturation = 0.05,
            colorShift = {-0.02, 0.02, 0.06},
            disturbInterval = 20,
        },
        safe = {
            fogDensity = 0.02,
            fogColor = {0.25, 0.45, 0.55},
            ambient = 0.85,
            maxViewDist = 40,
            flickerIntensity = 0.01,
            breathSpeed = 0.1,
            breathDepth = 0.02,
            vignetteStrength = 0.05,
            vignetteRadius = 0.9,
            desaturation = 0.0,
            colorShift = {0.0, 0.02, 0.04},
            disturbInterval = 999,
        },
    },

    --===========================================
    -- DEEP: Dark crushing depths
    --===========================================
    deep = {
        hostile = {
            fogDensity = 0.22,
            fogColor = {0.04, 0.06, 0.12},
            ambient = 0.15,
            maxViewDist = 10,
            flickerIntensity = 0.08,
            breathSpeed = 0.4,
            breathDepth = 0.15,
            vignetteStrength = 0.7,
            vignetteRadius = 0.4,
            desaturation = 0.35,
            colorShift = {-0.04, -0.02, 0.04},
            disturbInterval = 6,
        },
        safe = {
            fogDensity = 0.08,
            fogColor = {0.10, 0.15, 0.25},
            ambient = 0.45,
            maxViewDist = 20,
            flickerIntensity = 0.03,
            breathSpeed = 0.15,
            breathDepth = 0.05,
            vignetteStrength = 0.2,
            vignetteRadius = 0.7,
            desaturation = 0.1,
            colorShift = {-0.01, 0.0, 0.02},
            disturbInterval = 15,
        },
    },

    --===========================================
    -- ABYSS: Near-total darkness, oppressive
    --===========================================
    abyss = {
        hostile = {
            fogDensity = 0.30,
            fogColor = {0.02, 0.03, 0.06},
            ambient = 0.08,
            maxViewDist = 7,
            flickerIntensity = 0.12,
            breathSpeed = 0.5,
            breathDepth = 0.20,
            vignetteStrength = 0.85,
            vignetteRadius = 0.3,
            desaturation = 0.45,
            colorShift = {-0.05, -0.03, 0.03},
            disturbInterval = 4,
        },
        safe = {
            fogDensity = 0.12,
            fogColor = {0.06, 0.08, 0.15},
            ambient = 0.30,
            maxViewDist = 14,
            flickerIntensity = 0.04,
            breathSpeed = 0.2,
            breathDepth = 0.08,
            vignetteStrength = 0.35,
            vignetteRadius = 0.6,
            desaturation = 0.15,
            colorShift = {-0.02, -0.01, 0.02},
            disturbInterval = 12,
        },
    },

    --===========================================
    -- TRENCH: Extreme depths, alien environment
    --===========================================
    trench = {
        hostile = {
            fogDensity = 0.35,
            fogColor = {0.01, 0.02, 0.04},
            ambient = 0.05,
            maxViewDist = 5,
            flickerIntensity = 0.15,
            breathSpeed = 0.6,
            breathDepth = 0.25,
            vignetteStrength = 0.9,
            vignetteRadius = 0.25,
            desaturation = 0.50,
            colorShift = {-0.06, -0.04, 0.02},
            disturbInterval = 3,
        },
        safe = {
            fogDensity = 0.15,
            fogColor = {0.04, 0.05, 0.10},
            ambient = 0.20,
            maxViewDist = 10,
            flickerIntensity = 0.05,
            breathSpeed = 0.25,
            breathDepth = 0.10,
            vignetteStrength = 0.5,
            vignetteRadius = 0.5,
            desaturation = 0.25,
            colorShift = {-0.03, -0.02, 0.02},
            disturbInterval = 8,
        },
    },
}

-- Current environment name
local currentEnv = "dungeon"

-- Vignette canvas (regenerated on resize)
local vignetteCanvas = nil
local vignetteW, vignetteH = 0, 0

-- Lerp helper
local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Lerp for color tables
local function lerpColor(a, b, t)
    return {
        lerp(a[1], b[1], t),
        lerp(a[2], b[2], t),
        lerp(a[3], b[3], t),
    }
end

function Atmosphere.init(envName)
    currentEnv = envName or "dungeon"
    state.baseEstablished = false
    state.baseTransition = 0
    state.breathCycle = 0
    state.flickerTimer = 0
    state.nextFlickerTime = 0.1 + math.random() * 0.3
    state.disturbTimer = 0
    state.disturbActive = false
    state.disturbValue = 0

    -- Snap to hostile preset immediately
    Atmosphere.snapToPreset()
end

-- Immediately set state to current preset (no interpolation)
function Atmosphere.snapToPreset()
    local preset = presets[currentEnv]
    if not preset then
        preset = presets.dungeon
    end

    local target = state.baseEstablished and preset.safe or preset.hostile

    state.fogDensity = target.fogDensity
    state.fogColor = {target.fogColor[1], target.fogColor[2], target.fogColor[3]}
    state.ambient = target.ambient
    state.maxViewDist = target.maxViewDist
    state.flickerIntensity = target.flickerIntensity
    state.breathSpeed = target.breathSpeed
    state.breathDepth = target.breathDepth
    state.vignetteStrength = target.vignetteStrength
    state.vignetteRadius = target.vignetteRadius
    state.desaturation = target.desaturation
    state.colorShift = {target.colorShift[1], target.colorShift[2], target.colorShift[3]}
    state.disturbInterval = target.disturbInterval
end

function Atmosphere.setEnvironment(envName)
    currentEnv = envName
    -- Don't snap - let it transition smoothly
end

function Atmosphere.setBaseEstablished(established)
    state.baseEstablished = established
end

function Atmosphere.isBaseEstablished()
    return state.baseEstablished
end

function Atmosphere.toggleBase()
    state.baseEstablished = not state.baseEstablished
    return state.baseEstablished
end

function Atmosphere.update(dt)
    local preset = presets[currentEnv]
    if not preset then
        preset = presets.dungeon
    end

    -- Smooth transition between hostile and safe
    local targetTransition = state.baseEstablished and 1.0 or 0.0
    local transitionSpeed = 0.15  -- Slow, creeping transition
    if state.baseTransition < targetTransition then
        state.baseTransition = math.min(targetTransition, state.baseTransition + dt * transitionSpeed)
    elseif state.baseTransition > targetTransition then
        -- Darkness encroaches faster than light pushes it back
        state.baseTransition = math.max(targetTransition, state.baseTransition - dt * transitionSpeed * 1.5)
    end

    local t = state.baseTransition
    local hostile = preset.hostile
    local safe = preset.safe

    -- Interpolate all target values
    local targetFog = lerp(hostile.fogDensity, safe.fogDensity, t)
    local targetFogColor = lerpColor(hostile.fogColor, safe.fogColor, t)
    local targetAmbient = lerp(hostile.ambient, safe.ambient, t)
    local targetMaxView = lerp(hostile.maxViewDist, safe.maxViewDist, t)
    local targetFlicker = lerp(hostile.flickerIntensity, safe.flickerIntensity, t)
    local targetBreathSpeed = lerp(hostile.breathSpeed, safe.breathSpeed, t)
    local targetBreathDepth = lerp(hostile.breathDepth, safe.breathDepth, t)
    local targetVignette = lerp(hostile.vignetteStrength, safe.vignetteStrength, t)
    local targetVigRadius = lerp(hostile.vignetteRadius, safe.vignetteRadius, t)
    local targetDesat = lerp(hostile.desaturation, safe.desaturation, t)
    local targetColorShift = lerpColor(hostile.colorShift, safe.colorShift, t)
    local targetDisturbInt = lerp(hostile.disturbInterval, safe.disturbInterval, t)

    -- Smoothly approach targets (different speeds for different properties)
    local fogLerp = math.min(1, dt * 2.0)
    local ambientLerp = math.min(1, dt * 1.5)
    local viewLerp = math.min(1, dt * 1.0)

    state.fogDensity = lerp(state.fogDensity, targetFog, fogLerp)
    state.fogColor = lerpColor(state.fogColor, targetFogColor, fogLerp)
    state.ambient = lerp(state.ambient, targetAmbient, ambientLerp)
    state.maxViewDist = lerp(state.maxViewDist, targetMaxView, viewLerp)
    state.flickerIntensity = lerp(state.flickerIntensity, targetFlicker, fogLerp)
    state.breathSpeed = lerp(state.breathSpeed, targetBreathSpeed, fogLerp)
    state.breathDepth = lerp(state.breathDepth, targetBreathDepth, fogLerp)
    state.vignetteStrength = lerp(state.vignetteStrength, targetVignette, ambientLerp)
    state.vignetteRadius = lerp(state.vignetteRadius, targetVigRadius, ambientLerp)
    state.desaturation = lerp(state.desaturation, targetDesat, ambientLerp)
    state.colorShift = lerpColor(state.colorShift, targetColorShift, fogLerp)
    state.disturbInterval = lerp(state.disturbInterval, targetDisturbInt, fogLerp)

    -- === FLICKER SYSTEM ===
    -- Irregular light flickering (like failing fluorescents or guttering torches)
    state.flickerTimer = state.flickerTimer + dt
    if state.flickerTimer >= state.nextFlickerTime then
        state.flickerTimer = 0
        -- Randomize next flicker timing (irregular, unsettling)
        if math.random() < 0.3 then
            -- Rapid succession of flickers
            state.nextFlickerTime = 0.03 + math.random() * 0.08
        else
            state.nextFlickerTime = 0.1 + math.random() * 0.5
        end
        -- Flicker magnitude
        local intensity = state.flickerIntensity
        if math.random() < 0.15 then
            -- Occasional deep flicker (lights almost die)
            state.flickerValue = -intensity * (0.6 + math.random() * 0.4)
        else
            state.flickerValue = (math.random() - 0.6) * intensity * 0.5
        end
    else
        -- Decay flicker value back to 0
        state.flickerValue = state.flickerValue * (1 - dt * 8)
    end

    -- === BREATHING FOG ===
    -- Slow oscillation that makes the fog feel alive
    state.breathCycle = state.breathCycle + dt * state.breathSpeed
    if state.breathCycle > math.pi * 2 then
        state.breathCycle = state.breathCycle - math.pi * 2
    end

    -- === DISTURBANCE PULSES ===
    -- Occasional sudden darkening - like something passing between you and a light source
    state.disturbTimer = state.disturbTimer + dt
    if not state.disturbActive then
        if state.disturbTimer >= state.disturbInterval then
            state.disturbActive = true
            state.disturbTimer = 0
            state.disturbValue = 0
            -- Randomize next interval
            state.disturbInterval = targetDisturbInt * (0.5 + math.random())
        end
    else
        -- Disturbance pulse: quick darken, slow recovery
        local disturbDuration = 1.5
        local peakTime = 0.2  -- Fast onset
        local elapsed = state.disturbTimer

        if elapsed < peakTime then
            -- Quick darken
            state.disturbValue = (elapsed / peakTime) * 0.4
        elseif elapsed < disturbDuration then
            -- Slow recovery
            local recovery = (elapsed - peakTime) / (disturbDuration - peakTime)
            state.disturbValue = 0.4 * (1 - recovery * recovery)  -- Ease out
        else
            state.disturbActive = false
            state.disturbValue = 0
            state.disturbTimer = 0
        end
    end
end

-- Get the effective fog density for this frame (with breathing)
function Atmosphere.getFogDensity()
    local breathOffset = math.sin(state.breathCycle) * state.breathDepth * state.fogDensity
    return state.fogDensity + breathOffset
end

-- Get effective fog color
function Atmosphere.getFogColor()
    return state.fogColor
end

-- Get effective ambient light (with flicker and disturbance)
function Atmosphere.getAmbient()
    local amb = state.ambient + state.flickerValue - state.disturbValue
    return math.max(0.02, amb)  -- Never fully black (player can always see a sliver)
end

-- Get max view distance in ray steps
function Atmosphere.getMaxViewDist()
    -- During disturbance, briefly reduce view distance too
    local viewDist = state.maxViewDist
    if state.disturbActive then
        viewDist = viewDist * (1 - state.disturbValue * 0.3)
    end
    return math.max(6, math.floor(viewDist))
end

-- Get vignette parameters
function Atmosphere.getVignette()
    local strength = state.vignetteStrength
    -- Disturbance intensifies vignette
    if state.disturbActive then
        strength = math.min(1.0, strength + state.disturbValue * 0.5)
    end
    return strength, state.vignetteRadius
end

-- Get desaturation amount (0 = full color, 1 = grayscale)
function Atmosphere.getDesaturation()
    local desat = state.desaturation
    if state.disturbActive then
        desat = math.min(1.0, desat + state.disturbValue * 0.3)
    end
    return desat
end

-- Get color shift
function Atmosphere.getColorShift()
    return state.colorShift
end

-- Apply atmosphere color grading to an RGB color
function Atmosphere.applyColorGrading(r, g, b)
    local shift = state.colorShift
    r = r + shift[1]
    g = g + shift[2]
    b = b + shift[3]

    -- Apply desaturation
    local desat = Atmosphere.getDesaturation()
    if desat > 0 then
        local luminance = r * 0.299 + g * 0.587 + b * 0.114
        r = lerp(r, luminance, desat)
        g = lerp(g, luminance, desat)
        b = lerp(b, luminance, desat)
    end

    return math.max(0, math.min(1, r)), math.max(0, math.min(1, g)), math.max(0, math.min(1, b))
end

-- Generate vignette overlay canvas
function Atmosphere.generateVignette(w, h)
    if vignetteCanvas and vignetteW == w and vignetteH == h then
        return -- Already generated at this size
    end

    vignetteW, vignetteH = w, h
    vignetteCanvas = love.graphics.newCanvas(w, h)

    love.graphics.setCanvas(vignetteCanvas)
    love.graphics.clear(0, 0, 0, 0)

    -- Draw radial vignette using concentric rectangles (faster than per-pixel)
    local cx, cy = w / 2, h / 2
    local maxDist = math.sqrt(cx * cx + cy * cy)
    local steps = 64

    for i = steps, 1, -1 do
        local t = i / steps
        -- Alpha ramps up at edges
        local alpha = (1 - t) * (1 - t)  -- Quadratic falloff

        local rx = cx * t * 1.2  -- Slightly wider than tall for widescreen
        local ry = cy * t * 1.1

        love.graphics.setColor(0, 0, 0, alpha)
        love.graphics.rectangle("fill", cx - rx, cy - ry, rx * 2, ry * 2, rx * 0.3, ry * 0.3)
    end

    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1)
end

-- Draw vignette overlay
function Atmosphere.drawVignette(w, h)
    local strength, radius = Atmosphere.getVignette()
    if strength <= 0.01 then return end

    Atmosphere.generateVignette(w, h)

    -- Draw vignette with dynamic strength.
    -- The vignette canvas is black with a transparent-in-the-center alpha ramp,
    -- so it must be composited with alpha blending. Drawing it with "multiply"
    -- multiplied the whole screen center by (0,0,0) and blacked out the world.
    love.graphics.setColor(1, 1, 1, strength)
    love.graphics.draw(vignetteCanvas, 0, 0)
    love.graphics.setColor(1, 1, 1)
end

-- Draw full-screen darkness overlay (for disturbance pulses)
function Atmosphere.drawDisturbance(w, h)
    if not state.disturbActive or state.disturbValue < 0.01 then return end

    love.graphics.setColor(0, 0, 0, state.disturbValue * 0.6)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1)
end

-- Get raw state (for debug display)
function Atmosphere.getState()
    return state
end

-- Check if a preset exists for an environment
function Atmosphere.hasPreset(envName)
    return presets[envName] ~= nil
end

-- Get the current environment name
function Atmosphere.getEnvironment()
    return currentEnv
end

return Atmosphere
