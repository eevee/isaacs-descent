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
    -- TODO are these part of the sprite?
    shape = whammo_shapes.Box(8, 16, 20, 48),
    anchor = Vector(16, 64),

    -- Visuals (should maybe be wrapped in another object?)
    sprite_name = 'isaac',
    facing_left = false,

    -- Passive physics parameters
    -- Units are pixels and seconds!
    min_speed = 1/256 * PICO8V,
    max_speed = 1/4 * PICO8V,
    friction = 1/16 * PICO8A,  -- not actually from pico8
    ground_friction = 1,
    max_slope = Vector(1, 1),

    -- Active physics parameters
    xaccel = 0.125 * PICO8A,
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
    self.velocity = Vector.zero:clone()

    -- TODO arrgh, this global.  sometimes i just need access to the game.
    -- should this be done on enter, maybe?
    -- TODO shouldn't the anchor really be part of the sprite?  hm, but then
    -- how would our bouncing box change?
    self.sprite = game.sprites[self.sprite_name]:instantiate()

    -- TODO christ
    self.initial_shape_offset = Vector(self.shape.x0, self.shape.y0)
    self.shape:move_to((position - self.anchor + self.initial_shape_offset):unpack())
end

function PlayerActor:update(dt)
    local xmult
    if self.on_ground then
        -- TODO adjust this factor when on a slope, so ascending is harder than
        -- descending?  maybe even affect max_speed going uphill?
        xmult = self.ground_friction
    else
        xmult = self.aircontrol
    end
    --print()
    --print()
    --print("position", self.pos, "velocity", self.velocity)

    -- Explicit movement
    -- TODO should be whichever was pressed last?
    local pose = 'stand'
    if love.keyboard.isDown('right') then
        self.velocity.x = self.velocity.x + self.xaccel * xmult * dt
        self.facing_left = false
        pose = 'walk'
    elseif love.keyboard.isDown('left') then
        self.velocity.x = self.velocity.x - self.xaccel * xmult * dt
        self.facing_left = true
        pose = 'walk'
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
            self.on_ground = false
        end
    elseif self.on_ground then
        self.jumptime = 0
    else
        self.jumptime = self.max_jumptime
    end

    -- Update pose depending on movement
    -- TODO how do these work for things that aren't players?
    if self.facing_left then
        pose = pose .. '/left'
    else
        pose = pose .. '/right'
    end
    -- TODO hmm, seems a slight shame to call update() when the new pose might clobber that anyway; maybe combine these methods?
    self.sprite:update(dt)
    self.sprite:set_pose(pose)

    -- Passive adjustments
    if math.abs(self.velocity.x) > self.max_speed then
        self.velocity.x = util.sign(self.velocity.x) * self.max_speed
    elseif math.abs(self.velocity.x) < self.min_speed then
        self.velocity.x = 0
    end

    -- Friction -- the general tendency for everything to decelerate.
    -- It always pushes against the direction of motion, but never so much that
    -- it would reverse the motion.  Note that taking the dot product with the
    -- horizontal produces the normal force.
    -- Include the dt factor from the beginning, to make capping easier.
    -- Also, doing this before anything else ensures that it only considers
    -- deliberate movement and momentum, not gravity.
    local vellen = self.velocity:len()
    if vellen > 1e-8 then
        local vel1 = self.velocity / vellen
        local friction_vector = Vector(self.friction, 0)
        local deceleration = friction_vector * vel1 * dt
        local decel_vector = -deceleration * friction_vector:normalized()
        decel_vector:trimInplace(vellen)
        self.velocity = self.velocity + decel_vector
        --print("velocity after deceleration:", self.velocity)
    end

    -- TODO factor the ground_friction constant into both of these
    -- Slope resistance -- an actor's ability to stay in place on an incline
    -- It always pushes upwards along the slope.  It has no cap, since it
    -- should always exactly oppose gravity, as long as the slope is shallow
    -- enough.
    -- Skip it entirely if we're not even moving in the general direction
    -- of gravity, though, so it doesn't interfere with jumping.
    if self.on_ground and self.last_slide then
        --print("last slide:", self.last_slide)
        local slide1 = self.last_slide:normalized()
        if gravity * self.max_slope:normalized() - gravity * slide1 > -1e-8 then
            local slope_resistance = -(gravity * slide1)
            self.velocity = self.velocity + slope_resistance * dt * slide1
            --print("velocity after slope resistance:", self.velocity)
        end
    end

    -- Gravity
    self.velocity = self.velocity + gravity * dt
    self.velocity.y = math.min(self.velocity.y, terminal_velocity)
    --print("velocity after gravity:", self.velocity)

    -- Calculate the desired movement, always trying to move us such that we
    -- end up on the edge of a pixel.  Round away from zero, to avoid goofy
    -- problems (like not recognizing the ground) when we end up moving less
    -- than requested; this may make us move faster than the physics constants
    -- would otherwise intend, but, oh well?
    local naive_movement = self.velocity * dt
    local goalpos = self.pos + naive_movement
    goalpos.x = self.velocity.x < 0 and math.floor(goalpos.x) or math.ceil(goalpos.x)
    goalpos.y = self.velocity.y < 0 and math.floor(goalpos.y) or math.ceil(goalpos.y)
    local movement = goalpos - self.pos

    ----------------------------------------------------------------------------
    -- Collision time!
    if love.keyboard.isDown('s') then
        self.pos = Vector(416.5,448.5)
        self.shape:move(self.pos.x - self.shape.x0, self.pos.y - self.shape.y0)
        self.velocity = Vector(-160.89588755785371177,-95.287752296280814335)
        movement = Vector(-3.5,-2.5)
    end
    --print("Collision time!  position", self.pos, "velocity", self.velocity, "movement", movement)

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
    local movement, hits, last_clock = worldscene.collider:slide(self.shape, movement:unpack())

    -- Trim velocity as necessary, based on the last surface we slid against
    --print("velocity is", self.velocity, "and clock is", last_clock)
    if last_clock and self.velocity ~= Vector.zero then
        local axis = last_clock:closest_extreme(self.velocity)
        if not axis then
            -- TODO stop?  once i fix the empty thing
        elseif self.velocity * axis < 0 then
            -- Nearest axis points away from our movement, so we have to stop
            self.velocity = Vector.zero:clone()
        else
        --print("axis", axis, "dot product", self.velocity * axis)
            -- Nearest axis is within a quarter-turn, so slide that direction
            self.velocity = self.velocity:projectOn(axis)
        end
    end
    --print("and now it's", self.velocity)
    --print("movement", movement, "movement0", movement0)

    -- Ground test: from where we are, are we allowed to move straight down?
    -- TODO pretty sure this won't work if the slope points the other way
    -- TODO i really want to replace clocks with just normals
    if last_clock then
        self.last_slide = last_clock:closest_extreme(gravity)
    else
        self.last_slide = nil
    end
    local blocked_clock = last_clock:inverted()
    self.on_ground = blocked_clock:includes(self.max_slope)

    self.pos = self.pos + movement
    --print("FINAL POSITION:", self.pos)
    self.shape:move_to((self.pos - self.anchor + self.initial_shape_offset):unpack())
end

function PlayerActor:draw()
    self.sprite:draw_at(self.pos - self.anchor)
    do return end
    if self.on_ground then
        love.graphics.setColor(255, 0, 0, 128)
    else
        love.graphics.setColor(0, 192, 0, 128)
    end
    self.shape:draw('fill')
    love.graphics.setColor(255, 255, 255)
end


return PlayerActor
