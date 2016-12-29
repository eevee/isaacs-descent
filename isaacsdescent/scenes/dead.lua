local Class = require 'vendor.hump.class'
local Gamestate = require 'vendor.hump.gamestate'
local Vector = require 'vendor.hump.vector'
local flux = require 'vendor.flux'

local BaseScene = require 'isaacsdescent.scenes.base'
local SceneFader = require 'isaacsdescent.scenes.fader'

local DeadScene = Class{
    __includes = BaseScene,
    __tostring = function(self) return "deadscene" end,

    wrapped = nil,
}

-- TODO it would be nice if i could formally eat keyboard input
function DeadScene:init(wrapped)
    BaseScene.init(self)

    self.wrapped = nil
end

function DeadScene:enter(previous_scene)
    self.wrapped = previous_scene
end

function DeadScene:update(dt)
    flux.update(dt)
    self.wrapped:update(dt)
end

function DeadScene:draw()
    self.wrapped:draw()

    love.graphics.push('all')
    local w, h = love.graphics.getDimensions()

    -- Draw a dark stripe across the middle of the screen for printing text on.
    -- We draw it twice, the first time slightly taller, so it has a slight
    -- fade on the top and bottom edges
    local bg_height = love.graphics.getHeight() / 4
    love.graphics.setColor(0, 0, 0, 128)
    love.graphics.rectangle('fill', 0, (h - bg_height) / 2, w, bg_height)
    love.graphics.rectangle('fill', 0, (h - bg_height) / 2 + 2, w, bg_height - 4)

    -- Give some helpful instructions
    -- FIXME this doesn't explain how to use the staff.  i kind of feel like
    -- that should be a ui hint in the background, anyway?  like attached to
    -- the inventory somehow.  maybe you even have to use it
    love.graphics.setColor(255, 255, 255)
    love.graphics.printf("you died\npress r to restart", 0, (h - m5x7:getHeight() * 2) / 2, w, "center")

    love.graphics.pop()
end

function DeadScene:keypressed(key, scancode, isrepeat)
    -- TODO really, this should load some kind of more formal saved game
    -- TODO also i question this choice of key
    if key == 'r' then
        Gamestate.switch(SceneFader(
            self.wrapped, true, 0.5, {0, 0, 0},
            function()
                self.wrapped:reload_map()
            end
        ))
    elseif key == 'e' then
        -- TODO this seems really invasive!
        -- FIXME hardcoded color, as usual
        local player = self.wrapped.player
        if player.ptrs.savepoint then
            Gamestate.switch(SceneFader(
                self.wrapped, true, 0.25, {140, 214, 18},
                function()
                    -- TODO shouldn't this logic be in the staff or the savepoint somehow?
                    -- TODO eugh this magic constant
                    player:move_to(player.ptrs.savepoint.pos + Vector(0, 16))
                    player:resurrect()
                    -- TODO hm..  this will need doing anytime the player is forcibly moved
                    worldscene:update_camera()
                end))
        end
    end
end

return DeadScene
