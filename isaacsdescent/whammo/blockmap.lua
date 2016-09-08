--[[
A spatial hash.
]]

local Class = require 'vendor.hump.class'

local Blockmap = Class{}

function Blockmap:init(blocksize)
    self.blocksize = blocksize
    self.blocks = {}
    self.bboxes = setmetatable({}, {__mode = 'k'})
end

function Blockmap:to_block_units(x, y)
    return math.floor(x / self.blocksize), math.floor(y / self.blocksize)
end

function Blockmap:block(x, y)
    return self:raw_block(self:to_block_units(x, y))
end

function Blockmap:raw_block(a, b)
    local column = self.blocks[a]
    if not column then
        column = {}
        self.blocks[a] = column
    end
    
    local block = column[b]
    if not block then
        block = setmetatable({}, {__mode = 'k'})
        column[b] = block
    end

    return block
end

function Blockmap:add(obj)
    obj:remember_blockmap(self)
    local x0, y0, x1, y1 = obj:bbox()
    local a0, b0 = self:to_block_units(x0, y0)
    local a1, b1 = self:to_block_units(x1, y1)
    for a = a0, a1 do
        for b = b0, b1 do
            local block = self:raw_block(a, b)
            block[obj] = true
        end
    end
    self.bboxes[obj] = {x0, y0, x1, y1}
end

function Blockmap:remove(obj)
    obj:forget_blockmap(self)
    local x0, y0, x1, y1 = unpack(self.bboxes[obj])
    local a0, b0 = self:to_block_units(x0, y0)
    local a1, b1 = self:to_block_units(x1, y1)
    for a = a0, a1 do
        for b = b0, b1 do
            local block = self:raw_block(a, b)
            block[obj] = nil
        end
    end
    self.bboxes[obj] = nil
end

function Blockmap:update(obj)
    self:remove(obj)
    self:add(obj)
end

function Blockmap:neighbors(obj, dx, dy)
    local x0, y0, x1, y1 = obj:extended_bbox(dx, dy)

    local a0, b0 = self:to_block_units(x0, y0)
    local a1, b1 = self:to_block_units(x1, y1)
    local ret = {}
    for a = a0, a1 do
        for b = b0, b1 do
            -- Get the block manually, to avoid creating one if not necessary
            local column = self.blocks[a]
            local block
            if column then
                block = column[b]
            end
            if block then
                for neighbor in pairs(block) do
                    ret[neighbor] = true
                end
            end
        end
    end

    -- Objects do not neighbor themselves
    ret[obj] = nil

    return ret
end

return Blockmap
