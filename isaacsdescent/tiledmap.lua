--[[
Read a map in Tiled's JSON format.
]]

local HC_shapes = require 'vendor.HC.shapes'
local Class = require 'vendor.hump.class'
local json = require 'vendor.dkjson'

local util = require 'isaacsdescent.util'

local function HC_new_rectangle(x, y, w, h)
    return HC_shapes.newPolygonShape(x,y, x+w,y, x+w,y+h, x,y+h)
end


-- I hate silent errors
local function strict_json_decode(str)
    local obj, pos, err = json.decode(str)
    if err then
        error(err)
    else
        return obj
    end
end


local TiledMap = Class{}

function TiledMap:init(path, imageloader)
    self.tiled = strict_json_decode(love.filesystem.read(path))
    self.tiles = {}
    for _, tileset in pairs(self.tiled.tilesets) do
        -- TODO load the image
        local tw, th, cols = tileset.tilewidth, tileset.tileheight, tileset.columns
        -- TODO should probably get these from the image instead
        local iw, ih = tileset.imagewidth, tileset.imageheight

        -- TODO spacing, margin
        local firstgid = tileset.firstgid
        for relid = 0, tileset.tilecount - 1 do
            local row, col = util.divmod(relid, cols)
            self.tiles[firstgid + relid] = {
                tilestuff = tileset.tiles["" .. relid],
                quad = love.graphics.newQuad(
                    col * tw, row * th, tw, th,
                    iw, ih),
            }
        end
    end
end

function TiledMap:add_to_collider(collider)
    -- TODO injecting like this seems...  wrong?  also keeping references to
    -- the collision shapes /here/?  this object should be a dumb wrapper and
    -- not have any state i think
    self.shapes = {}
    for _, layer in pairs(self.tiled.layers) do
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
            local tile = self.tiles[gid]
            if tile and tile.tilestuff then
                local tilestuff = tile.tilestuff
                -- TODO extremely hokey
                local coll = tilestuff.objectgroup.objects[1]
                if coll then
                    local ty, tx = util.divmod(t, width)
                    local ax, ay = x + tx, y + ty
                    local shape = HC_new_rectangle(
                        ax * self.tiled.tilewidth + coll.x,
                        ay * self.tiled.tileheight + coll.y,
                        coll.width,
                        coll.height)
                    self.shapes[ay * self.tiled.width + ax] = shape
                    collider:register(shape)
                end
            end
        end
    end
end

-- Draw a 
function TiledMap:draw(origin)
    -- TODO origin unused.  is it in tiles or pixels?
    local tw, th = self.tiled.tilewidth, self.tiled.tileheight
    for _, layer in pairs(self.tiled.layers) do
        local x, y = layer.x, layer.y
        local width, height = layer.width, layer.height
        local data = layer.data
        for t = 0, width * height - 1 do
            local gid = data[t + 1]
            if gid ~= 0 then
                local dy, dx = util.divmod(t, width)
                love.graphics.draw(
                    p8_spritesheet, self.tiles[gid].quad,
                    -- convert tile offsets to pixels
                    -- TODO scale?  love's pixel scale?
                    (x + dx) * tw, (y + dy) * th,
                    0, 1, 1)
            end
        end
    end
end

return TiledMap
