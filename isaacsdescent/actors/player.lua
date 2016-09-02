local Class = require 'vendor.hump.class'
local Vector = require 'vendor.hump.vector'

local util = require 'isaacsdescent.util'

-- TODO copy/pasted from tiledmap, ugh
local HC_shapes = require 'vendor.HC.shapes'
local function HC_new_rectangle(x, y, w, h)
    return HC_shapes.newPolygonShape(x,y, x+w,y, x+w,y+h, x,y+h)
end


-- TODO convert these to native units once you're confident these are the same
local TILE_SIZE = 32
local PICO8V = TILE_SIZE / (1/30)
local PICO8A = TILE_SIZE / (1/30) / (1/30)
local PlayerActor = Class{
    -- TODO consider splitting me into components
    -- TODO separate code from twiddles
    pos = nil,
    velocity = nil,
    shape = HC_new_rectangle(0, 0, 32, 64),

    -- Visuals (should maybe be wrapped in another object?)
    sprite = 'isaac_stand',
    facing_left = false,

    -- Passive physics parameters
    -- Units are pixels and seconds!
    min_speed = 1/64 * PICO8V,
    max_speed = 1/4 * PICO8V,
    -- TODO this is kind of hard to convert from pico-8 units to seconds; this is in frames, which i assume are 60 fps
    friction = math.sqrt(0.625),

    -- Active physics parameters
    xaccel = 0.125 * PICO8A,
    max_jumptime = 4 / 30,
    -- determined experimentally
    -- to make max jump 2 tiles
    yaccel = 7/64 * PICO8A,
    -- multiplied by xaccel while
    -- airborne
    aircontrol = 0.5,

    -- Physics state
    on_ground = false,
}
local gravity = 1/32 * PICO8A
local terminal_velocity = 7/8 * PICO8V

function PlayerActor:init(position)
    self.pos = position
    self.velocity = Vector(0, 0)

    local center = Vector(self.shape:center())
    self.shape:moveTo((self.pos + center):unpack())
end

function PlayerActor:update(dt)
    local xmult = 1
    if not self.on_ground then
        xmult = self.aircontrol
    end

    -- Explicit movement
    -- TODO should be whichever was pressed last?
    if love.keyboard.isDown('right') then
        self.velocity.x = self.velocity.x + self.xaccel * xmult * dt
    elseif love.keyboard.isDown('left') then
        self.velocity.x = self.velocity.x - self.xaccel * xmult * dt
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
    local friction = self.friction
    if not self.on_ground then
        -- Compute air friction
        friction = 1 - (1 - friction) / 2
    end
    -- TODO i don't like that this friction is independent of time, but it's /exponential/, what can i do about that
    self.velocity.x = self.velocity.x * friction
    if math.abs(self.velocity.x) > self.max_speed then
        self.velocity.x = util.sign(self.velocity.x) * self.max_speed
    elseif math.abs(self.velocity.x) < self.min_speed then
        self.velocity.x = 0
    end

    -- Gravity
    self.velocity.y = math.min(self.velocity.y + gravity * dt, terminal_velocity)

    -- Velocity-based state tracking
    -- TODO _prevx?
    self.on_ground = false
    if self.velocity.x ~= 0 then
        self.facing_left = self.velocity.x < 0
    end

    local movement = self.velocity * dt

    -- TODO round to a tile?  to a pixel?  to half a pixel?

    -- Collision time!
    local movement0 = movement:clone()
    self.shape:move(movement:unpack())

    -- TODO !!!
    local collisions = worldscene.collider:collisions(self.shape)
    -- TODO this could use some comments?
    -- TODO maybe rename 'delta' to, like, pushback
    local separation = Vector(0, 0)
    local shapes = {}
    local shape_centers = {}
    local shape_deltas = {}
    local shape_delta_lens = {}
    local shape_distances = {}
    local center = Vector(self.shape:center())
    for shape, delta in pairs(collisions) do
        delta = Vector(unpack(delta))
        shape_deltas[shape] = delta
        shape_delta_lens[shape] = delta:len2()
        local shape_center = Vector(shape:center())
        shape_centers[shape] = shape_center
        shape_distances[shape] = center:dist2(shape_center)
        table.insert(shapes, shape)
    end
    table.sort(shapes, function(a, b)
        if shape_distances[a] == shape_distances[b] then
            if shape_delta_lens[a] == shape_delta_lens[b] then
                return shape_deltas[a].x < shape_deltas[b].x
            else
                return shape_delta_lens[a] < shape_delta_lens[b]
            end
        else
            return shape_distances[a] < shape_distances[b]
        end
    end)

    for _, shape in ipairs(shapes) do
        local delta = shape_deltas[shape]
        local still_collides, dx, dy = self.shape:collidesWith(shape)
        if still_collides then
            movement.x = movement.x + dx
            movement.y = movement.y + dy
            self.shape:move(dx, dy)
        end
    end
    if movement.x * util.sign(movement0.x) < math.abs(movement0.x) then
        self.velocity.x = 0
    end
    if movement.y * util.sign(movement0.y) < math.abs(movement0.y) then
        self.velocity.y = 0
    end
    if movement.y < movement0.y then
        self.on_ground = true
    end

    self.pos = self.pos + movement
end

function PlayerActor:draw()
    game.sprites[self.sprite]:draw_at(self.pos, 0, self.facing_left)
end


return PlayerActor
