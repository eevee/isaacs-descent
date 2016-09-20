local Class = require 'vendor.hump.class'
local Vector = require 'vendor.hump.vector'

local actors_misc = require 'isaacsdescent.actors.misc'
local Player = require 'isaacsdescent.actors.player'
local BaseScene = require 'isaacsdescent.scenes.base'
local whammo = require 'isaacsdescent.whammo'

-- TODO yeah this sucks
local actors_lookup = {
    spikes_up = actors_misc.SpikesUp,
    magical_bridge = actors_misc.MagicalBridge,
    wooden_switch = actors_misc.WoodenSwitch,
}

local WorldScene = Class{
    __includes = BaseScene,
    __tostring = function(self) return "worldscene" end,
}

function WorldScene:init(map)
    BaseScene.init(self)

    self:load_map(map)
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

    do return end
    for shape in pairs(self.collider.shapes) do
        shape:draw('line')
    end

    if debug_hits then
        for hit, touchtype in pairs(debug_hits) do
            if touchtype > 0 then
                -- Collision: red
                love.graphics.setColor(255, 0, 0, 128)
            elseif touchtype < 0 then
                -- Overlap: blue
                love.graphics.setColor(0, 64, 255, 128)
            else
                -- Touch: green
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

function WorldScene:load_map(map)
    self.collider = whammo.Collider(4 * map.tilewidth)
    self.map = map
    self.actors = {}

    -- TODO this seems clearly wrong, especially since i don't clear the
    -- collider, but it happens to work (i think)
    map:add_to_collider(self.collider)
    -- TODO i feel like all this stuff is a /little/...  disconnected.  like
    -- what happens if an actor's shape changes?
    self.shape_to_actor = {}

    self.player = Player(Vector(1 * map.tilewidth, 8 * map.tileheight))
    self:add_actor(self.player)

    -- TODO this seems more a candidate for an 'enter' or map-switch event
    for _, template in ipairs(map.actor_templates) do
        local class = actors_lookup[template.name]
        self:add_actor(class(template.position))
    end
end

function WorldScene:reload_map()
    self:load_map(self.map)
end

function WorldScene:add_actor(actor)
    table.insert(self.actors, actor)

    self.collider:add(actor.shape)

    -- TODO again, yeah, what happens if the shape changes?
    self.shape_to_actor[actor.shape] = actor
end

function WorldScene:remove_actor(actor)
    -- TODO what if the actor is the player...?  should we unset self.player?

    -- TODO maybe an index would be useful
    for i, an_actor in ipairs(self.actors) do
        if actor == an_actor then
            local last = #self.actors
            self.actors[i] = self.actors[last]
            self.actors[last] = nil
            break
        end
    end

    self.collider:remove(actor.shape)

    self.shape_to_actor[actor.shape] = nil
end


return WorldScene
