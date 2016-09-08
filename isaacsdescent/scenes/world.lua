local Class = require 'vendor.hump.class'
local Vector = require 'vendor.hump.vector'

local BaseScene = require 'isaacsdescent.scenes.base'
local whammo = require 'isaacsdescent.whammo'

local WorldScene = Class{
    __includes = BaseScene,
}

function WorldScene:init(map)
    BaseScene.init(self)
    self.map = map
    self.actors = {}

    self.collider = whammo.Collider(4 * map.tilewidth)
    map:add_to_collider(self.collider)

    -- TODO this seems more a candidate for an 'enter' or map-switch event
    for _, template in ipairs(map.actor_templates) do
        -- TODO make me happen, and also, add in sprites
    end
end

--------------------------------------------------------------------------------
-- hump.gamestate hooks

function WorldScene:update(dt)
    for _, actor in ipairs(self.actors) do
        actor:update(dt)
    end
end

function WorldScene:draw()
    self.map:draw(Vector(0, 0))

    for _, actor in ipairs(self.actors) do
        actor:draw(dt)
    end
end

--------------------------------------------------------------------------------
-- API

function WorldScene:add_actor(actor)
    table.insert(self.actors, actor)

    self.collider:add(actor.shape)
end


return WorldScene
