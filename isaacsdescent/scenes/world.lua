local Class = require 'vendor.hump.class'
local Vector = require 'vendor.hump.vector'

local actors_misc = require 'isaacsdescent.actors.misc'
local BaseScene = require 'isaacsdescent.scenes.base'
local whammo = require 'isaacsdescent.whammo'

-- TODO yeah this sucks
local actors_lookup = {
    magical_bridge = actors_misc.MagicalBridge,
    wooden_switch = actors_misc.WoodenSwitch,
}

local WorldScene = Class{
    __includes = BaseScene,
}

function WorldScene:init(map)
    BaseScene.init(self)
    self.map = map
    self.actors = {}

    self.collider = whammo.Collider(2 * map.tilewidth)
    map:add_to_collider(self.collider)

    -- TODO this seems more a candidate for an 'enter' or map-switch event
    for _, template in ipairs(map.actor_templates) do
        local class = actors_lookup[template.name]
        self:add_actor(class(template.position))
    end
end

--------------------------------------------------------------------------------
-- hump.gamestate hooks

function WorldScene:update(dt)
    if love.keyboard.isDown('a') then
    for _, actor in ipairs(self.actors) do
        actor:update(dt)
    end
    end
end

function WorldScene:draw()
    self.map:draw(Vector(0, 0))

    for _, actor in ipairs(self.actors) do
        actor:draw(dt)
    end

    do return end
    for shape in pairs(self.collider.shapes) do
        shape:draw('line')
    end

    if debug_hits then
        for hit, is_collision in pairs(debug_hits) do
            if is_collision then
                love.graphics.setColor(255, 0, 0, 128)
            else
                love.graphics.setColor(0, 192, 0, 128)
            end
            hit:draw('fill')
            --love.graphics.setColor(255, 255, 0)
            --local x, y = hit:bbox()
            --love.graphics.print(("%0.2f"):format(d), x, y)
        end
        love.graphics.setColor(255, 255, 255)
    end
end

--------------------------------------------------------------------------------
-- API

function WorldScene:add_actor(actor)
    table.insert(self.actors, actor)

    self.collider:add(actor.shape)
end


return WorldScene
