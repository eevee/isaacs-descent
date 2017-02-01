local anim8 = require 'vendor.anim8'
local Gamestate = require 'vendor.hump.gamestate'
local Vector = require 'vendor.hump.vector'

local BaseScene = require 'klinklang.scenes.base'
local SceneFader = require 'klinklang.scenes.fader'

local TitleScene = BaseScene:extend{
    __tostring = function(self) return "title" end,
}

-- TODO maybe pluck the reusable bits of this out into klinklang
function TitleScene:init(next_scene, map_path)
    TitleScene.__super.init(self)
    self.next_scene = next_scene

    self.music = love.audio.newSource('assets/music/isaac-title.ogg')
    self.music:setLooping(true)
    self.image = love.graphics.newImage('assets/images/title-poc.png')

    self.map_path = map_path
    self.load_state = 0
end

function TitleScene:enter()
    self.music:play()
end

function TitleScene:update(dt)
    if self.load_state == 1 then
        -- Only start to load the map AFTER we've drawn at least one frame, so
        -- the player isn't staring at a blank screen
        local tiledmap = require('klinklang.tiledmap')
        local map = tiledmap.TiledMap(self.map_path, game.resource_manager)
        self.next_scene:load_map(map)
        self.load_state = 2
    end
end

function TitleScene:draw()
    if self.load_state == 0 then
        self.load_state = 1
    end

    love.graphics.push('all')

    local w, h = love.graphics.getDimensions()
    love.graphics.draw(self.image, 0, 0, 0, 2)
    love.graphics.setFont(m5x7small)
    love.graphics.printf("v" .. game.VERSION, 0, h - m5x7small:getHeight() - 4, w - 4, "right")

    love.graphics.pop()
end

function TitleScene:_advance()
    Gamestate.switch(SceneFader(self.next_scene, false, 1.0, {0, 0, 0}))
end

-- FIXME i would like this to ignore alt-tabs and lone presses of modifiers
function TitleScene:keypressed(key, scancode, isrepeat)
    if love.keyboard.isDown('lalt', 'ralt') then
        return
    end
    if isrepeat then
        return
    end
    self:_advance()
end

function TitleScene:gamepadpressed(joystick, button)
    self:_advance()
end


return TitleScene
