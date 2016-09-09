local Class = require 'vendor.hump.class'
local Vector = require 'vendor.hump.vector'

local util = require 'isaacsdescent.util'
local whammo_shapes = require 'isaacsdescent.whammo.shapes'


-- TODO convert these to native units once you're confident these are the same
local TILE_SIZE = 32
local PICO8V = TILE_SIZE / (1/30)
local PICO8A = TILE_SIZE / (1/30) / (1/30)
local PlayerActor = Class{
    -- TODO consider splitting me into components
    -- TODO separate code from twiddles
    pos = nil,
    velocity = nil,
    shape = whammo_shapes.Box(0, 0, 32, 64),

    -- Visuals (should maybe be wrapped in another object?)
    sprite_name = 'isaac',
    facing_left = false,

    -- Passive physics parameters
    -- Units are pixels and seconds!
    min_speed = 1/64 * PICO8V,
    max_speed = 1/4 * PICO8V,
    -- TODO this is kind of hard to convert from pico-8 units to seconds; this is in frames, which i assume are 60 fps
    --friction = math.sqrt(0.625),
    --friction = 1/16 * PICO8A,
    friction = 1,

    -- Active physics parameters
    --xaccel = 0.125 * PICO8A,
    xaccel = 0.0625 * PICO8A,
    xdecel = 0.0625 * PICO8A,
    max_jumptime = 4 / 30,
    -- determined experimentally
    -- to make max jump 2 tiles
    yaccel = (7/64 + 1/16) * PICO8A,
    -- multiplied by xaccel while
    -- airborne
    aircontrol = 0.5,

    -- Physics state
    on_ground = false,
}
local gravity = Vector(0, 1/16 * PICO8A)
local terminal_velocity = 7/8 * PICO8V

function PlayerActor:init(position)
    self.pos = position
    self.velocity = Vector(0, 0)

    -- TODO arrgh, this global.  sometimes i just need access to the game.
    -- should this be done on enter, maybe?
    self.sprite = game.sprites[self.sprite_name]:instantiate()

    -- TODO would like to have an anchor property
    self.shape:move(position:unpack())
    --[[
    local center = Vector(self.shape:center())
    self.shape:moveTo((self.pos + center):unpack())
    ]]
end

function PlayerActor:update(dt)
    local xmult = 1
    if not self.on_ground then
        xmult = self.aircontrol
    end
    print()
    print()

    -- Explicit movement
    -- TODO should be whichever was pressed last?
    if love.keyboard.isDown('right') then
        self.velocity.x = self.velocity.x + self.xaccel * xmult * dt
    elseif love.keyboard.isDown('left') then
        self.velocity.x = self.velocity.x - self.xaccel * xmult * dt
    else
        -- Decelerate when not holding a key
        -- TODO this still doesn't /quite/ work with slopes because it doesn't
        -- counteract gravity
        if self.last_slide and (self.velocity.x ~= 0 or self.velocity.y ~= 0) then
            local slide1 = self.last_slide:projectOn(self.velocity):normalized()
            local dot = slide1 * self.velocity
            local decel = self.xdecel * dt
            if dot > 0 then
                slide1 = -slide1
            else
                dot = -dot
            end
            if dot < decel then
                decel = dot
            end
            self.velocity = self.velocity + slide1 * decel
        end
    end

    -- Jumping
    if love.keyboard.isDown('space') then
        if self.jumptime < self.max_jumptime then
            -- Be sure to actually cap the amount of jump time we give
            local jt = math.min(dt, self.max_jumptime - self.jumptime)
            self.velocity.y = self.velocity.y - self.yaccel * jt
            --[[ TODO
            if self.jumptime == 0 then
                [sound effect]
            end
            ]]
            self.jumptime = self.jumptime + dt
        end
    elseif self.on_ground then
        self.jumptime = 0
    else
        self.jumptime = self.max_jumptime
    end

    -- Passive adjustments
    if math.abs(self.velocity.x) > self.max_speed then
        self.velocity.x = util.sign(self.velocity.x) * self.max_speed
    elseif math.abs(self.velocity.x) < self.min_speed then
        self.velocity.x = 0
    end

    -- Gravity
    self.velocity = self.velocity + gravity * dt
    self.velocity.y = math.min(self.velocity.y, terminal_velocity)

    -- Velocity-based state tracking
    -- TODO _prevx?
    self.on_ground = false
    -- Note that this has to be done /before/ collision -- if the player tries
    -- to walk left and immediately bumps into something and is stopped, the
    -- sprite should still face left
    if self.velocity.x ~= 0 then
        self.facing_left = self.velocity.x < 0
    end

    -- Calculate the desired movement, always trying to move us such that we
    -- end up on the edge of a pixel.  Round away from zero, to avoid goofy
    -- problems (like not recognizing the ground) when we end up moving less
    -- than requested; this may make us move faster than the physics constants
    -- would otherwise intend, but, oh well?
    local naive_movement = self.velocity * dt
    local goalpos = self.pos + naive_movement
    goalpos.x = self.velocity.x < 0 and math.floor(goalpos.x) or math.ceil(goalpos.x)
    goalpos.y = self.velocity.y < 0 and math.floor(goalpos.y) or math.ceil(goalpos.y)
    --goalpos.y = math.floor(goalpos.y + 0.5)
    local movement = goalpos - self.pos

    ----------------------------------------------------------------------------
    -- Collision time!
    --print()
    --[[
    self.pos = Vector(282.57071216542, 256.67301583553)
    self.shape:move(self.pos.x - self.shape.x0, self.pos.y - self.shape.y0)
    movement = Vector(4.5186891533476, 5.1286257491438)
    ]]

    -- First things first: restrict movement to within the current map
    -- TODO ARGH, worldscene is a global!
    do
        local l, t, r, b = self.shape:bbox()
        local ml, mt, mr, mb = 0, 0, worldscene.map.width, worldscene.map.height
        movement.x = util.clamp(movement.x, ml - l, mr - r)
        movement.y = util.clamp(movement.y, mt - t, mb - b)
    end

    local movement0 = movement:clone()
    local attempted = movement
    local movement, hits, last_slide = worldscene.collider:slide(self.shape, movement:unpack())
    self.last_slide = last_slide

    -- Trim velocity as necessary, based on the last surface we slid against
    print("velocity is:", self.velocity)
    local v = last_slide and self.velocity:projectOn(last_slide) or self.velocity
    print("and now it's", v)
    self.velocity = v
    if movement * gravity < movement0 * gravity then
        self.on_ground = true
    end

    self.pos = self.pos + movement
    self.shape:move_to(self.pos:unpack())

    -- Update pose depending on movement
    local pose
    if self.velocity.x == 0 then
        pose = 'stand'
    else
        pose = 'walk'
    end
    if self.facing_left then
        pose = pose .. '/left'
    else
        pose = pose .. '/right'
    end
    -- TODO hmm, seems a slight shame to call update() when the new pose might clobber that anyway; maybe combine these methods?
    self.sprite:update(dt)
    self.sprite:set_pose(pose)
end

function PlayerActor:draw()
    self.sprite:draw_at(self.pos)
    love.graphics.setColor(255, 0, 0, 128)
    self.shape:draw('fill')
    love.graphics.setColor(255, 255, 255)
end


return PlayerActor
