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
    min_speed = 1/256 * PICO8V,
    max_speed = 1/4 * PICO8V,
    -- TODO this is kind of hard to convert from pico-8 units to seconds; this is in frames, which i assume are 60 fps
    --friction = math.sqrt(0.625),
    --friction = 1/16 * PICO8A,
    ground_friction = 1,
    friction = 1,
    max_slope = Vector(1, 1),

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
    self.velocity = Vector.zero:clone()

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
    dt = 1/60
    local xmult
    if self.on_ground then
        xmult = self.ground_friction
    else
        xmult = self.aircontrol
    end
    --print()
    --print()
    --print("position", self.pos, "velocity", self.velocity)
    local vel0 = self.velocity:clone()

    -- Explicit movement
    -- TODO should be whichever was pressed last?
    if love.keyboard.isDown('right') then
        self.velocity.x = self.velocity.x + self.xaccel * xmult * dt
        self.facing_left = false
    elseif love.keyboard.isDown('left') then
        self.velocity.x = self.velocity.x - self.xaccel * xmult * dt
        self.facing_left = true
    elseif self.on_ground then
        -- Decelerate when not holding a key
        -- TODO this still doesn't /quite/ work with slopes because it doesn't
        -- counteract gravity
        local decel = Vector(self.xdecel, 0)
        local dot = decel * self.velocity
        if dot > 0 then
            decel = -decel
        end
        if dot ~= 0 then
            decel = decel:projectOn(self.velocity)
            --print("decelerating by", decel, decel * dt)
            self.velocity = self.velocity + decel * dt * xmult
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

    -- Slope friction
    -- This is different from regular friction, which is about slowing down when not holding a movement key.  Slope friction is your ability to hold yourself still on a slope...
    if self.last_slide and self.on_ground then
        -- TODO only apply if the slope is <= 45
        local slide1 = self.last_slide:normalized()
        --print("slide:", slide1)
        local fric = gravity * slide1
        local friction = -fric * slide1
        --print("velocity before friction:", self.velocity, "magnitude:", self.velocity:len())
        --print("gravity:", gravity)
        --print("friction:", friction, "magnitude:", fric, "/", fric * dt)
        local new_velocity = self.velocity + friction * dt
        --print("new velocity:", new_velocity)
        if new_velocity * self.velocity <= 0 then
            self.velocity = Vector.zero:clone()
        else
            self.velocity = new_velocity
        end
        --print("velocity after friction:", self.velocity)
    end

    --print("total velocity change:", self.velocity - vel0)

    -- Velocity-based state tracking
    -- TODO _prevx?
    self.on_ground = false

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
    -- TODO early return if movement is zero
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
        self.last_slide = axis
    end
    --print("and now it's", self.velocity)
    --print("movement", movement, "movement0", movement0)
    -- Ground test: from where we are, are we allowed to move straight down?
    if not last_clock:includes(gravity) then
        self.on_ground = true
    end

    self.pos = self.pos + movement
    --print("FINAL POSITION:", self.pos)
    self.shape:move_to(self.pos:unpack())

    -- Update pose depending on movement
    -- TODO how do these work for things that aren't players?
    local pose
    -- TODO this is slightly glitchy, has us "walking" on slopes even when still
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
    if self.on_ground then
        love.graphics.setColor(255, 0, 0, 128)
    else
        love.graphics.setColor(0, 192, 0, 128)
    end
    self.shape:draw('fill')
    love.graphics.setColor(255, 255, 255)
end


return PlayerActor
