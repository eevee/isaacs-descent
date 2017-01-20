local Class = require 'vendor.hump.class'
local Vector = require 'vendor.hump.vector'

local actors_misc = require 'isaacsdescent.actors.misc'
local Player = require 'isaacsdescent.actors.player'
local BaseScene = require 'isaacsdescent.scenes.base'
local whammo = require 'isaacsdescent.whammo'

local TiledMap = require 'isaacsdescent.tiledmap'

local CAMERA_MARGIN = 6

-- TODO yeah this sucks
local actors_lookup = {
    spikes_up = actors_misc.SpikesUp,
    magical_bridge = actors_misc.MagicalBridge,
    wooden_switch = actors_misc.WoodenSwitch,
    laser_eye = actors_misc.LaserEye,
    ['tome of levitation'] = actors_misc.TomeOfLevitation,
}

local WorldScene = Class{
    __includes = BaseScene,
    __tostring = function(self) return "worldscene" end,
}

function WorldScene:init(map)
    BaseScene.init(self)

    self:load_map(map)
end

--------------------------------------------------------------------------------
-- hump.gamestate hooks

function WorldScene:update(dt)
    if love.keyboard.isDown(',') then
        local Gamestate = require 'vendor.hump.gamestate'
        Gamestate.switch(self)
    end
    if self.inventory_switch then
        self.inventory_switch.progress = self.inventory_switch.progress + dt * 3
        if self.inventory_switch.progress >= 2 then
            self.inventory_switch = nil
        end
    end

    -- TODO i can't tell if this belongs here.  probably not, since it /should/
    -- do a fadeout.  maybe on the game object itself?
    if self.player and self.player.__EXIT then
        self.player.__EXIT = false
        game.map_index = game.map_index + 1
        local map = TiledMap("data/maps/" .. game.maps[game.map_index], game.resource_manager)
        self:load_map(map)
    end

    for _, actor in ipairs(self.actors) do
        actor:update(dt)
    end

    self:update_camera()
end

function WorldScene:update_camera()
    -- Update camera position
    -- TODO i miss having a box type
    if self.player then
        local focus = self.player.pos
        local w, h = love.graphics.getDimensions()
        local mapx, mapy = 0, 0
        local margin = CAMERA_MARGIN * self.map.tilewidth
        self.camera.x = math.max(
            math.min(self.camera.x, math.max(mapx, math.floor(focus.x) - margin)),
            math.min(self.map.width, math.floor(focus.x) + margin) - w)
        self.camera.y = math.max(
            math.min(self.camera.y, math.max(mapy, math.floor(focus.y) - margin)),
            math.min(self.map.height, math.floor(focus.y) + margin) - h)
    end
end

function WorldScene:draw()
    love.graphics.push('all')
    love.graphics.translate(-self.camera.x, -self.camera.y)

    -- TODO once the camera is set up, consider rigging the map to somehow
    -- auto-expand to fill the screen?
    -- TODO don't really like hardcoding layer names here; maybe a prop
    self.map:draw('background', self.camera, love.graphics.getDimensions())

    for _, actor in ipairs(self.actors) do
        actor:draw(dt)
    end

    self.map:draw('objects', self.camera, love.graphics.getDimensions())
    self.map:draw('foreground', self.camera, love.graphics.getDimensions())

    if game.debug then
        --[[
        for shape in pairs(self.collider.shapes) do
            shape:draw('line')
        end
        ]]
        for _, actor in ipairs(self.actors) do
            if actor.shape then
                love.graphics.setColor(255, 255, 0, 192)
                actor.shape:draw('line')
            end
            love.graphics.setColor(255, 0, 0)
            love.graphics.circle('fill', actor.pos.x, actor.pos.y, 2)
            love.graphics.setColor(255, 255, 255)
            love.graphics.circle('line', actor.pos.x, actor.pos.y, 2)
        end

        if debug_hits then
            for hit, touchtype in pairs(debug_hits) do
                if touchtype > 0 then
                    -- Collision: red
                    love.graphics.setColor(255, 0, 0, 128)
                elseif touchtype < 0 then
                    -- Overlap: blue
                    love.graphics.setColor(0, 64, 255, 128)
                else
                    -- Touch: green
                    love.graphics.setColor(0, 192, 0, 128)
                end
                hit:draw('fill')
                --love.graphics.setColor(255, 255, 0)
                --local x, y = hit:bbox()
                --love.graphics.print(("%0.2f"):format(d), x, y)
            end
        end
    end

    love.graphics.pop()

    if game.debug then
        self:_draw_blockmap()
    end

    love.graphics.push('all')

    love.graphics.draw(p8_spritesheet, love.graphics.newQuad(192, 128, 64, 64, p8_spritesheet:getDimensions()), 0, 0)
    love.graphics.setScissor(16, 16, love.graphics.getWidth(), 32)
    local name = love.graphics.newText(m5x7, self.player.inventory[self.player.inventory_cursor].display_name)
    local dy = 32
    if self.inventory_switch then
        if self.inventory_switch.progress < 1 then
            dy = math.floor(self.inventory_switch.progress * 32)
            game.sprites[self.inventory_switch.old_item.sprite_name]:instantiate():draw_at(Vector(16, 16 - dy))
            love.graphics.draw(self.inventory_switch.new_name, 64, 32 - self.inventory_switch.new_name:getHeight() / 2 + 32 - dy)
        else
            love.graphics.setColor(255, 255, 255, (2 - self.inventory_switch.progress) * 255)
            love.graphics.draw(self.inventory_switch.new_name, 64, 32 - self.inventory_switch.new_name:getHeight() / 2)
            love.graphics.setColor(255, 255, 255)
        end
    end

    game.sprites[self.player.inventory[self.player.inventory_cursor].sprite_name]:instantiate():draw_at(Vector(16, 16 + 32 - dy))
    --love.graphics.setColor(128, 0, 0)
    --love.graphics.rectangle('fill', 64, 32 - name:getHeight() / 2, name:getWidth(), name:getHeight())
    --love.graphics.setColor(255, 255, 255)
    --love.graphics.draw(name, 64, 32 - name:getHeight() / 2)

    love.graphics.pop()
end

function WorldScene:_draw_blockmap()
    love.graphics.push('all')
    love.graphics.setColor(255, 255, 255, 64)

    local blockmap = self.collider.blockmap
    local blocksize = blockmap.blocksize
    local x0 = -self.camera.x % blocksize
    local y0 = -self.camera.y % blocksize
    local w, h = love.graphics.getDimensions()
    for x = x0, w, blocksize do
        love.graphics.line(x, 0, x, h)
    end
    for y = y0, h, blocksize do
        love.graphics.line(0, y, w, y)
    end

    for x = x0, w, blocksize do
        for y = y0, h, blocksize do
            local a, b = blockmap:to_block_units(self.camera.x + x, self.camera.y + y)
            love.graphics.print((" %d, %d"):format(a, b), x, y)
        end
    end

    love.graphics.pop()
end

function WorldScene:keypressed(key, scancode, isrepeat)
    if key == 'q' then
        -- Switch inventory items
        if not self.inventory_switch then
            local old_item = self.player.inventory[self.player.inventory_cursor]
            self.player.inventory_cursor = self.player.inventory_cursor + 1
            if self.player.inventory_cursor > #self.player.inventory then
                self.player.inventory_cursor = 1
            end
            self.inventory_switch = {
                old_item = old_item,
                new_name = love.graphics.newText(m5x7, self.player.inventory[self.player.inventory_cursor].display_name),
                progress = 0
            }
        end
    elseif key == 'e' then
        -- Use inventory item, or nearby thing
        -- FIXME this should be separate keys maybe?
        if self.player.touching_mechanism then
            self.player.touching_mechanism:on_use(self.player)
        else
            self.player.inventory[self.player.inventory_cursor]:on_inventory_use(self.player)
        end
    end
end

--------------------------------------------------------------------------------
-- API

function WorldScene:load_map(map)
    self.camera = Vector(0, 0)
    self.collider = whammo.Collider(4 * map.tilewidth)
    self.map = map
    self.actors = {}

    -- TODO this seems clearly wrong, especially since i don't clear the
    -- collider, but it happens to work (i think)
    map:add_to_collider(self.collider)

    local player_start = self.map.player_start
    -- FIXME fix all the maps and then make this fatal
    if not player_start then
        print("WARNING: no player start!!")
        player_start = Vector(1 * map.tilewidth, 5 * map.tileheight)
    end
    if not self.player then
        self.player = Player(player_start:clone())
    else
        self.player:move_to(player_start:clone())
    end

    -- TODO this seems more a candidate for an 'enter' or map-switch event
    for _, template in ipairs(map.actor_templates) do
        local class = actors_lookup[template.name]
        local position = template.position:clone()
        if class.anchor then
            position = position + class.anchor
        end
        self:add_actor(class(position))
    end

    -- FIXME putting the player last is really just a z hack to make the player
    -- draw in front of everything else
    self:add_actor(self.player)

    -- Rez the player if necessary.  This MUST happen after moving the player
    -- (and SHOULD happen after populating the world, anyway) because it does a
    -- zero-duration update, and if the player is still touching whatever
    -- killed them, they'll instantly die again.
    if self.player.is_dead then
        -- TODO should this be a more general 'reset'?
        self.player:resurrect()
    end
end

function WorldScene:reload_map()
    self:load_map(self.map)
end

function WorldScene:add_actor(actor)
    table.insert(self.actors, actor)

    if actor.shape then
        -- TODO what happens if the shape changes?
        self.collider:add(actor.shape, actor)
    end

    actor:on_spawn()
end

function WorldScene:remove_actor(actor)
    -- TODO what if the actor is the player...?  should we unset self.player?

    -- TODO maybe an index would be useful
    for i, an_actor in ipairs(self.actors) do
        if actor == an_actor then
            local last = #self.actors
            self.actors[i] = self.actors[last]
            self.actors[last] = nil
            break
        end
    end

    if actor.shape then
        self.collider:remove(actor.shape)
    end
end


return WorldScene
