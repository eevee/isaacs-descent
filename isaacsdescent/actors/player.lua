local Class = require 'vendor.hump.class'
local Vector = require 'vendor.hump.vector'

local actors_base = require 'isaacsdescent.actors.base'
local actors_misc = require 'isaacsdescent.actors.misc'
local util = require 'isaacsdescent.util'
local whammo_shapes = require 'isaacsdescent.whammo.shapes'


local Player = Class{
    __includes = actors_base.MobileActor,

    shape = whammo_shapes.Box(8, 16, 20, 48),
    anchor = Vector(16, 64),
    sprite_name = 'isaac',

    is_player = true,
}

function Player:init(...)
    actors_base.MobileActor.init(self, ...)

    -- TODO not sure how i feel about having player state attached to the
    -- actor, but it /does/ make sense, and it's certainly an improvement over
    -- a global
    -- TODO BUT either way, this needs to be initialized at the start of the
    -- game and correctly restored on map load
    self.inventory = {}
    table.insert(self.inventory, {
        -- TODO i feel like this should be a real type, or perhaps attached to
        -- an actor somehow, but i don't want you to have real actual actors in
        -- your inventory.  i suppose you could just have a count of actor
        -- /types/, which i think is how zdoom works?
        -- TODO sprite = ...
        on_inventory_use = function(self, activator)
            if activator.savepoint then
                -- TODO seems like a good place to use :die()
                worldscene:remove_actor(activator.savepoint)
                activator.savepoint = nil
            end

            local savepoint = actors_misc.Savepoint(
                -- TODO this constant is /totally/ arbitrary, hmm
                activator.pos + Vector(0, -16))
            worldscene:add_actor(savepoint)
            activator.savepoint = savepoint
        end,
    })

end

function Player:update(dt)
    if self.is_dead then
        -- TODO buuut still gotta update the sprite...
        return
    end

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
            pose = 'jump'
        end
    elseif self.on_ground then
        self.jumptime = 0
    else
        self.jumptime = self.max_jumptime
    end

    -- Update pose depending on movement
    if self.velocity.y < 0 then
        pose = 'jump'
    elseif self.velocity.y > 0 then
        pose = 'fall'
    end
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

    -- Apply other actions
    -- TODO is there a compelling reason i'm doing this after movement, rather
    -- than before?
    -- TODO this is, ah, clumsy.  perhaps i should use the keypressed hook after all.
    -- TODO also it triggers on reload lol.
    local is_e_pressed = love.keyboard.isDown('e')
    local is_e_tapped = is_e_pressed and not self.was_e_pressed
    self.was_e_pressed = is_e_pressed
    if is_e_tapped then
        -- TODO this seems like the sort of thing that should, maybe, be
        -- scheduled as an event so it runs at a consistent time and isn't part
        -- of the update loop?  is there any good reason for that?
        if self.touching_mechanism then
            self.touching_mechanism:on_use(self)
        else
            -- TODO need to track currently-selected inventory item
            self.inventory[1]:on_inventory_use(self)
        end
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

local Gamestate = require 'vendor.hump.gamestate'
local DeadScene = require 'isaacsdescent.scenes.dead'
-- TODO should other things also be able to die?
function Player:die()
    if not self.is_dead then
        self.is_dead = true
        -- TODO LOL THIS WILL NOT FLY but the problem with putting a check in
        -- WorldScene is that it will then explode.  so maybe this should fire an
        -- event?  hump has an events thing, right?  or, maybe knife, maybe let's
        -- switch to knife...
        -- TODO oh, it gets better: switch gamestate during an update means draw
        -- doesn't run this cycle, so you get a single black frame
        Gamestate.switch(DeadScene(Gamestate.current()))
    end
end

function Player:resurrect()
    if self.is_dead then
        self.is_dead = false
    end
end


return Player
