local Class = require 'vendor.hump.class'
local Vector = require 'vendor.hump.vector'

local whammo_shapes = require 'isaacsdescent.whammo.shapes'

-- TODO some overall questions about this setup:
-- 1. where should anchors and collision boxes live?  here?  on the sprites?  can i cram that into tiled?
-- 2. where are sprites even defined?  also in tiled, i guess?
-- 3. do these actors use the sprites given on the map, or what?  do they also name their own sprites?  can those conflict?

-- wooden switch (platforms)
local WoodenSwitch = Class{
    sprite_name = 'wooden_switch',
    anchor = Vector(0, 0),
    shape = whammo_shapes.Box(0, 0, 32, 32),
    -- TODO p8 has a "switched" pose

    -- TODO usesprite = declare_sprite{2},

    is_usable = true,
}

function WoodenSwitch:init(position)
    self.pos = position
    self.velocity = Vector.zero:clone()

    self.sprite = game.sprites[self.sprite_name]:instantiate()

    self.shape = self.shape:clone()
    self.initial_shape_offset = Vector(self.shape.x0, self.shape.y0)
    self.shape:move_to((position - self.anchor + self.initial_shape_offset):unpack())
end

function WoodenSwitch:blocks(actor, d)
    return false
end

function WoodenSwitch:reset()
    self.is_usable = true
    self:set_pose"default"
end

function WoodenSwitch:on_use(activator)
    -- TODO sfx(4)
    -- TODO self:set_pose"switched"
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

function WoodenSwitch:update(dt)
end

function WoodenSwitch:draw()
    self.sprite:draw_at(self.pos)
end

-- magical bridge, activated by wooden switch
local MagicalBridge = Class{
    sprite_name = 'magical_bridge',
    anchor = Vector(0, 0),
    shape = whammo_shapes.Box(0, 0, 32, 8),
}

function MagicalBridge:init(position)
    -- TODO lol
    WoodenSwitch.init(self, position)

    self.enabled = true
    self.timer = 0.8
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
    if not self.enabled or self.timer <= 0 then
	return
    end
    -- TODO redo this with hump's tweens
    self.timer = self.timer - dt
end

function MagicalBridge:draw()
    if self.timer > 0 then
	local alpha = self.timer / 0.8 * 255
	love.graphics.setColor(255, 255, 255, alpha)
	self.sprite:draw_at(self.pos)
	love.graphics.setColor(255, 255, 255)
    end
end


return {
    WoodenSwitch = WoodenSwitch,
    MagicalBridge = MagicalBridge,
}
