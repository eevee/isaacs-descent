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
    local lastclock = util.ClockRange(util.ClockRange.ZERO, util.ClockRange.ZERO)  -- 
    local stuckcounter = 0

    while true do
        --print("--- STARTING ROUND")
        local hits = {}
        local hits2 = {}
        local anyhit = false
        local shortest_move_len2 = attempted:len2()
        local shortest_move = attempted
        local neighbors = self.blockmap:neighbors(shape, attempted:unpack())
        for neighbor in pairs(neighbors) do
            local move, clock = shape:slide_towards(neighbor, attempted)
            --print("< got move and clock:", move, clock)
            if move then
                anyhit = true
                local move_len2 = move:len2()
                if move_len2 <= shortest_move_len2 then
                    if move_len2 < shortest_move_len2 then
                        hits = {}
                        hits2 = {}
                    end
                    hits[neighbor] = clock
                    hits2[neighbor] = move_len2
                    shortest_move_len2 = move_len2
                    shortest_move = move
                end
            end
            --print("< shortest move is now:", shortest_move, "len2:", shortest_move_len2)
        end

        if not anyhit then
            break
        end
        -- Automatically break if we don't move for three iterations -- not
        -- moving once is okay because we might slide, but three indicates a
        -- bad loop somewhere
        -- TODO would be nice to avoid this entirely!  it happens, e.g., at the
        -- bottom of the slopetest ramp: position       (606.5,638.5)   velocity        (61.736288265774419415,121.03382860727833759)   movement        (1.5,2.5)
        if shortest_move_len2 == 0 then
            stuckcounter = stuckcounter + 1
            if stuckcounter >= 3 then
                --print("!!!  BREAKING OUT OF LOOP BECAUSE WE'RE STUCK, OOPS")
                attempted = Vector(0, 0)
                break
            end
        else
            stuckcounter = 0
        end

        local attempted_len2 = attempted:len2()
        for hit, move_len2 in pairs(hits2) do
            --print("logging hit...", move_len2, "<-", hit:bbox())
            if allhits[hit] == nil then
                allhits[hit] = (move_len2 < attempted_len2)
            end
        end

        --print("moving by", shortest_move)
        shape:move(shortest_move:unpack())
        successful = successful + shortest_move

        -- Intersect all the "clocks" (sets of allowable slide angles) we found
        local moveperp = attempted:perpendicular()
        local finalclock = util.ClockRange(util.ClockRange.ZERO, util.ClockRange.ZERO)
        for neighbor, clock in pairs(hits) do
            finalclock:intersect(clock)
            --print("clock:", clock, "dv:", hits2[neighbor], "neighbor:", neighbor:bbox())
        end
        -- Slide along the extreme that's closest to the direction of movement
        --print("finalclock:", finalclock)
        local slide = finalclock:closest_extreme(attempted)
        -- TODO wow this is bad naming
        -- TODO this can be an empty clock, which is really an entire clock
        if lastclock and shortest_move_len2 == 0 then
            lastclock:intersect(finalclock)
        else
            lastclock = finalclock
        end

        -- TODO slide might be nil
        if slide then
            local remaining = attempted - shortest_move
            attempted = remaining:projectOn(slide)
            --print("slide!  remaining", remaining, "-> attempted", attempted)
        else
            attempted = Vector(0, 0)
        end

        if attempted.x == 0 and attempted.y == 0 then
            break
        end
    end

    -- Whatever's left over is unopposed
    shape:move(attempted:unpack())
    debug_hits = allhits
    return successful + attempted, allhits, lastclock
end

return {
    Collider = Collider,
}
