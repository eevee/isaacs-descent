local HC = require 'vendor.HC'
HC.shapes = require 'vendor.HC.shapes'

local json = require 'vendor.dkjson'

local function strict_json_decode(str)
    local obj, pos, err = json.decode(str)
    if err then
	error(err)
    else
	return obj
    end
end

local function sign(n)
    if n == math.abs(n) then
        return 1
    else
        return -1
    end
end

local function divmod(n, b)
    return math.floor(n / b), math.mod(n, b)
end

local function HC_new_rectangle(x, y, w, h)
    return HC.shapes.newPolygonShape(x,y, x+w,y, x+w,y+h, x,y+h)
end

-- TODO yeah ok this direly wants to be bundled up into its own thing, elsewhere
local p8_spritesheet
local map = {}
local function _mapload()
    map.tiled = strict_json_decode(love.filesystem.read("assets/maps/all-pico8.tiled.json"))
    map.tiles = {}
    for _, tileset in pairs(map.tiled.tilesets) do
	local tw, th, cols = tileset.tilewidth, tileset.tileheight, tileset.columns
	-- TODO should probably get these from the image instead
	local iw, ih = tileset.imagewidth, tileset.imageheight

	-- TODO spacing, margin
	local firstgid = tileset.firstgid
	for relid = 0, tileset.tilecount - 1 do
	    local row, col = divmod(relid, cols)
	    map.tiles[firstgid + relid] = {
                tilestuff = tileset.tiles["" .. relid],
		quad = love.graphics.newQuad(
		    col * tw, row * th, tw, th,
		    iw, ih),
	    }
	end
    end

    -- Set up collision world
    map.collider = HC.new(4 * map.tiled.tilewidth)
    map.shapes = {}
    for _, layer in pairs(map.tiled.layers) do
	local x, y = layer.x, layer.y
	local width, height = layer.width, layer.height
	local data = layer.data
	for t = 0, width * height - 1 do
	    local gid = data[t + 1]
            if gid == 34 then
                local r = love.math.random(86, 89)
                if r ~= 86 then
                    gid = r
                    data[t + 1] = gid
                end
            end
            local tile = map.tiles[gid]
            if tile and tile.tilestuff then
                local tilestuff = tile.tilestuff
                -- TODO extremely hokey
                local coll = tilestuff.objectgroup.objects[1]
                if coll then
                    local ty, tx = divmod(t, width)
                    local ax, ay = x + tx, y + ty
                    local shape = HC_new_rectangle(
                        ax * map.tiled.tilewidth + coll.x,
                        ay * map.tiled.tileheight + coll.y,
                        coll.width,
                        coll.height)
                    map.shapes[ay * map.tiled.width + ax] = shape
                    map.collider:register(shape)
                end
	    end
	end
    end
end

local function _mapdraw(origin)
    -- TODO origin unused.  is it in tiles or pixels?
    local tw, th = map.tiled.tilewidth, map.tiled.tileheight
    for _, layer in pairs(map.tiled.layers) do
	local x, y = layer.x, layer.y
	local width, height = layer.width, layer.height
	local data = layer.data
	for t = 0, width * height - 1 do
	    local gid = data[t + 1]
	    if gid ~= 0 then
		local dy, dx = divmod(t, width)
		love.graphics.draw(
		    p8_spritesheet, map.tiles[gid].quad,
		    -- convert tile offsets to pixels
		    -- TODO scale?  love's pixel scale?
		    (x + dx) * tw, (y + dy) * th,
		    0, 1, 1)
	    end
	end
    end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local Class = require 'vendor.hump.class'
local Vector = require 'vendor.hump.vector'


local game = {
    scale = 1,
    sprites = {},
    actors = {},
}

local TILE_SIZE = 32


--------------------------------------------------------------------------------
-- Sprite definitions

local SpriteFrame = Class{}

function SpriteFrame:init(spritesheet, region)
    self.spritesheet = spritesheet
    self.region = region
    self.quad = love.graphics.newQuad(
        self.region.l, self.region.t, self.region.w, self.region.h,
        spritesheet:getWidth(), spritesheet:getHeight())
end

function SpriteFrame:draw_at(point, dt, hflip)
    -- TODO take scale into account?  and factor in love's pixel scale while you're at it
    local x, y = point:unpack()
    local sx, sy = game.scale, game.scale
    if hflip then
        x = x + self.region.w
        sx = sx * -1
    end
    love.graphics.draw(self.spritesheet, self.quad, x, y, 0, sx, sy)
end


--------------------------------------------------------------------------------

local player_actor
function love.load(arg)
    love.graphics.setDefaultFilter('nearest', 'nearest', 1)
    -- TODO list all this declaratively and actually populate it in this function?
    p8_spritesheet = love.graphics.newImage('assets/images/spritesheet.png')
    game.sprites.isaac_stand = SpriteFrame(
        -- TODO need a better way to chop up spritesheet; probably exists already
        p8_spritesheet, { l = 32, t = 0, w = 32, h = 64})

    m5x7 = love.graphics.newFont('assets/fonts/m5x7.ttf', 48)

    _mapload()
    player_actor:_place()
end

function love.update(dt)
    for _, actor in ipairs(game.actors) do
        actor:update(dt)
    end
end

function love.draw(dt)
    _mapdraw(Vector(0, 0))

    for _, actor in ipairs(game.actors) do
        actor:draw(dt)
    end

    --tmp_draw_dialogue()
end

--------------------------------------------------------------------------------

-- TODO convert these to native units once you're confident these are the same
PICO8V = TILE_SIZE / (1/30)
PICO8A = TILE_SIZE / (1/30) / (1/30)
player_actor = {
    pos = Vector(1, 6) * TILE_SIZE,
    velocity = Vector(0, 0),
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
gravity = 1/32 * PICO8A
terminal_velocity = 7/8 * PICO8V

function player_actor:_place()
    local center = Vector(self.shape:center())
    self._shape_center = center
    self.shape:moveTo((self.pos + self._shape_center):unpack())
    map.collider:register(player_actor.shape)
end

function player_actor:update(dt)
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
        self.velocity.x = sign(self.velocity.x) * self.max_speed
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

    local collisions = map.collider:collisions(self.shape)
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
    if movement.x * sign(movement0.x) < math.abs(movement0.x) then
        self.velocity.x = 0
    end
    if movement.y * sign(movement0.y) < math.abs(movement0.y) then
        self.velocity.y = 0
    end
    if movement.y < movement0.y then
        self.on_ground = true
    end

    self.pos = self.pos + movement
end

function player_actor:draw()
    game.sprites[self.sprite]:draw_at(self.pos, 0, self.facing_left)
end

game.actors = {player_actor}

--------------------------------------------------------------------------------

function tmp_draw_dialogue()
    love.graphics.setColor(0, 0, 0, 128)
    love.graphics.rectangle('fill', 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    local l = 16
    local r = love.graphics.getWidth() - 16
    local b = love.graphics.getHeight() - 16
    local t = b - (160 - 32)
    love.graphics.setColor(10, 152, 172)
    love.graphics.rectangle('fill', l, t, r - l, b - t)
    love.graphics.setColor(13, 32, 48)
    love.graphics.rectangle('line', l, t, r - l, b - t)
    love.graphics.rectangle('line', l + 1, t + 1, r - l - 2, b - t - 2)
    love.graphics.setColor(0, 82, 128)
    love.graphics.rectangle('line', l + 8, t + 7, r - l - 16, b - t - 16)
    love.graphics.setColor(255, 255, 255)
    love.graphics.rectangle('line', l + 8, t + 8, r - l - 16, b - t - 16)

    local text = love.graphics.newText(m5x7, "Hullo.")
    love.graphics.setColor(0, 82, 128)
    love.graphics.draw(text, l + 20 - 2, t + 12 + 2)
    love.graphics.setColor(255, 255, 255)
    love.graphics.draw(text, l + 20, t + 12)

    local quad = love.graphics.newQuad(64, 416, 64, 96, p8_spritesheet:getWidth(), p8_spritesheet:getHeight())
    local scale = 4
    love.graphics.draw(p8_spritesheet, quad, l + 32 + 64 * scale, t - 96 * scale, 0, -scale, scale)
end
