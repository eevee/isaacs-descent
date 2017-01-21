local Class = require 'vendor.hump.class'
local Vector = require 'vendor.hump.vector'

local actors_base = require 'klinklang.actors.base'
local actors_misc = require 'klinklang.actors.misc'
local whammo_shapes = require 'klinklang.whammo.shapes'

-- TODO some overall questions about this setup:
-- 1. where should anchors and collision boxes live?  here?  on the sprites?  can i cram that into tiled?
-- 2. where are sprites even defined?  also in tiled, i guess?
-- 3. do these actors use the sprites given on the map, or what?  do they also name their own sprites?  can those conflict?


-- spikes
local SpikesUp = Class{
    __includes = actors_base.Actor,

    sprite_name = 'spikes_up',
    anchor = Vector(0, 0),
    shape = whammo_shapes.Box(0, 24, 32, 8),
}

function SpikesUp:blocks(actor, d)
    return false
end

function SpikesUp:on_collide(other, direction)
    -- FIXME this gets the /full/ direction, not just the collision direction,
    -- so it doesn't work for "am i landing on the spikes" -- i could come in
    -- down-diagonally on one side, or i could be falling past without
    -- colliding
    if other.is_player and direction.y > 0 then
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
    self.sprite:set_pose('switched')
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
        worldscene:add_actor(actors_misc.Particle(
            self.pos + direction * 4,
            direction * 32 * love.math.random(0.75, 1),
            Vector(0, 1),
            {190, 235, 113},
            1, true
        ))
    end
end

function Savepoint:update(dt)
    actors_base.Actor.update(self, dt)

    if love.math.random() < 0.0625 then
        local angle = love.math.random() * 6.28
        local direction = Vector(math.cos(angle), math.sin(angle))
        worldscene:add_actor(actors_misc.Particle(
            self.pos + direction * 8,
            direction * 16,
            Vector(0, 1),
            {190, 235, 113},
            1.5, true
        ))
    end
end


local Laser = Class{
    __includes = actors_base.Actor,

    sprite_name = 'laser_vert',
    fullbright = true,
    anchor = Vector(16, 0),
    shape = whammo_shapes.Box(14, 0, 4, 32),

    laser_length = 0,
    laser_vector = Vector.zero,
}

function Laser:update(dt)
    actors_base.Actor.update(self, dt)

    self.laser_direction = Vector(0, 1)
    local impact, impactdist = worldscene.collider:fire_ray(
        self.pos,
        self.laser_direction,
        function (actor)
            if actor ~= nil then
                return true
            else
                return false
            end
        end)
    self.laser_length = impactdist
    self.laser_vector = self.laser_direction * impactdist
    self:set_shape(whammo_shapes.Box(14, 0, 4, self.laser_length))

    if math.random() < 0.1 then
        -- TODO should rotate this to face back along laser vector
        local angle = math.random() * math.pi * 2
        local direction = Vector(math.cos(angle), math.sin(angle))
        if direction * self.laser_vector > 0 then
            direction = -direction
        end
        worldscene:add_actor(actors_misc.Particle(
            self.pos + self.laser_vector,
            direction * 64,
            Vector.zero,
            {255, 0, 0},
            0.5))
    end
end

-- TODO custom drawing too
function Laser:draw()
    --actors_base.Actor.draw(self)
    local length = self.laser_length - 32
    -- TODO this is a clusterfuck
    love.graphics.push('all')
    love.graphics.setLineWidth(2)
    -- FIXME where does this color come from?  should probably use a sprite regardless
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

function Laser:on_collide(other, direction)
    if other.is_player then
        -- TODO i feel that damage should be dealt in a more roundabout way?
        other:die()
    end
end


-- TODO this should probably have a cute canon name
local LaserEye = Class{
    __includes = actors_base.MobileActor,

    sprite_name = 'laser_eye',
    anchor = Vector(16, 16),
    shape = whammo_shapes.Box(0, 0, 32, 32),

    sensor_range = 64,
    sleep_timer = 0,
    is_awake = false,

    is_floating = true,
    -- We don't accelerate, so ignore friction as well
    friction = 0,
}

function LaserEye:init(...)
    actors_base.MobileActor.init(self, ...)
    self.pos0 = self.pos
    self.waking_velocity = Vector(64, 0)
    self.velocity = self.waking_velocity:clone()
end

function LaserEye:reset()
    self:sleep()
end

function LaserEye:sleep()
    self.is_awake = false
    self.sleep_timer = 0
    self.sprite:set_pose('default')
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
        self.sprite:set_pose('awake')
        self.is_awake = true
        self.sleep_timer = 4
        if not self.ptrs.laser then
            local laser = Laser(self.pos + Vector(0, 12))
            self.ptrs.laser = laser
            worldscene:add_actor(laser)
        end
    elseif self.sleep_timer > 0 then
        self.sleep_timer = self.sleep_timer - dt
        if self.sleep_timer <= 0 then
            self:sleep()
        end
    end

    if self.is_awake then
        actors_base.MobileActor.update(self, dt)
        -- Keep the laser in lockstep with us
        if self.ptrs.laser then
            self.ptrs.laser:move_to(self.pos + Vector(0, 12))
        end
        -- If we hit something (which cuts our velocity), reverse direction
        if self.velocity:len2() < self.waking_velocity:len2() then
            self.waking_velocity = - self.waking_velocity
            self.velocity = self.waking_velocity:clone()
        end
    else
        -- Still need to update the sprite!!
        -- FIXME this is a running theme
        actors_base.Actor.update(self, dt)
    end
end


local StoneDoor = Class{
    __includes = actors_base.Actor,

    sprite_name = 'stone_door',
    anchor = Vector(16, 0),
    shape = whammo_shapes.Box(0, 0, 32, 32),

    door_height = 0,
    busy = false,
}

-- FIXME what happens if you stick a rune in an open doorway?
function StoneDoor:on_spawn()
    -- FIXME this "ray" should really have a /width/
    local impact, impactdist = worldscene.collider:fire_ray(
        self.pos,
        Vector(0, 1),
        function (actor)
            return actor == self
        end)
    -- FIXME if the ray doesn't hit anything, it returns...  infinity.  also it
    -- doesn't actually walk the whole blockmap, oops!
    if impactdist == math.huge then
        impactdist = 0
    end
    self:set_shape(whammo_shapes.Box(0, 0, 32, impactdist))
    self.door_height = impactdist
end

function StoneDoor:blocks()
    return true
end

function StoneDoor:update(dt)
end

function StoneDoor:draw()
    local pt = self.pos - self.anchor
    love.graphics.push('all')
    -- FIXME maybe worldscene needs a helper for this
    love.graphics.setScissor(pt.x - worldscene.camera.x, pt.y - worldscene.camera.y, 32, self.door_height)
    local height = self.door_height + (-self.door_height) % 32
    local top = pt.y - (-self.door_height) % 32
    local bottom = pt.y + self.door_height, 32
    for y = top, bottom, 32 do
        local sprite = self.sprite.anim
        if y == bottom - 32 then
            -- FIXME invasive...
            sprite = self.sprite.spriteset.poses['end'].right
        end
        sprite:draw(self.sprite.spriteset.image, pt.x, y)
    end
    love.graphics.pop()
    --pt = pt + Vector(0, 1) * self.door_height
    --:draw(self.sprite.sprite.image, pt.x, pt.y, 0, 1, 1)
    --local coll = self:coll()
    --rectfill(coll.l * 8, coll.t * 8, coll.r * 8 - 1, coll.b * 8 - 1, 8)
end

function StoneDoor:open()
    if self.busy then
        return
    end
    self.busy = true
    if self.door_height <= 32 then
        return
    end

    -- FIXME i would like some little dust clouds
    -- FIXME grinding noise
    -- FIXME what happens if the door hits something?
    local height = self.door_height
    local time = height / 30
    worldscene.fluct:to(self, time, { door_height = 32 })
        :ease('linear')
        :onupdate(function() self:set_shape(whammo_shapes.Box(0, 0, 32, self.door_height)) end)
        :after(time, { door_height = height })
        :delay(4)
        :ease('linear')
        :onupdate(function() self:set_shape(whammo_shapes.Box(0, 0, 32, self.door_height)) end)
        :oncomplete(function() self.busy = false end)
end


-- TODO this should probably have a cute canon name
local StoneDoorShutter = Class{
    __includes = actors_base.Actor,

    sprite_name = 'stone_door_shutter',
    anchor = Vector(16, 0),
    shape = whammo_shapes.Box(0, 0, 32, 32),
}

function StoneDoorShutter:init(...)
    actors_base.Actor.init(self, ...)
end

function StoneDoorShutter:on_spawn()
    local door = StoneDoor(self.pos + Vector(0, 32))
    self.ptrs.door = door
    worldscene:add_actor(door)
end

function StoneDoorShutter:blocks(actor, dir)
    return true
end

function StoneDoorShutter:on_activate()
    self.sprite:set_pose('active')
    -- FIXME original code plays animation (and stays unusable) for one second
    self.ptrs.door:open()
end


-- wooden wheel (stone doors)
local WoodenWheel = Class{
    __includes = actors_base.Actor,

    sprite_name = 'wooden_wheel',
    anchor = Vector(0, 0),
    shape = whammo_shapes.Box(0, 0, 32, 32),

    is_usable = true,
}

-- TODO nothing calls this
function WoodenWheel:reset()
    self.is_usable = true
    self:set_pose"default"
end

function WoodenWheel:on_use(activator)
    -- TODO sfx(4)
    self.sprite:set_pose('turning')
    self.is_usable = false

    -- TODO probably wants a real API
    -- TODO worldscene is a global...
    -- FIXME oops, this will activate both doors /and/ bridges
    for _, actor in ipairs(worldscene.actors) do
        -- TODO would be nice if this could pick more specific targets, not just the entire map
        if actor.on_activate then
            actor:on_activate()
        end
    end

    -- FIXME this should really use the tick library
    worldscene.fluct:to(self, 1, {}):oncomplete(function() self.sprite:set_pose('default') self.is_usable = true end)
end


-- inventory items
local TomeOfLevitation = Class{
    __includes = actors_base.Actor,

    sprite_name = 'tome_of_levitation',
    anchor = Vector(0, 0),
    shape = whammo_shapes.Box(0, 0, 32, 32),
    is_floating = true,

    -- inventory
    display_name = 'Tome of Freefall',
}

function TomeOfLevitation:update(dt)
    actors_base.Actor.update(self, dt)
    -- FIXME this is basically duplicated for isaac, but it's also not really
    -- an appropriate effect here i think?
    if math.random() < dt * 4 then
        worldscene:add_actor(actors_misc.Particle(
            self.pos + Vector(math.random() * 32, 32), Vector(0, -32), Vector(0, 0),
            {255, 255, 255}, 1.5, true))
    end
end

function TomeOfLevitation:on_inventory_use(activator)
    if activator.is_floating then
        activator.is_floating = false
    elseif activator.on_ground then
        activator.is_floating = true
    end
end

function TomeOfLevitation:on_collide(other, direction)
    if other.is_player then
        table.insert(other.inventory, TomeOfLevitation)
        worldscene:remove_actor(self)
    end
end




return {
    SpikesUp = SpikesUp,
    WoodenSwitch = WoodenSwitch,
    MagicalBridge = MagicalBridge,
    Savepoint = Savepoint,
    LaserEye = LaserEye,
    StoneDoorShutter = StoneDoorShutter,
    WoodenWheel = WoodenWheel,
    TomeOfLevitation = TomeOfLevitation,
}
