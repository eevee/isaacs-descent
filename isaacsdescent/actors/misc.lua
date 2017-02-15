local Gamestate = require 'vendor.hump.gamestate'
local Vector = require 'vendor.hump.vector'

local Object = require 'klinklang.object'
local actors_base = require 'klinklang.actors.base'
local actors_misc = require 'klinklang.actors.misc'
local whammo_shapes = require 'klinklang.whammo.shapes'
local SceneFader = require 'klinklang.scenes.fader'
local CreditsScene = require 'isaacsdescent.scenes.credits'

-- TODO some overall questions about this setup:
-- 1. where should anchors and collision boxes live?  here?  on the sprites?  can i cram that into tiled?
-- 2. where are sprites even defined?  also in tiled, i guess?
-- 3. do these actors use the sprites given on the map, or what?  do they also name their own sprites?  can those conflict?


-- spikes
local SpikesUp = actors_base.Actor:extend{
    name = 'spikes_up',
    sprite_name = 'spikes_up',
}

function SpikesUp:blocks(actor, d)
    return false
end

function SpikesUp:on_collide(actor, movement, collision)
    if actor.is_player and collision.touchtype >= 0 and actors_base.any_normal_faces(collision, Vector(0, -1)) then
        -- TODO i feel that damage should be dealt in a more roundabout way?
        actor:die()
    end
end


-- wooden switch (platforms)
local WoodenSwitch = actors_base.Actor:extend{
    name = 'wooden_switch',
    sprite_name = 'wooden_switch',

    -- TODO usesprite = declare_sprite{2},

    is_usable = true,
}

-- TODO nothing calls this
function WoodenSwitch:reset()
    self.is_usable = true
    self:set_pose"default"
end

function WoodenSwitch:on_use(activator)
    game.resource_manager:get('assets/sounds/lever.ogg'):play()
    self.sprite:set_pose('switched')
    self.is_usable = false

    -- TODO probably wants a real API
    -- TODO worldscene is a global...
    worldscene.tick:delay(function()
        game.resource_manager:get('assets/sounds/platforms-appear.ogg'):play()
        for _, actor in ipairs(worldscene.actors) do
            -- TODO would be nice if this could pick more specific targets, not just the entire map
            if actor.on_activate_lever then
                actor:on_activate_lever()
            end
        end
    end, 0.5)
end


-- magical bridge, activated by wooden switch
local MagicalBridge = actors_base.Actor:extend{
    name = 'magical_bridge',
    sprite_name = 'magical_bridge',
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
    -- FIXME this is unused, and will break anyway
    -- TODO do i want this same global 'enabled' concept?  seems hokey
    self.enabled = false
    decoractor.reset(self)
end

function MagicalBridge:on_activate_lever()
    -- TODO should check for a blocker and refuse to materialize, or delay
    -- materializing?
    self.enabled = true
    self.opacity = 0
    worldscene.fluct:to(self, 0.5, { opacity = 1 })
end

function MagicalBridge:draw()
    if self.enabled then
        if self.opacity < 1 then
            love.graphics.setColor(255, 255, 255, self.opacity * 255)
            self.sprite:draw_at(self.pos)
            love.graphics.setColor(255, 255, 255)
        else
            self.sprite:draw_at(self.pos)
        end
    end
end


local Savepoint = actors_base.Actor:extend{
    name = 'savepoint',
    sprite_name = 'savepoint',
    z = -1000,
}

function Savepoint:on_enter()
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


local Laser = actors_base.Actor:extend{
    name = 'laser_vert',
    sprite_name = 'laser_vert',
    fullbright = true,

    laser_length = 0,
    laser_vector = Vector.zero,
}

function Laser:init(...)
    Laser.__super.init(self, ...)

    self.sfx = game.resource_manager:get('assets/sounds/laser.ogg'):clone()
    self.sfx:setVolume(0.75)
    self.sfx:setLooping(true)
    self.sfx:setAttenuationDistances(game.TILE_SIZE * 4, game.TILE_SIZE * 32)
end

function Laser:on_enter()
    Laser.__super.on_enter(self)
    self.sfx:play()
end

function Laser:on_leave()
    Laser.__super.on_leave(self)
    self.sfx:stop()
end

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
    self:set_shape(whammo_shapes.Box(-2, 0, 4, self.laser_length))

    self.sfx:setPosition(self.pos.x + self.laser_vector.x, self.pos.y + self.laser_vector.y, 0)

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
local LaserEye = actors_base.MobileActor:extend{
    name = 'laser_eye',
    sprite_name = 'laser_eye',

    sensor_range = 32 * 4,
    sleep_timer = 0,
    is_awake = false,

    gravity_multiplier = 0,
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
            -- FIXME it would be nice to be able to specify extra custom anchors on a particular sprite?
            local laser = Laser(self.pos + Vector(0, 28))
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
            self.ptrs.laser:move_to(self.pos + Vector(0, 28))
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


local StoneDoor = actors_base.Actor:extend{
    name = 'stone_door',
    sprite_name = 'stone_door',

    door_height = 0,
    busy = false,
}

function StoneDoor:init(...)
    StoneDoor.__super.init(self, ...)

    self.sfx = game.resource_manager:get('assets/sounds/stonegrind.ogg'):clone()
    self.sfx:setVolume(0.75)
    self.sfx:setLooping(true)
    self.sfx:setPosition(self.pos.x, self.pos.y, 0)
    self.sfx:setAttenuationDistances(game.TILE_SIZE * 4, game.TILE_SIZE * 32)
end

-- FIXME what happens if you stick a rune in an open doorway?
function StoneDoor:on_enter()
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
    self:set_shape(whammo_shapes.Box(-12, 0, 24, impactdist))
    self.door_height = impactdist
end

function StoneDoor:on_leave()
    self.sfx:stop()
end

function StoneDoor:blocks()
    return true
end

function StoneDoor:update(dt)
end

function StoneDoor:draw()
    local pt = self.pos - self.sprite.anchor
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
            sprite = self.sprite.spriteset.poses['end'].right.animation
        end
        sprite:draw(self.sprite.spriteset.image, math.floor(pt.x), math.floor(y))
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
        :onupdate(function() self:set_shape(whammo_shapes.Box(-12, 0, 24, self.door_height)) end)
        :onstart(function() self.sfx:play() end)
        :oncomplete(function() self.sfx:stop() end)
        :after(time, { door_height = height })
        :delay(4)
        :ease('linear')
        :onupdate(function() self:set_shape(whammo_shapes.Box(-12, 0, 24, self.door_height)) end)
        :oncomplete(function() self.busy = false end)
        :onstart(function() self.sfx:play() end)
        :oncomplete(function() self.sfx:stop() end)
end


-- TODO this should probably have a cute canon name
local StoneDoorShutter = actors_base.Actor:extend{
    name = 'stone door shutter',
    sprite_name = 'stone_door_shutter',
}

function StoneDoorShutter:init(...)
    actors_base.Actor.init(self, ...)
end

function StoneDoorShutter:on_enter()
    -- FIXME this number is kind of arbitrarily based on the arbitrary anchors
    -- i gave both the shutter and the door, hmm
    local door = StoneDoor(self.pos + Vector(0, 16))
    self.ptrs.door = door
    worldscene:add_actor(door)
end

function StoneDoorShutter:blocks(actor, dir)
    return true
end

function StoneDoorShutter:on_activate_wheel()
    self.sprite:set_pose('active')
    -- FIXME original code plays animation (and stays unusable) for one second
    self.ptrs.door:open()
end


-- wooden wheel (stone doors)
local WoodenWheel = actors_base.Actor:extend{
    name = 'wooden wheel',
    sprite_name = 'wooden_wheel',

    is_usable = true,
}

-- TODO nothing calls this
function WoodenWheel:reset()
    self.is_usable = true
    self:set_pose"default"
end

function WoodenWheel:on_use(activator)
    game.resource_manager:get('assets/sounds/wheel.ogg'):play()
    self.sprite:set_pose('turning')
    self.is_usable = false

    -- TODO probably wants a real API
    -- TODO worldscene is a global...
    -- FIXME oops, this will activate both doors /and/ bridges
    for _, actor in ipairs(worldscene.actors) do
        -- TODO would be nice if this could pick more specific targets, not just the entire map
        if actor.on_activate_wheel then
            actor:on_activate_wheel()
        end
    end

    -- FIXME this should really use the tick library
    worldscene.fluct:to(self, 1, {}):oncomplete(function() self.sprite:set_pose('default') self.is_usable = true end)
end


-- inventory items
local TomeOfLevitation = actors_base.Actor:extend{
    name = 'tome of levitation',
    sprite_name = 'tome_of_levitation',
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
        game.resource_manager:get('assets/sounds/uncast.ogg'):play()
        activator.is_floating = false
    elseif activator.on_ground then
        game.resource_manager:get('assets/sounds/cast.ogg'):play()
        activator.is_floating = true
    end
end

function TomeOfLevitation:on_collide(other, direction)
    if other.is_player then
        game.resource_manager:get('assets/sounds/pickup.ogg'):play()
        table.insert(other.inventory, TomeOfLevitation)
        worldscene:remove_actor(self)
    end
end


local Flurry = actors_base.Actor:extend{
    name = 'flurry',
    sprite_name = 'flurry',
    is_floating = true,
}

function Flurry:on_collide(other, direction)
    worldscene:remove_actor(self)
    worldscene.music:stop()
    game.resource_manager:get('assets/sounds/win.ogg'):play()
    worldscene.tick:delay(function()
        Gamestate.switch(SceneFader(CreditsScene(), false, 2, {0, 0, 0}))
    end, 2)
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
