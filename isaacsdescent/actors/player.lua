local Class = require 'vendor.hump.class'
local Vector = require 'vendor.hump.vector'

local actors_base = require 'isaacsdescent.actors.base'
local actors_misc = require 'isaacsdescent.actors.misc'
local util = require 'isaacsdescent.util'
local whammo_shapes = require 'isaacsdescent.whammo.shapes'


local Player = Class{
    __includes = actors_base.MobileActor,

    shape = whammo_shapes.Box(8, 16, 20, 46),
    anchor = Vector(19, 62),
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
            if activator.ptrs.savepoint then
                -- TODO seems like a good place to use :die()
                worldscene:remove_actor(activator.ptrs.savepoint)
                activator.ptrs.savepoint = nil
            end

            local savepoint = actors_misc.Savepoint(
                -- TODO this constant is /totally/ arbitrary, hmm
                activator.pos + Vector(0, -16))
            worldscene:add_actor(savepoint)
            activator.ptrs.savepoint = savepoint
        end,
    })

end

function Player:update(dt)
    if self.is_dead then
        -- TODO buuut still gotta update the sprite...
        self.sprite:update(dt)
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
    -- This uses the Sonic approach: pressing jump immediately sets (not
    -- increases!) the player's y velocity, and releasing jump lowers the y
    -- velocity to a threshold
    if love.keyboard.isDown('space') then
        if self.on_ground then
            if self.velocity.y > -self.jumpvel then
                self.velocity.y = -self.jumpvel
                self.on_ground = false
                game.resource_manager:get('assets/sounds/jump.ogg'):play()
            end
        end
    else
        if not self.on_ground then
            self.velocity.y = math.max(self.velocity.y, -self.jumpvel * self.jumpcap)
        end
    end

    -- Run the base logic to perform movement, collision, sprite updating, etc.
    actors_base.MobileActor.update(self, dt)

    -- Update pose depending on actual movement
    if self.on_ground then
    elseif self.velocity.y < 0 then
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
    self.sprite:set_pose(pose)

    -- TODO ugh, this whole block should probably be elsewhere; i need a way to
    -- check current touches anyway.  would be nice if it could hook into the
    -- physics system so i don't have to ask twice
    local hits = self._stupid_hits_hack
    self.touching_mechanism = nil
    for shape in pairs(hits) do
        local actor = worldscene.collider:get_owner(shape)
        if actor and actor.is_usable then
            self.touching_mechanism = actor
            break
        end
    end

    -- TODO this is stupid but i want a real exit door anyway
    -- TODO also it should fire an event or something
    local _, _, x1, _ = self.shape:bbox()
    if x1 >= worldscene.map.width then
        self.__EXIT = true
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

    do return end
    if self.touching_mechanism then
        love.graphics.setColor(0, 64, 255, 128)
        self.touching_mechanism.shape:draw('fill')
        love.graphics.setColor(255, 255, 255)
    end
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
        local pose = 'die'
        -- TODO ARGGGHH
        if self.facing_left then
            pose = pose .. '/left'
        else
            pose = pose .. '/right'
        end
        self.sprite:set_pose(pose)
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
        -- Reset physics
        self.velocity = Vector(0, 0)
        self.on_ground = false  -- TODO this one's always tricky
    end
end


return Player
