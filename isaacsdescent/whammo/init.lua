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

local PRECISION = 1024 * 1024 * 1024

function Collider:slide(shape, dx, dy)
    local attempted = Vector(dx, dy)
    local successful = Vector(0, 0)
    -- TODO this only has hits from the last movement, oops
    local hits = {}  -- set of objects we ultimately bump into
    local last_slide  -- last direction we slide, for friction
    print()
    print()
    print("MOVEMENT TIME!!", attempted, "bbox:", shape:bbox())

    -- TODO i am pretty sure this needs to hit the closest thing first, then
    -- repeat until movement is exhausted or an iteration has no hits
    debug_hits = {}
    local stuckcounter = 0
    while true do
        local anyhit = false
        local min_d = 1
        local neighbors = self.blockmap:neighbors(shape, attempted:unpack())
        for neighbor in pairs(neighbors) do
            local d, clock = shape:slide_towards_3(neighbor, attempted)
            if d then
                print("*** Hit registered:", d, clock, "via", neighbor:bbox())
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

        print("---")
        print("Finished one round with d =", min_d)
        if not anyhit then
            --print("Breaking because no hits?")
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
        --print("Successful movement:", this_move:unpack())
        --print("Now at:", shape.x0, shape.y0 + min_d * dy)
        successful = successful + this_move
        -- We have a set of allowed angles, represented with pairs of clock hands.
        -- We want to know: what is the allowed angle that is the closest to
        -- our attempted movement?
        -- It must be one of the endpoints.  So start with whichever of the
        -- first pair of hands is closer, which we can find by using the dot
        -- product -- it's larger the closer together the angles are.
        -- TODO i don't see a way to avoid taking full magnitude here
        -- TODO really ought to sort the results somehow, to avoid
        -- non-determinism?  but i guess this IS a sort, of a sort
        -- TODO slide must also be within the general direction of the
        -- movement, so that's a good starting point, but is very likely to
        -- create intersections
        local moveperp = attempted:perpendicular()
        local finalclock = util.ClockRange(-moveperp, moveperp)
        local finalclock = util.ClockRange(util.ClockRange.ZERO, util.ClockRange.ZERO)
        for neighbor, clock in pairs(hits) do
            print("intersecting with", clock)
            finalclock:intersect(clock)
        end
        print("finalclock:", finalclock)
        -- Finally, find a fucking hand
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
        print("slide:", slide)

        print("original attempt:   ", attempted)
        print("step made this loop:", this_move)
        local remaining = attempted - this_move
        print("left after movement:", remaining)
        remaining = remaining:projectOn(slide)
        print("left after slide:   ", remaining)
        -- TODO is this equivalent to attempted = attempted - attempted:projectOn(normal)?
        -- TODO what if the sign's different?
        if math.abs(remaining.x) > math.abs(attempted.x) then
            remaining.x = attempted.x
        end
        if math.abs(remaining.y) > math.abs(attempted.y) then
            remaining.y = attempted.y
        end
        print("left after trim:    ", remaining)
        attempted = remaining

        for hit in pairs(hits) do
            debug_hits[hit] = true
        end

        if attempted.x == 0 and attempted.y == 0 then
            break
        end
    end

    -- Whatever's left over is unopposed
    shape:move(attempted:unpack())
    print("final movement:", successful + attempted)
    return successful + attempted, hits, last_slide
end

function Collider:slide__old(shape, dx, dy)
    local sx, sy = 0, 0  -- successful movement
    local hits = {}  -- set of objects we ultimately bump into

    -- TODO i am pretty sure this needs to hit the closest thing first, then
    -- repeat until movement is exhausted or an iteration has no hits
    while true do
        local anyhit = false
        local min_d = 1
        local neighbors = self.blockmap:neighbors(shape, dx, dy)
        for neighbor in pairs(neighbors) do
            local hit, d, normx, normy = shape:slide_towards(neighbor, dx, dy)
            if hit then
                print("*** Hit registered:", d, normx, normy)
                anyhit = true
                if d < min_d then
                    min_d = d
                    hits = {}
                end
                hits[neighbor] = {normx, normy}
            end
        end

        print("---")
        print("Finished one round with d =", min_d)
        if not anyhit then
            print("Breaking because no hits?")
            break
        end
        shape:move(min_d * dx, min_d * dy)
        print("Successful movement:", min_d * dx, min_d * dy)
        print("Now at:", shape.x0 + min_d * dx, shape.y0 + min_d * dy)
        sx = sx + min_d * dx
        sy = sy + min_d * dy
        -- We have a set of normal vectors, possibly in different directions.
        -- Each one also has two possible perpendicular vectors, along which we
        -- must slide.
        -- Choose the perp that has the FURTHEST angle from the direction of
        -- movement, as indicated by the dot product with the smallest absolute
        -- value.  That means we're moving along, or away from, all contacted
        -- surfaces.  TODO: Not true for convex shapes!
        local perpx, perpy = 0, 0
        local min_dot = math.huge
        for shape, stuff in pairs(hits) do
            local nx, ny = unpack(stuff)

            local p1x, p1y = ny, -nx
            local dot = math.abs(vector_light.dot(dx, dy, p1x, p1y))
            --print("...trying perp vector", p1x, p1y, "which has dot product", dot)
            if dot < min_dot then
                perpx, perpy = p1x, p1y
                dot = min_dot
            end

            local p2x, p2y = -ny, nx
            local dot = math.abs(vector_light.dot(dx, dy, p2x, p2y))
            --print("...trying perp vector", p2x, p2y, "which has dot product", dot)
            if dot < min_dot then
                perpx, perpy = p2x, p2y
                dot = min_dot
            end
        end
        print("Remaining movement:", dx, dy)
        print("Computed slide vector:", perpx, perpy)
        dx, dy = vector_light.project((1 - min_d) * dx, (1 - min_d) * dy, perpx, perpy)
        print("Remaining (slid) movement:", dx, dy)

        if dx == 0 and dy == 0 then
            print("Breaking because no movement left")
            break
        end
    end

    -- Whatever's left over is unopposed
    shape:move(dx, dy)
    return sx + dx, sy + dy, hits
end

return {
    Collider = Collider,
}
