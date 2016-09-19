local Class = require 'vendor.hump.class'
local Gamestate = require 'vendor.hump.gamestate'

local BaseScene = require 'isaacsdescent.scenes.base'

local DeadScene = Class{
    __includes = BaseScene,
    __tostring = function(self) return "deadscene" end,
}

-- TODO it would be nice if i could formally eat keyboard input
function DeadScene:init(wrapped)
    BaseScene.init(self)

    self.wrapped = wrapped
end

function DeadScene:update(dt)
    -- TODO really, this should load some kind of more formal saved game
    -- TODO also i question this choice of key, and it should only work if it wasn't held down the previous frame...
    if love.keyboard.isDown('e') then
        self.wrapped:reload_map()
        Gamestate.switch(self.wrapped)
        return
    end

    self.wrapped:update(dt)
end

function DeadScene:draw()
    self.wrapped:draw()

    love.graphics.setColor(0, 0, 0, 64)
    love.graphics.rectangle('fill', 0, 0, love.graphics.getDimensions())

    local w, h = love.graphics.getDimensions()


    love.graphics.setColor(255, 255, 255)
    love.graphics.printf("you died\npress e to restart", w/2, h/2, 400, "center")
end

return DeadScene
