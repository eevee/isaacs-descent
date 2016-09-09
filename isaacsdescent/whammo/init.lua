local Class = require 'vendor.hump.class'
local Vector = require 'vendor.hump.vector'
local vector_light = require 'vendor.hump.vector-light'

local util = require 'isaacsdescent.util'
local Blockmap = require 'isaacsdescent.whammo.blockmap'
local shapes = require 'isaacsdescent.whammo.shapes'

local Collider = Class{}

function Collider:init(blocksize)
    self.shapes = setmetatable({}, {__mode = 'k'})
    self.blockmap = Blockmap(blocksize)
end

function Collider:add(shape)
    self.blockmap:add(shape)
    self.shapes[shape] = true
end

function Collider:remove(shape)
    self.blockmap:remove(shape)
    self.shapes[shape] = nil
end


function Collider:slide(shape, dx, dy)
    local attempted = Vector(dx, dy)
    local successful = Vector(0, 0)
    local allhits = {}  -- set of objects we ultimately bump into
    local last_slide  -- last direction we slide, for friction
    local stuckcounter = 0

    while true do
        local hits = {}
        local anyhit = false
        local min_d = 1
        local neighbors = self.blockmap:neighbors(shape, attempted:unpack())
        for neighbor in pairs(neighbors) do
            local d, clock = shape:slide_towards(neighbor, attempted)
            if d then
                anyhit = true
                if d <= min_d then
                    if d < min_d then
                        hits = {}
                    end
                    min_d = d
                    hits[neighbor] = clock
                end
            end
        end

        if not anyhit then
            break
        end
        -- Automatically break if we don't move for three iterations -- not
        -- moving once is okay because we might slide, but three indicates a
        -- bad loop somewhere
        if min_d == 0 then
            stuckcounter = stuckcounter + 1
            if stuckcounter >= 3 then
                break
            end
        else
            stuckcounter = 0
        end

        local this_move = attempted * min_d
        shape:move(this_move:unpack())
        successful = successful + this_move

        -- Intersect all the "clocks" (sets of allowable slide angles) we found
        local moveperp = attempted:perpendicular()
        local finalclock = util.ClockRange(util.ClockRange.ZERO, util.ClockRange.ZERO)
        for neighbor, clock in pairs(hits) do
            finalclock:intersect(clock)
        end
        -- Then choose the extreme that's closest to the direction of movement
        -- (via the dot product) and slide along that
        local slide, dot
        for vec in pairs(finalclock:extremes()) do
            local vec1 = vec:normalized()
            local vecdot = vec1 * attempted
            if not slide then
                slide = vec1
                dot = vecdot
            elseif vecdot > dot then
                slide = vec1
                dot = vecdot
            end
        end
        last_slide = slide

        local remaining = attempted - this_move
        remaining = remaining:projectOn(slide)
        attempted = remaining

        for hit in pairs(hits) do
            allhits[hit] = true
        end

        if attempted.x == 0 and attempted.y == 0 then
            break
        end
    end

    -- Whatever's left over is unopposed
    shape:move(attempted:unpack())
    return successful + attempted, allhits, last_slide
end

return {
    Collider = Collider,
}
