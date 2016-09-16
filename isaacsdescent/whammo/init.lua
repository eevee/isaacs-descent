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
    local lastclock = util.ClockRange(util.ClockRange.ZERO, util.ClockRange.ZERO)
    local stuckcounter = 0

    -- TODO i wonder if this should just do a single move and leave the sliding
    -- and looping up to the caller?
    while true do
        --print("--- STARTING ROUND; ATTEMPTING TO MOVE", attempted)
        local collisions = {}
        local neighbors = self.blockmap:neighbors(shape, attempted:unpack())
        for neighbor in pairs(neighbors) do
            local move, touchtype, clock = shape:slide_towards(neighbor, attempted)
            --print("< got move, touchtype, clock:", move, touchtype, clock)
            if move then
                table.insert(collisions, {
                    shape = neighbor,
                    move = move,
                    touchtype = touchtype,
                    clock = clock,
                    len2 = move:len2(),
                })
            end
        end
        if #collisions == 0 then
            break
        end

        -- Look through the objects we'll hit, in the order we'll hit them, and
        -- stop at the first that blocks us
        table.sort(collisions, function(a, b)
            return a.len2 < b.len2
        end)
        local first_collision
        -- Intersection of all the "clocks" (sets of allowable slide angles) we find
        local combined_clock = util.ClockRange(util.ClockRange.ZERO, util.ClockRange.ZERO)
        for _, collision in ipairs(collisions) do
            --print("checking collision...", collision.move, collision.len2, "at", collision.shape:bbox())
            -- If we've already found something that blocks us, and this
            -- collision requires moving further, then stop here.  This allows
            -- for ties
            if first_collision and first_collision.len2 < collision.len2 then
                break
            end

            -- Log the first type of contact with each shape
            if allhits[collision.shape] == nil then
                allhits[collision.shape] = collision.touchtype
            end

            -- Check whether we can move through this object
            local is_passable = false
            if collision.touchtype < 0 then
                -- Objects we're overlapping are always passable
                is_passable = true
            elseif worldscene then
                -- TODO oh no this global definitely does not need to be in here
                local otheractor = worldscene.shape_to_actor[collision.shape]
                if otheractor and not otheractor:blocks(self, collision.move) then
                    is_passable = true
                end
            end

            -- Restrict our slide angle if the object blocks us
            if not is_passable then
                combined_clock:intersect(collision.clock)
            end

            -- If we're hitting the object and it's not passable, stop here
            if not first_collision and not is_passable and collision.touchtype > 0 then
                --print("< found first collision:", first_collision.move, "len2:", first_collision.len2)
                first_collision = collision
            end
        end

        -- Automatically break if we don't move for three iterations -- not
        -- moving once is okay because we might slide, but three indicates a
        -- bad loop somewhere
        -- TODO would be nice to avoid this entirely!  it happens, e.g., at the
        -- bottom of the slopetest ramp: position       (606.5,638.5)   velocity        (61.736288265774419415,121.03382860727833759)   movement        (1.5,2.5)
        -- TODO hang on, is it even possible (or reasonable) to not move after the first iteration?
        if first_collision and first_collision.len2 == 0 then
            stuckcounter = stuckcounter + 1
            if stuckcounter >= 3 then
                print("!!!  BREAKING OUT OF LOOP BECAUSE WE'RE STUCK, OOPS")
                attempted = Vector(0, 0)
                break
            end
        else
            stuckcounter = 0
        end

        -- Track the last clock, so we can tell the caller which directions
        -- they're still blocked in after moving
        -- TODO wow this is bad naming
        -- TODO this can be an empty clock, which is really an entire clock
        if lastclock and first_collision and first_collision.len2 == 0 then
            -- If we don't actually move, then...  this happens...
            -- TODO should this even happen?
            lastclock:intersect(combined_clock)
        else
            lastclock = combined_clock
        end

        if not first_collision then
            -- We don't actually hit anything this time!  Loop over
            break
        end

        -- Perform the actual move; we have to move ourselves so we can correctly handle the next iteration
        --print("moving by", first_collision.move)
        shape:move(first_collision.move:unpack())
        successful = successful + first_collision.move

        -- Slide along the extreme that's closest to the direction of movement
        --print("combined_clock:", combined_clock)
        local slide = combined_clock:closest_extreme(attempted)
        if slide and attempted ~= first_collision.move then
            local remaining = attempted - first_collision.move
            attempted = remaining:projectOn(slide)
            --print("slide!  remaining", remaining, "-> attempted", attempted)
        else
            attempted = Vector.zero:clone()
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
