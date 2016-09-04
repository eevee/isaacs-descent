local Class = require 'vendor.hump.class'
local Vector = require 'vendor.hump.vector'
local HC = require 'vendor.HC'

local BaseScene = require 'isaacsdescent.scenes.base'

local WorldScene = Class{
    __includes = BaseScene,
}

function WorldScene:init(map)
    BaseScene.init(self)
    self.map = map
    self.actors = {}

    self.collider = HC.new(4 * map.tilewidth)
    map:add_to_collider(self.collider)
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

    self.collider:register(actor.shape)
end


return WorldScene
