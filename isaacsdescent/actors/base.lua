local Class = require 'vendor.hump.class'
local Vector = require 'vendor.hump.vector'

local util = require 'isaacsdescent.util'
local whammo_shapes = require 'isaacsdescent.whammo.shapes'

-- Base class for an actor: any object in the world with any behavior at all.
-- (The world also contains tiles, but those are purely decorative; they don't
-- have an update call, and they're drawn all at once by the map rather than
-- drawing themselves.)
local Actor = Class{
    -- TODO consider splitting me into components

    -- Provided to constructor
    pos = nil,

    -- Should be provided in the class
    -- TODO are these part of the sprite?
    shape = nil,
    anchor = nil,
    -- Visuals (should maybe be wrapped in another object?)
    sprite_name = nil,
    -- TODO this doesn't even necessarily make sense...?
    facing_left = false,

    -- Indicates this is an object that responds to the use key
    is_usable = false,
}

function Actor:init(position)
    self.pos = position
    self.velocity = Vector.zero:clone()

    self.shape = self.shape:clone()
    -- TODO arrgh, this global.  sometimes i just need access to the game.
    -- should this be done on enter, maybe?
    -- TODO shouldn't the anchor really be part of the sprite?  hm, but then
    -- how would our bounding box change?
    self.sprite = game.sprites[self.sprite_name]:instantiate()

    -- TODO christ
    self.initial_shape_offset = Vector(self.shape.x0, self.shape.y0)
    self.shape:move_to((position - self.anchor + self.initial_shape_offset):unpack())
end

-- Called once per update frame; any state changes should go here
function Actor:update(dt)
    -- TODO this should update the sprite!!  but i don't know how to make that
    -- work with set_pose yet
end

-- Draw the actor
function Actor:draw()
    if self.sprite then
        self.sprite:draw_at(self.pos - self.anchor)
    end
end

-- Determines whether this actor blocks another one.  By default, actors are
-- non-blocking, and mobile actors are blocking
function Actor:blocks(actor, direction)
    return false
end

-- Called every frame that another actor is touching this one
-- TODO that seems excessive?
function Actor:on_collide(actor, direction)
end

-- General API stuff for controlling actors from outside

function Actor:move_to(position)
    self.pos = position
end


-- Base class for an actor that's subject to standard physics.  Generally
-- something that makes conscious decisions, like a player or monster
-- TODO not a fan of using subclassing for this; other options include
-- component-entity, or going the zdoom route and making everything have every
-- behavior but toggled on and off via myriad flags
-- TODO convert these to native units once you're confident these are the same
local TILE_SIZE = 32
local PICO8V = TILE_SIZE / (1/30)
local PICO8A = TILE_SIZE / (1/30) / (1/30)
local MobileActor = Class{
    __includes = Actor,

    -- TODO separate code from twiddles
    velocity = nil,

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

-- TODO these are a property of the world and should go on the world object
-- once one exists
local gravity = Vector(0, 1/16 * PICO8A)
local terminal_velocity = 7/8 * PICO8V

function MobileActor:_do_physics(dt)
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

    -- Tell everyone we've hit them
    -- TODO surely we should announce this in the order we hit!  all the more
    -- reason to hoist the loop out of whammo and into here
    for shape in pairs(hits) do
	local actor = worldscene.shape_to_actor[shape]
	if actor then
	    -- TODO should we also pass along the touchtype?
	    actor:on_collide(self, movement)
	end
    end

    return hits
end

function MobileActor:update(dt)
    -- TODO i don't think this is going to work, since the base class's
    -- update() eventually needs to be called to make sure we're updating the
    -- sprite too
    self:_do_physics(dt)
end

function MobileActor:blocks(actor, d)
    return true
end

function MobileActor:move_to(position)
    Actor.move_to(self, position)

    self.shape:move_to((self.pos - self.anchor + self.initial_shape_offset):unpack())
end


return {
    Actor = Actor,
    MobileActor = MobileActor,
}
