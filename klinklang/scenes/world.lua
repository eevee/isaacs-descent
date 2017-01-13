local flux = require 'vendor.flux'
local Gamestate = require 'vendor.hump.gamestate'
local Vector = require 'vendor.hump.vector'

local actors_base = require 'klinklang.actors.base'
local Player = require 'klinklang.actors.player'
local BaseScene = require 'klinklang.scenes.base'
local PauseScene = require 'klinklang.scenes.pause'
local whammo = require 'klinklang.whammo'

local tiledmap = require 'klinklang.tiledmap'

local CAMERA_MARGIN = 0.4

-- FIXME game-specific...  but maybe it doesn't need to be
local TriggerZone = require 'klinklang.actors.trigger'

local WorldScene = BaseScene:extend{
    __tostring = function(self) return "worldscene" end,

    music = nil,
    fluct = nil,

    was_left_down = false,
    was_right_down = false,
}

--------------------------------------------------------------------------------
-- hump.gamestate hooks

function WorldScene:init(...)
    BaseScene.init(self, ...)

    self.camera = Vector()
    self:_refresh_canvas()
end

function WorldScene:_refresh_canvas()
    local w, h = game:getDimensions()
    self.canvas = love.graphics.newCanvas(w, h)
end

function WorldScene:update(dt)
    -- Handle movement input.
    -- Input comes in two flavors: "instant" actions that happen once when a
    -- button is pressed, and "continuous" actions that happen as long as a
    -- button is held down.
    -- "Instant" actions need to be handled in keypressed, but "continuous"
    -- actions need to be handled with an explicit per-frame check.  The
    -- difference is that a press might happen in another scene (e.g. when the
    -- game is paused), which for instant actions should be ignored, but for
    -- continuous actions should start happening as soon as we regain control —
    -- even though we never know a physical press happened.
    -- Walking has the additional wrinkle that there are two distinct inputs.
    -- If both are held down, then we want to obey whichever was held more
    -- recently, which means we also need to track whether they were held down
    -- last frame.
    local is_left_down = love.keyboard.isScancodeDown('left')
    local is_right_down = love.keyboard.isScancodeDown('right')
    if is_left_down and is_right_down then
        if self.was_left_down and self.was_right_down then
            -- Continuing to hold both keys; do nothing
        elseif self.was_left_down then
            -- Was holding left, also pressed right, so move right
            self.player:decide_walk(1)
        elseif self.was_right_down then
            -- Was holding right, also pressed left, so move left
            self.player:decide_walk(-1)
        else
            -- Miraculously went from holding neither to holding both, so let's
            -- not move at all
            self.player:decide_walk(0)
        end
    elseif is_left_down then
        self.player:decide_walk(-1)
    elseif is_right_down then
        self.player:decide_walk(1)
    else
        self.player:decide_walk(0)
    end
    self.was_left_down = is_left_down
    self.was_right_down = is_right_down
    -- Jumping is slightly more subtle.  The initial jump is an instant action,
    -- but /continuing/ to jump is a continuous action.  So we handle the
    -- initial jump in keypressed, but abandon a jump here as soon as the key
    -- is no longer held.
    if not love.keyboard.isScancodeDown('space') then
        self.player:decide_abandon_jump()
    end

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

    self.fluct:update(dt)

    -- TODO i can't tell if this belongs here.  probably not, since it /should/
    -- do a fadeout.  maybe on the game object itself?
    if self.player and self.player.__EXIT then
        self.player.__EXIT = false
        game.map_index = game.map_index + 1
        local map = tiledmap.TiledMap("data/maps/" .. game.maps[game.map_index], game.resource_manager)
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
    -- FIXME if you resize the window, the camera can point outside of the
    -- map??  but that shouldn't be possible, we check against the map size,
    -- what
    -- FIXME would like some more interesting features here like smoothly
    -- catching up with the player, platform snapping?
    if self.player then
        local focus = self.player.pos
        local w, h = game:getDimensions()
        local mapx, mapy = 0, 0
        local marginx = CAMERA_MARGIN * w
        local marginy = CAMERA_MARGIN * h
        self.camera.x = math.floor(math.max(
            math.min(self.camera.x, math.max(mapx, math.floor(focus.x) - marginx)),
            math.min(self.map.width, math.floor(focus.x) + marginx) - w))
        --self.camera.y = math.floor(math.max(
        --    math.min(self.camera.y, math.max(mapy, math.floor(focus.y) - marginy)),
        --    math.min(self.map.height, math.floor(focus.y) + marginy) - h))
        -- FIXME hmm, finish this up probably, maybe stuff it in a type
        local y0 = marginy
        local y1 = h - marginy
        local miny = 0
        local maxy = self.map.height - h
        local newy = self.camera.y
        if focus.y - newy < y0 then
            newy = focus.y - y0
        elseif focus.y - newy > y1 then
            newy = focus.y - y1
        end
        newy = math.max(miny, math.min(maxy, newy))
        self.camera.y = math.floor(newy)
    end
end

function WorldScene:draw()
    local w, h = game:getDimensions()
    love.graphics.setCanvas(self.canvas)

    love.graphics.push('all')
    love.graphics.translate(-self.camera.x, -self.camera.y)

    -- TODO once the camera is set up, consider rigging the map to somehow
    -- auto-expand to fill the screen?
    -- FIXME don't really like hardcoding layer names here; they /have/ an
    -- order, the main problem is just that there's no way to specify where the
    -- actors should be drawn
    self.map:draw('background', self.camera, w, h)

    if self.pushed_actors then
        for _, actor in ipairs(self.pushed_actors) do
            actor:draw()
        end
    else
        for _, actor in ipairs(self.actors) do
            actor:draw()
        end
    end

    self.map:draw('objects', self.camera, w, h)
    self.map:draw('foreground', self.camera, w, h)
    self.map:draw('wiring', self.camera, w, h)

    if self.pushed_actors then
        love.graphics.setColor(0, 0, 0, 192)
        love.graphics.rectangle('fill', self.camera.x, self.camera.y, w, h)
        love.graphics.setColor(255, 255, 255)
        self.map:draw(self.submap, self.camera, w, h)
        for _, actor in ipairs(self.actors) do
            actor:draw()
        end
    end


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

    love.graphics.setCanvas()
    love.graphics.draw(self.canvas, 0, 0, 0, self.scale, self.scale)

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
    love.graphics.scale(game.scale, game.scale)

    local blockmap = self.collider.blockmap
    local blocksize = blockmap.blocksize
    local x0 = -self.camera.x % blocksize
    local y0 = -self.camera.y % blocksize
    local w, h = game:getDimensions()
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

function WorldScene:resize(w, h)
    self:_refresh_canvas()
end

-- FIXME this is really /all/ game-specific
function WorldScene:keypressed(key, scancode, isrepeat)
    if isrepeat then
        return
    end

    if scancode == 'space' then
        self.player:decide_jump()
    elseif key == 'q' then
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
        elseif self.player.inventory_cursor > 0 then
            self.player.inventory[self.player.inventory_cursor]:on_inventory_use(self.player)
        end
    elseif key == 'pause' then
        -- FIXME ignore if modifiers?
        Gamestate.push(PauseScene())
    end
end

--------------------------------------------------------------------------------
-- API

function WorldScene:load_map(map)
    self.collider = whammo.Collider(4 * map.tilewidth)
    self.map = map
    self.actors = {}
    self.fluct = flux.group()

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
    self:_create_actors()

    -- FIXME this is invasive
    -- FIXME should probably just pass the slightly-munged object right to the constructor, instead of special casing these
    -- FIXME could combine this with player start detection maybe
    for _, layer in pairs(map.raw.layers) do
        if layer.type == 'objectgroup' and layer.visible then
            for _, object in ipairs(layer.objects) do
                if object.type == 'trigger' then
                    self:add_actor(TriggerZone(
                        Vector(object.x, object.y),
                        Vector(object.width, object.height)))
                end
            end
        end
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

    self.camera = self.player.pos:clone()
end

function WorldScene:reload_map()
    self:load_map(self.map)
end

function WorldScene:_create_actors(submap)
    for _, template in ipairs(self.map.actor_templates) do
        if template.submap == submap then
            local class = actors_base.Actor._ALL_ACTOR_TYPES[template.name]
            if not class then
                error(("No such actor type %s"):format(template.name))
            end
            local position = template.position:clone()
            local actor = class(position)
            -- FIXME this feels...  hokey...
            if actor.sprite.anchor then
                actor:move_to(position + actor.sprite.anchor)
            end
            self:add_actor(actor)
        end
    end
end

function WorldScene:enter_submap(name)
    -- FIXME this is extremely half-baked
    self.submap = name
    self:remove_actor(self.player)
    self.pushed_actors = self.actors
    self.pushed_collider = self.collider
    self.actors = {}
    self.collider = whammo.Collider(4 * self.map.tilewidth)
    self.map:add_to_collider(self.collider, self.submap)
    self:add_actor(self.player)

    self:_create_actors(self.submap)

    -- FIXME this is also invasive
    for _, layer in pairs(map.raw.layers) do
        if layer.type == 'objectgroup' and layer.properties and layer.properties['submap'] == self.submap then
            for _, object in ipairs(layer.objects) do
                if object.type == 'trigger' then
                    self:add_actor(TriggerZone(
                        Vector(object.x, object.y),
                        Vector(object.width, object.height)))
                end
            end
        end
    end
end

function WorldScene:leave_submap(name)
    -- FIXME this is extremely half-baked
    self.submap = nil
    self:remove_actor(self.player)
    self.actors = self.pushed_actors
    self.collider = self.pushed_collider
    self.pushed_actors = nil
    self.pushed_collider = nil
    self:add_actor(self.player)
end

function WorldScene:add_actor(actor)
    table.insert(self.actors, actor)

    if actor.shape then
        -- TODO what happens if the shape changes?
        self.collider:add(actor.shape, actor)
    end

    actor:on_enter()
end

function WorldScene:remove_actor(actor)
    -- TODO what if the actor is the player...?  should we unset self.player?
    actor:on_leave()

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
