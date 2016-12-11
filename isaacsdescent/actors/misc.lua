local Class = require 'vendor.hump.class'
local Vector = require 'vendor.hump.vector'

local actors_base = require 'isaacsdescent.actors.base'
local whammo_shapes = require 'isaacsdescent.whammo.shapes'

-- TODO some overall questions about this setup:
-- 1. where should anchors and collision boxes live?  here?  on the sprites?  can i cram that into tiled?
-- 2. where are sprites even defined?  also in tiled, i guess?
-- 3. do these actors use the sprites given on the map, or what?  do they also name their own sprites?  can those conflict?

-- spikes
local SpikesUp = Class{
    __includes = actors_base.Actor,

    sprite_name = 'spikes_up',
    anchor = Vector(0, 0),
    shape = whammo_shapes.Box(0, 24, 32, 32),
}

function SpikesUp:blocks(actor, d)
    return true
end

function SpikesUp:on_collide(other, direction)
    if other.is_player then
	-- TODO i feel that damage should be dealt in a more roundabout way?
	other:die()
    end
end


-- wooden switch (platforms)
local WoodenSwitch = Class{
    __includes = actors_base.Actor,

    sprite_name = 'wooden_switch',
    anchor = Vector(0, 0),
    shape = whammo_shapes.Box(0, 0, 32, 32),
    -- TODO p8 has a "switched" pose

    -- TODO usesprite = declare_sprite{2},

    is_usable = true,
}

-- TODO nothing calls this
function WoodenSwitch:reset()
    self.is_usable = true
    self:set_pose"default"
end

function WoodenSwitch:on_use(activator)
    -- TODO sfx(4)
    self.sprite:set_pose('switched/right')
    self.is_usable = false

    -- TODO probably wants a real API
    -- TODO worldscene is a global...
    for _, actor in ipairs(worldscene.actors) do
	-- TODO would be nice if this could pick more specific targets, not just the entire map
        if actor.on_activate then
	    actor:on_activate()
        end
    end
end


-- magical bridge, activated by wooden switch
local MagicalBridge = Class{
    __includes = actors_base.Actor,

    sprite_name = 'magical_bridge',
    anchor = Vector(0, 0),
    shape = whammo_shapes.Box(0, 0, 32, 8),
}

function MagicalBridge:init(position)
    actors_base.Actor.init(self, position)

    self.enabled = false
    self.timer = 0
end

function MagicalBridge:blocks(actor, d)
    return self.enabled
end

function MagicalBridge:reset()
    -- disabled by default
    -- TODO do i want this same global 'enabled' concept?  seems hokey
    self.enabled = false
    decoractor.reset(self)
end

function MagicalBridge:on_activate()
    -- TODO should check for a blocker and refuse to materialize, or delay
    -- materializing?
    self.enabled = true
    self.timer = 0.8
end

function MagicalBridge:update(dt)
    -- TODO decoractor.update(self)
    if self.enabled and self.timer > 0 then
	-- TODO redo this with hump's tweens
	self.timer = self.timer - dt
    end
end

function MagicalBridge:draw()
    if self.enabled then
	if self.timer > 0 then
	    local alpha = (1 - self.timer / 0.8) * 255
	    love.graphics.setColor(255, 255, 255, alpha)
	    self.sprite:draw_at(self.pos)
	    love.graphics.setColor(255, 255, 255)
	else
	    self.sprite:draw_at(self.pos)
	end
    end
end


local Savepoint = Class{
    __includes = actors_base.Actor,

    sprite_name = 'savepoint',
    anchor = Vector(16, 16),
    shape = whammo_shapes.Box(0, 0, 32, 32),
    -- TODO z?  should always be in background
}


return {
    SpikesUp = SpikesUp,
    WoodenSwitch = WoodenSwitch,
    MagicalBridge = MagicalBridge,
    Savepoint = Savepoint,
}
