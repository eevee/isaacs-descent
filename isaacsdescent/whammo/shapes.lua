local Class = require 'vendor.hump.class'
local Vector = require 'vendor.hump.vector'

local util = require 'isaacsdescent.util'

local function union_clock_hands(a0, a1, b0, b1)
    if not a0 then
        return b0, b1
    end
    -- The new left endpoint should only replace the old one if it's further ccw
    if util.vector_clock_direction(a0, b0) < 0 then
        a0 = b0
        print("Setting first hand to", b0)
    end
    -- Same for the other
    if util.vector_clock_direction(a1, b1) > 0 then
        a1 = b1
        print("Setting second hand to", b1)
    end
    -- TODO ah, but we're dealing with a circle here, so what happens if they
    -- move so far back that they overlap?  that seems unlikely, since we
    -- SHOULD only be dealing with maximum two edges here, but...

    return a0, a1
end

local function intersect_clock_hands(a0, a1, b0, b1)
    if not a0 then
        return b0, b1
    end
    -- TODO explain
    -- TODO what if there's no overlap?
    -- TODO what if the overlap creates two sections?  consider < and >
    if util.vector_clock_direction(a0, b0) > 0 then
        a0 = b0
        print("Setting first hand to", b0)
    end
    if util.vector_clock_direction(a1, b1) < 0 then
        a1 = b1
        print("Setting second hand to", b1)
    end

    return a0, a1
end

local Segment = Class{}

function Segment:init(x0, y0, x1, y1)
    self.x0 = x0
    self.y0 = y0
    self.x1 = x1
    self.y1 = y1
end

function Segment:__tostring()
    return ("<Segment: %f, %f to %f, %f>"):format(
        self.x0, self.y0, self.x1, self.y1)
end

function Segment:point0()
    return Vector(self.x0, self.y0)
end

function Segment:point1()
    return Vector(self.x1, self.y1)
end

function Segment:tovector()
    return Vector(self.x1 - self.x0, self.y1 - self.y0)
end

-- Returns the "outwards" normal as a Vector, assuming the points are given
-- clockwise
function Segment:normal()
    return Vector(self.y1 - self.y0, -(self.x1 - self.x0))
end

function Segment:move(dx, dy)
    self.x0 = self.x0 + dx
    self.x1 = self.x1 + dx
    self.y0 = self.y0 + dy
    self.y1 = self.y1 + dy
end




local Shape = Class{}

function Shape:init()
    self.blockmaps = setmetatable({}, {__mode = 'k'})
end

function Shape:remember_blockmap(blockmap)
    self.blockmaps[blockmap] = true
end

function Shape:forget_blockmap(blockmap)
    self.blockmaps[blockmap] = nil
end

function Shape:update_blockmaps()
    for blockmap in pairs(self.blockmaps) do
        blockmap:update(self)
    end
end

-- Extend a bbox along a movement vector (to enclose all space it might cross
-- along the way)
function Shape:extended_bbox(dx, dy)
    local x0, y0, x1, y1 = self:bbox()

    dx = dx or 0
    dy = dy or 0
    if dx < 0 then
        x0 = x0 + dx
    elseif dx > 0 then
        x1 = x1 + dx
    end
    if dy < 0 then
        y0 = y0 + dy
    elseif dy > 0 then
        y1 = y1 + dy
    end

    return x0, y0, x1, y1
end

-- An arbitrary (CONVEX) polygon
local Polygon = Class{
    __includes = Shape,
}

function Polygon:init(...)
    Shape.init(self)
    self.edges = {}
    local coords = {...}
    self.coords = coords
    self.x0 = coords[1]
    self.y0 = coords[2]
    self.x1 = coords[1]
    self.y1 = coords[2]
    for n = 1, #coords - 2, 2 do
        table.insert(self.edges, Segment(unpack(coords, n, n + 4)))
        if coords[n + 2] < self.x0 then
            self.x0 = coords[n + 2]
        end
        if coords[n + 2] > self.x1 then
            self.x1 = coords[n + 2]
        end
        if coords[n + 3] < self.y0 then
            self.y0 = coords[n + 3]
        end
        if coords[n + 3] > self.y1 then
            self.y1 = coords[n + 3]
        end
    end
    table.insert(self.edges, Segment(coords[#coords - 1], coords[#coords], coords[1], coords[2]))
    print("Edges:")
    for _, edge in ipairs(self.edges) do
        print(edge)
    end
end

function Polygon:bbox()
    return self.x0, self.y0, self.x1, self.y1
end

function Polygon:move(dx, dy)
    self.x0 = self.x0 + dx
    self.x1 = self.x1 + dx
    self.y0 = self.y0 + dy
    self.y1 = self.y1 + dy
    for n = 1, #self.coords, 2 do
        self.coords[n] = self.coords[n] + dx
        self.coords[n + 1] = self.coords[n + 1] + dy
    end
    for _, edge in ipairs(self.edges) do
        edge:move(dx, dy)
    end
    self:update_blockmaps()
end

function Polygon:move_to(x, y)
    -- TODO
    error("TODO")
end

function Polygon:center()
    -- TODO uhh
    return self.x0 + self.width / 2, self.y0 + self.height / 2
end

function Polygon:draw(mode)
    love.graphics.polygon(mode, self.coords)
end

-- Return a list of Segments representing edges that are facing in the given
-- (general) direction
function Polygon:get_facing_edges(direction)
    local ret = {}
    --[[
    local edges = {
        -- top
        Segment(self.x0, self.y0, self.x1, self.y0),
        -- right
        Segment(self.x1, self.y0, self.x1, self.y1),
        -- bottom
        Segment(self.x1, self.y1, self.x0, self.y1),
        -- left
        Segment(self.x0, self.y1, self.x0, self.y0),
    }
    ]]
    for _, edge in ipairs(self.edges) do
        -- Edge is only facing in the given direction if it's less than a
        -- quarter turn away, i.e., the dot product is positive
        if edge:normal() * direction > 0 then
            table.insert(ret, edge)
        end
    end
    return ret
end

local function linearly_decompose_point(seg, axis, point)
    local numer = axis.y * (point.x - seg.x0) - axis.x * (point.y - seg.y0)
    local denom = axis.y * (seg.x1 - seg.x0) - axis.x * (seg.y1 - seg.y0)
    -- TODO denom could be zero, if axis is parallel to segment -- indicates
    -- either a miss OR a case we just have to handle by hand
    local t = numer / denom
    -- todo be sure to use whichever of vx or vy is abs bigger
    -- To avoid dividing by zero (and precision issues), calculate dv using
    -- whichever component of the vector is greater
    local dv
    if math.abs(axis.x) > math.abs(axis.y) then
        dv = (point.x - seg.x0 - t * (seg.x1 - seg.x0)) / axis.x
    else
        dv = (point.y - seg.y0 - t * (seg.y1 - seg.y0)) / axis.y
    end
    --local sx = x0 + t * (x1 - x0)
    --local sy = y0 + t * (y1 - y0)
    --pset(sx, sy, 10)
    return t, dv
end

local function find_segment_intersection(A, B, v)
    --[[
    Here's the fun part!

    We have two line segments, A and B.  Segment A is moving along the movement
    vector v.  When, and where, will it strike segment B -- if at all?

                  B
                  |
       A     v    |
        \   /     |
         \        |
          \
           \

    It's easier to reason about if A, B, and v are all orthogonal.

                  B
                  |
        A         |
        |  --> v  |
        |         |
        |

    Now the solution isn't too hard (which is probably why everyone uses only
    AABBs).  If A and B overlap horizontally, and the horizontal distance
    between them is less than v, then A will collide with B.  Done.

    Observe that in the above diagram, if we tilt A or B slightly, there are
    only four possible points of contact: the endpoints of A and B.  This is
    true in general: the endpoints are "corners", and two objects can only
    collide at corners or along edges.  So either one of those points is the
    collision point, the two lines are parallel and come to touch each other
    (in which case at least two of the endpoints will still collide anyway), or
    the lines won't meet at all.

    The trick to the general case, then, is to do the same thing -- but instead
    of looking along the x-axis, we have to look along the v-axis.  (You could
    do this by literally rotating the plane, but that would take a bunch of
    trig, which is slow and not actually necessary.)  First we express the two
    line segments as pairs of parametric equations, which you may recall are
    equations that define x and y separately in terms of another variable t.

        x = x0 + t * (x1 - x0)
        y = y0 + t * (y1 - y0)

    This makes t range from 0 to 1 along each segment, which is handy, because
    it's very easy to tell whether a given t lies within the segment.

    Next, we consider one of B's endpoints, P.  P can be expressed -- uniquely!
    -- as a point Q somewhere on A, shifted along v by some distance dv.  This
    is just like the orthogonal case, only following the v vector instead of
    the x-axis.  The result looks like:

        P = Q + dv * v

    But P and Q are both points, v is a vector, and Q (being on A) is defined
    by parametric equations.  We can split this up and substitute those in:

        Px = Ax0 + t * (Ax1 - Ax0) + dv * v
        Py = Ay0 + t * (Ay1 - Ay0) + dv * v

    All of these values are known, except t and dv.  This is a simple system of
    linear equations; solve it, and you know how far along the movement the
    collision happens (dv).  Repeat for all four points, constrain to the line
    segments, and we have the answer.

    In fact, we don't even need to try all four points, because we already the
    answers for A's endpoints: they're A's endpoints, plus zero of v!  So we
    can just try B's endpoints.
    ]]

    -- First, figure out how to express each of B's endpoints as a point on A
    -- plus some amount of v.  dv is that amount; t is the parameter that will
    -- give us a point on A.
    local t0, dv0 = linearly_decompose_point(A, v, B:point0())
    local t1, dv1 = linearly_decompose_point(A, v, B:point1())
    -- Fix, ahem, any rounding errors.  I occasionally see a dv of 0 end up as
    -- -1e-16 within LÖVE, which is of course less than zero and counted as
    -- invalid, allowing the player to occasionally clip through a solid
    -- surface.  I can't reproduce this with stock Lua.  I hate floats.
    if math.abs(dv0) < 1e-8 then
        dv0 = 0
    end
    if math.abs(dv1) < 1e-8 then
        dv1 = 0
    end

    -- These variables track which end we hit: 0, 1, or nil.  It's used by the
    -- caller to figure out where to slide to avoid the collision.
    -- If the solution for t is at 0 or 1, that means it's at A's endpoint
    local Aend0, Aend1
    if t0 == 0 or t0 == 1 then
        Aend0 = t0
    end
    if t1 == 0 or t1 == 1 then
        Aend1 = t1
    end
    -- And of course we know that both solutions are at B's endpoints
    local Bend0, Bend1 = 0, 1
    -- Ensure the solutions are in order for the next part.  They might not be,
    -- depending on the order of B's endpoints
    if t0 > t1 then
        t0, t1 = t1, t0
        dv0, dv1 = dv1, dv0
        Aend0, Aend1 = Aend1, Aend0
        Bend0, Bend1 = Bend1, Bend0
    end
    --print("original soln 0", t0, dv0, Aend0, Bend0)
    --print("original soln 1", t1, dv1, Aend1, Bend1)

    -- Now, the span t0 to t1 is the projection of B onto A.  If that span
    -- doesn't overlap [0, 1] -- the range of t's valid for A -- then A will
    -- completely bypass B, and we're done.
    if t1 < 0 or t0 > 1 then
        return
    end

    -- Constrain the [t0, t1] span to within [0, 1].  In other words, if t0 is
    -- less than zero, then A can never hit B's endpoint.  BUT, A's endpoint
    -- might still strike B, so compute dv for that case.  The same applies to
    -- the other endpoint.
    -- How do we compute dv, though?  We could find the intersection and
    -- compute the distance and divide by v's magnitude...  but there's an
    -- easier trick.  t and dv are related linearly, since they describe the
    -- distance between two lines.  If you move halfway from t0 to t1 --
    -- halfway from one point on A to another point on A -- then you also move
    -- halfway from dv0 to dv1.  Express that relation as another set of
    -- parametric equations (calling the new parameter q) and substitute.
    if t0 < 0 then
        -- Note that the new parameter = (new_t - t0) / (t1 - t0), which has
        -- been substituted into the formula for dv; this code just does the
        -- multiplication first to reduce float error.
        -- This denominator can never be zero; we know t0 < 0 because we're in
        -- this block, and we know t0 > 0 because we didn't return early.
        dv0 = dv0 + (0 - t0) * (dv1 - dv0) / (t1 - t0)
        if math.abs(dv0) < 1e-8 then
            dv0 = 0
        end
        t0 = 0
        Aend0 = 0
        if t1 == 0 then
            -- Unusual case where t0 is negative and t1 is zero, so t = 0 does
            -- in fact hit B's endpoint
            Bend0 = Bend1
        else
            Bend0 = nil
        end
    end
    -- Same thing for the other endpoint
    if t1 > 1 then
        dv1 = dv0 + (1 - t0) * (dv1 - dv0) / (t1 - t0)
        if math.abs(dv1) < 1e-8 then
            dv1 = 0
        end
        t1 = 1
        Aend1 = 1
        if t0 == 1 then
            Bend1 = Bend0
        else
            Bend1 = nil
        end
    end
    --print("adjusted soln 0", t0, dv0, Aend0, Bend0)
    --print("adjusted soln 1", t1, dv1, Aend1, Bend1)

    -- Now we have two points on A.  Whichever will hit first -- that is,
    -- whichever has the lower dv -- is the point of collision.
    -- One final wrinkle is that we don't want results where dv is less than
    -- zero (indicating A already passed B) or greater than one (indicating A
    -- won't move far enough).
    if dv1 < dv0 then
        t0, t1 = t1, t0
        dv0, dv1 = dv1, dv0
        Aend0, Aend1 = Aend1, Aend0
        Bend0, Bend1 = Bend1, Bend0
    end
    if dv1 < 0 or dv0 > 1 then
        -- A won't move far enough; neither result lies in [0, 1]
        return
    end
    -- At least one is valid, so return whichever it is
    if 0 <= dv0 then
        if dv0 == dv1 and t0 ~= t1 then
            -- Two valid points are an equal distance away, meaning the edges
            -- are parallel and will collide
            return dv0, nil, nil
        end
        return dv0, Aend0, Bend0
    else
        return dv1, Aend1, Bend1
    end
    -- TODO i wonder what happens if the lines are already intersecting...
end





function Polygon:slide_towards_2(other, movement)
    local our_edges = self:get_facing_edges(movement)
    local their_edges = other:get_facing_edges(-movement)

    local dv = math.huge
    local clocks = {}
    for _, A in ipairs(our_edges) do
        --print("A:", A.x0, A.y0, A.x1, A.y1)
        for _, B in ipairs(their_edges) do
            --print("  B:", B.x0, B.y0, B.x1, B.y1)
            local new_dv, a_end, b_end = find_segment_intersection(A, B, movement)
            -- TODO fix precision errors here?  specifically i think i'd want
            -- to round to pixel movement, and maybe add a tiny buffer to fix
            -- issues with dipping less than a pixel into an object
            if new_dv then
                --print("    dv:", new_dv, a_end, b_end)
            end
            if new_dv and new_dv <= dv then
                dv = new_dv
                if new_dv < dv then
                    clocks = {}
                end
                -- Figure out which way we could slide to avoid the collision.
                -- There are three interesting cases: our corner hit their
                -- edge, our edge hit their corner, or both corners collided.
                -- (It's also possible for both edges to collide, but that
                -- works out the same as either edge-corner case.)
                local new_slide_range
                -- TODO incorrectly handled: two edges meeting face to face
                -- when their corners also touch; different from corners
                -- passing each other!
                if a_end and b_end then
                    -- Corner hits corner.  The movement range is quite wide,
                    -- since either edge could slide along the other.
                    -- I don't know how to prove this, but drawing it out, it
                    -- seems to be just whichever angle between the edges is a
                    -- reflex (i.e. greater than a semicircle).
                    -- Also, we need vectors pointing away from the point of
                    -- intersection, so flip the edges if they touched at their
                    -- ends rather than their beginnings
                    local vecA = A:tovector()
                    if a_end == 0 then
                        -- A needs to be flipped the other way, actually...
                        vecA = -vecA
                    end
                    local vecB = B:tovector()
                    if b_end == 1 then
                        vecB = -vecB
                    end

                    local dir = util.ClockRange.direction(vecA, vecB)
                    if dir > 0 then
                        -- B is clockwise from A; B to A is the bigger angle
                        table.insert(clocks, util.ClockRange(vecB, vecA))
                    elseif dir < 0 then
                        -- Reverse case
                        table.insert(clocks, util.ClockRange(vecA, vecB))
                    else
                        -- Edges are parallel!  Any slide direction is okay
                    end
                elseif a_end then
                    -- A's corner hit B's edge; use B's normal
                    local perp = B:normal():perpendicular()
                    table.insert(clocks, util.ClockRange(-perp, perp))
                else
                    -- A's edge hit B's corner; use A's normal, but reverse it
                    -- to face away from the direction of movement
                    local perp = A:normal():perpendicular()
                    table.insert(clocks, util.ClockRange(perp, -perp))
                end
            end
        end
    end
    -- Sometimes dv is just a rounding error away from 0 or 1, so fix it here
    if math.abs(dv - 0) < 1e-10 then
        dv = 0
    elseif math.abs(dv - 1) < 1e-10 then
        dv = 1
    elseif dv == math.huge or dv < 0 or dv > 1 then
        return
    end

    -- Last step is combining the normals, sob.
    -- A normal is really a way to express a set of directions that spans
    -- exactly half the circle.  If you collide with a flat surface, then ANY
    -- of those directions will move you away without colliding.
    -- If you collide with a corner, though, there's more than a half-circle of
    -- allowed directions.  Express this as a pair of "clock hands", where the
    -- ranges of angles swept between them (clockwise) is allowed.
    -- Initial range is the first normal rotated 90 degrees ccw and cw.  Note
    -- that Vector.perpendicular rotates clockwise.
    --[[
    local hand0, hand1
    for i, normal in ipairs(normals) do
        hand0, hand1 = union_clock_hands(hand0, hand1, -normal:perpendicular(), normal:perpendicular())
    end
    ]]

    local finalclock = util.ClockRange(util.ClockRange.ZERO, util.ClockRange.ZERO)
    for _, clock in ipairs(clocks) do
        finalclock:intersect(clock)
    end


    -- If the final clock includes the original requested motion, then nothing
    -- is actually blocking (might be a slide) and we should return nothing
    if finalclock:includes(movement) then
        return
    end

    return dv, finalclock
end

function Polygon:slide_towards(other, dx, dy)
    -- TODO early return if the moving bbox won't even intersect the other
    --print("[SLIDE_TOWARDS]", dx, dy, "with other's bbox:", other:bbox())
    -- Assuming all boxes for now
    -- TODO don't do that
    -- One sliding AABB can only collide with another at one of its "forward"
    -- edges, i.e., one of the edges facing the direction of motion.
    -- If the slide is orthogonal, there's only one candidate edge; if the
    -- slide is zero (if, say, we already collided with something else), we
    -- need to test touch instead, which is really all four edges.
    -- Note that if the boxes overlap, this code will usually allow the slide.
    -- TODO is that what we want?  what's the right thing there, actually?
    local hit = false
    local d = 1
    local zero = dx == 0 and dy == 0
    local nx, ny = 0, 0
    -- Whether our bbox will overlap AFTER moving
    local overlapx = self.x1 + dx > other.x0 and self.x0 + dx < other.x1
    local overlapy = self.y1 + dy > other.y0 and self.y0 + dy < other.y1

    -- Left
    if dx < 0 or zero then
        -- Their x; our starting and ending x
        --print("- moving left!")
        local x = other.x1
        local sx = self.x0
        local ex = self.x0 + dx
        if overlapy and ex <= x and x <= sx then
            --print("  - HIT!!")
            hit = true
            local new_d
            if zero then
                new_d = 0
            else
                new_d = (sx - x) / (sx - ex)
            end
            nx = 1
            if new_d < d then
                d = new_d
                ny = 0
            end
        end
    end
    -- Right
    if dx > 0 or zero then
        --print("- moving right!")
        local x = other.x0
        local sx = self.x1
        local ex = self.x1 + dx
        if overlapy and sx <= x and x <= ex then
            --print("  - HIT!!")
            hit = true
            local new_d
            if zero then
                new_d = 0
            else
                new_d = (sx - x) / (sx - ex)
            end
            nx = -1
            if new_d < d then
                d = new_d
                ny = 0
            end
        end
    end

    -- Up
    if dy < 0 or zero then
        -- Their y; our starting and ending y
        --print("- moving up!")
        local y = other.y1
        local sy = self.y0
        local ey = self.y0 + dy
        if overlapx and ey <= y and y <= sy then
            --print("  - HIT!!")
            hit = true
            local new_d
            if zero then
                new_d = 0
            else
                new_d = (sy - y) / (sy - ey)
            end
            ny = 1
            if new_d < d then
                d = new_d
                nx = 0
            end
        end
    end
    -- Down
    if dy > 0 or zero then
        local y = other.y0
        local sy = self.y1
        local ey = self.y1 + dy
        --print("- moving down!", sy, y, ey)
        if overlapx and sy <= y and y <= ey then
            --print("  - HIT!!")
            hit = true
            local new_d
            if zero then
                new_d = 0
            else
                new_d = (sy - y) / (sy - ey)
            end
            ny = -1
            if new_d < d then
                d = new_d
                nx = 0
            end
        end
    end

    return hit, d, nx, ny
end

-- An AABB, i.e., an unrotated rectangle
local Box = Class{
    __includes = Polygon,
}

function Box:init(x, y, width, height)
    Shape.init(self)
    Polygon.init(self, x, y, x + width, y, x + width, y + height, x, y + height)
    self.width = width
    self.height = height
end

function Box:move_to(x, y)
    self:move(x - self.x0, y - self.y0)
    self:update_blockmaps()
end

function Box:center()
    return self.x0 + self.width / 2, self.y0 + self.height / 2
end

return {
    Box = Box,
    Polygon = Polygon,
    Segment = Segment,
    linearly_decompose_point = linearly_decompose_point,
    find_segment_intersection = find_segment_intersection,
}
