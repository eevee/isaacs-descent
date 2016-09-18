local Class = require 'vendor.hump.class'
local Vector = require 'vendor.hump.vector'

local actors_base = require 'isaacsdescent.actors.base'
local util = require 'isaacsdescent.util'
local whammo_shapes = require 'isaacsdescent.whammo.shapes'


local Player = Class{
    __includes = actors_base.MobileActor,

    shape = whammo_shapes.Box(8, 16, 20, 48),
    anchor = Vector(16, 64),
    sprite_name = 'isaac',
}

function Player:update(dt)
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

    -- Run the base logic to perform movement and collision
    local hits = self:_do_physics(dt)

    self.touching_mechanism = nil
    for shape in pairs(hits) do
        local actor = worldscene.shape_to_actor[shape]
        if actor and actor.is_usable then
            self.touching_mechanism = actor
            break
        end
    end

    if self.touching_mechanism and love.keyboard.isDown('e') then
        -- TODO this seems like the sort of thing that should, maybe, be
        -- scheduled as an event so it runs at a consistent time and isn't part
        -- of the update loop?  is there any good reason for that?
        self.touching_mechanism:on_use(self)
    end
end

function Player:draw()
    actors_base.MobileActor.draw(self)

    if self.touching_mechanism then
        love.graphics.setColor(0, 64, 255, 128)
        self.touching_mechanism.shape:draw('fill')
        love.graphics.setColor(255, 255, 255)
    end
    do return end
    if self.on_ground then
        love.graphics.setColor(255, 0, 0, 128)
    else
        love.graphics.setColor(0, 192, 0, 128)
    end
    self.shape:draw('fill')
    love.graphics.setColor(255, 255, 255)
end


return Player
