local Class = require 'vendor.hump.class'
local Vector = require 'vendor.hump.vector'

local actors_base = require 'isaacsdescent.actors.base'
local whammo_shapes = require 'isaacsdescent.whammo.shapes'

-- TODO some overall questions about this setup:
-- 1. where should anchors and collision boxes live?  here?  on the sprites?  can i cram that into tiled?
-- 2. where are sprites even defined?  also in tiled, i guess?
-- 3. do these actors use the sprites given on the map, or what?  do they also name their own sprites?  can those conflict?


-- TODO this doesn't do most things an actor does, which means it has no shape
-- or sprite, which means other code trying to interfere with it might not work
-- so good.  but it also means i have to write my own dummy on_spawn?
-- do i need a BaseActor or something?
local Particle = Class{}

function Particle:init(position, velocity, acceleration, color, ttl)
    self.pos = position
    self.velocity = velocity
    self.acceleration = acceleration
    self.color = color
    self.ttl = ttl
end

function Particle:on_spawn()
end

function Particle:update(dt)
    self.velocity = self.velocity + self.acceleration * dt
    self.pos = self.pos + self.velocity * dt

    self.ttl = self.ttl - dt
    if self.ttl < 0 then
        worldscene:remove_actor(self)
    end
end

function Particle:draw()
    love.graphics.push('all')
    love.graphics.setColor(unpack(self.color))
    love.graphics.points(self.pos:unpack())
    love.graphics.pop()
end



-- spikes
local SpikesUp = Class{
    __includes = actors_base.Actor,

    sprite_name = 'spikes_up',
    anchor = Vector(0, 0),
    shape = whammo_shapes.Box(0, 24, 32, 8),
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

function Savepoint:on_spawn()
    for i = 1, 8 do
        local angle = love.math.random() * 6.28
        local direction = Vector(math.cos(angle), math.sin(angle))
        worldscene:add_actor(Particle(
            self.pos + direction * 4,
            direction * 32,
            Vector(0, 1),
            {190, 235, 113},
            1
        ))
    end
end

function Savepoint:update(dt)
    actors_base.Actor.update(self, dt)

    if love.math.random() < 0.0625 then
        local angle = love.math.random() * 6.28
        local direction = Vector(math.cos(angle), math.sin(angle))
        worldscene:add_actor(Particle(
            self.pos + direction * 8,
            direction * 16,
            Vector(0, 1),
            {190, 235, 113},
            1.5
        ))
    end
end


local Laser = Class{
    __includes = actors_base.Actor,

    sprite_name = 'laser_vert',
    fullbright = true,
    anchor = Vector(16, 0),
    shape = whammo_shapes.Box(14, 0, 4, 32),
}

function Laser:update(dt)
    actors_base.Actor.update(self, dt)

    self.laser_direction = Vector(0, 1)
    local impact, impactdist = worldscene.collider:fire_ray(
        self.pos,
        self.laser_direction,
        function (actor)
            if actor == self then
                return true
            else
                return false
            end
        end)
    self.laser_length = impactdist
    self.laser_vector = self.laser_direction * impactdist
    -- TODO this involves some kerjiggering and belongs in init
    --[[
    self.shape = whammo_shapes.Box(
        0.375, 0, 0.25, bottom.y - pos.y)
    ]]

    --local coll = self:coll()
    if math.random() < 0.1 then
        -- TODO should rotate this to face back along laser vector
        local angle = math.random() * math.pi * 2
        local direction = Vector(math.cos(angle), math.sin(angle))
        if direction * self.laser_vector > 0 then
            direction = -direction
        end
        worldscene:add_actor(Particle(
            self.pos + self.laser_vector,
            direction * 64,
            Vector.zero,
            {255, 0, 0},
            0.5))
    end
    -- TODO (a) no way to check for arbitrary collision at the moment
    -- TODO (b) surely this should be an oncollide -- the problem is that it
    -- doesn't count as a collision if the laser moves onto the player
    --[[
    if coll:overlaps(player:coll()) then
        player:die()
    end
    ]]
end

-- TODO custom drawing too
function Laser:draw()
    --actors_base.Actor.draw(self)
    local length = self.laser_length - 32
    -- TODO this is a clusterfuck
    love.graphics.push('all')
    love.graphics.setLineWidth(2)
    love.graphics.setColor(255, 0, 0)
    love.graphics.line(self.pos.x, self.pos.y, (self.pos + self.laser_vector):unpack())
    love.graphics.pop()
    --local pt = self.pos - self.anchor
    --self.sprite.anim:draw(self.sprite.sprite.image, pt.x, pt.y, 0, 1, length / 32)
    --pt = pt + self.laser_direction * length
    --self.sprite.sprite.poses['end/right']:draw(self.sprite.sprite.image, pt.x, pt.y, 0, 1, 1)
    --local coll = self:coll()
    --rectfill(coll.l * 8, coll.t * 8, coll.r * 8 - 1, coll.b * 8 - 1, 8)
end


-- TODO this should probably have a cute canon name
local LaserEye = Class{
    __includes = actors_base.Actor,

    sprite_name = 'laser_eye',
    anchor = Vector(16, 16),
    shape = whammo_shapes.Box(0, 0, 32, 32),

    sensor_range = 64,

    sleep_timer = 0,
}

function LaserEye:reset()
    self:sleep()
end

function LaserEye:sleep()
    self.sleep_timer = 0
    self.sprite:set_pose('default/right')
    if self.ptrs.laser then
        worldscene:remove_actor(self.ptrs.laser)
        self.ptrs.laser = nil
    end
end
function LaserEye:update(dt)
    -- TODO really, really want a bounding box type
    local px0, py0, px1, py1 = worldscene.player.shape:bbox()
    local sx0, sy0, sx1, sy1 = self.shape:bbox()
    local dist
    if sx1 < px0 then
        dist = px0 - sx1
    else
        dist = sx0 - px1
    end
    if dist < self.sensor_range then
        self.sprite:set_pose('awake/right')
        self.sleep_timer = 4
        if not self.ptrs.laser then
            local laser = Laser(self.pos + Vector(0, 16))
            self.ptrs.laser = laser
            worldscene:add_actor(laser)
        end
    elseif self.sleep_timer > 0 then
        self.sleep_timer = self.sleep_timer - dt
        if self.sleep_timer <= 0 then
            self:sleep()
        end
    end
    actors_base.Actor.update(self, dt)
-- TODO movement
--[[
    if self.pose == "awake" then
        local dx = 0.125
        local d0 = self.pos.x - self.pos0.x
        if d0 > 4 then
            self.reverse = true
        elseif d0 < -4 then
            self.reverse = false
        end
        if self.reverse then
            dx *= -1
        end
        self.pos.x += dx
        if self.laser then
            self.laser.pos.x += dx
        end
    end
]]
end


return {
    SpikesUp = SpikesUp,
    WoodenSwitch = WoodenSwitch,
    MagicalBridge = MagicalBridge,
    Savepoint = Savepoint,
    LaserEye = LaserEye,
}
