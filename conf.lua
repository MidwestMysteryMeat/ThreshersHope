--[[
    LÖVE2D Configuration
    Raycaster Proof-of-Concept
]]

function love.conf(t)
    t.identity = "raycaster_poc"
    t.version = "11.4"

    t.window.title = "Raycaster - Proof of Concept"
    t.window.width = 800
    t.window.height = 600
    t.window.resizable = true
    t.window.minwidth = 640
    t.window.minheight = 480
    t.window.vsync = 0  -- Disable vsync to measure true FPS

    -- Disable unused modules for slightly better performance
    t.modules.joystick = false
    t.modules.physics = false
    t.modules.video = false
end
