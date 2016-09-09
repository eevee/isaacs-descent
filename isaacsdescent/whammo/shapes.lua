local Class = require 'vendor.hump.class'
local Vector = require 'vendor.hump.vector'

local util = require 'isaacsdescent.util'

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
    self:_generate_normals()
end

function Polygon:_generate_normals()
    self._normals = {}
    for _, edge in ipairs(self.edges) do
        local normal = edge:normal()
        -- What a mouthful
        self._normals[normal] = normal:normalized()
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

function Polygon:normals()
    return self._normals
end

function Polygon:project_onto_axis(axis)
    -- TODO maybe use vector-light here
    local minpt = Vector(self.coords[1], self.coords[2])
    local maxpt = minpt
    local min = axis * minpt
    local max = min
    for i = 3, #self.coords, 2 do
        local pt = Vector(self.coords[i], self.coords[i + 1])
        local dot = axis * pt
        if dot < min then
            min = dot
            minpt = pt
        elseif dot > max then
            max = dot
            maxpt = pt
        end
    end
    return min, max, minpt, maxpt
end

function Polygon:slide_towards(other, movement)
    -- TODO skip entirely if bbox movement renders this impossible
    -- Use the separating axis theorem.
    -- 1. Choose a bunch of axes, generally normals of the shapes.
    -- 2. Project both shapes along each axis.
    -- 3. If the projects overlap along ANY axis, the shapes overlap.
    --    Otherwise, they don't.
    -- This code also does a couple other things.
    -- b. It uses the direction of movement as an extra axis, in order to find
    --    the minimum possible movement between the two shapes.
    -- a. It keeps values around in terms of their original vectors, rather
    --    than lengths or normalized vectors, to avoid precision loss
    --    from taking square roots.

    -- Mapping of normal vectors (i.e. projection axes) to their normalized
    -- versions (needed for comparing the results of the projection)
    local movenormal = movement:perpendicular()
    --local axes = {[movement] = movement:normalized()}
    local axes = {[movenormal] = movenormal:normalized()}
    for norm, norm1 in pairs(self:normals()) do
        axes[norm] = norm1
    end
    for norm, norm1 in pairs(other:normals()) do
        axes[norm] = norm1
    end

    -- Project both shapes onto each axis and look for the minimum distance
    local maxdist = -math.huge
    local maxsep, maxdir
    -- TODO i would love to get rid of this
    local clock = util.ClockRange()
    for fullaxis, axis in pairs(axes) do
        local min1, max1, minpt1, maxpt1 = self:project_onto_axis(axis)
        local min2, max2, minpt2, maxpt2 = other:project_onto_axis(axis)
        local dist, sep
        if min1 < min2 then
            -- 1 appears first, so take the distance from 1 to 2
            dist = min2 - max1
            sep = minpt2 - maxpt1
        else
            -- Other way around
            dist = min1 - max2
            -- Note that sep is always the vector from us to them
            sep = maxpt2 - minpt1
        end
        if math.abs(dist) < 1e-8 then
            dist = 0
        end
        if dist >= 0 then
            -- The movement itself may be a slide, in which case we can stop
            -- here; we know they'll never collide
            local dot = fullaxis * movement
            if min1 < min2 then
                dot = -dot
            end
            if dot >= 0 then
                -- This is a slide
                return
            end
            -- If the distance isn't negative, then it's possible to do a slide
            -- anywhere in the general direction of this axis
            local perp = fullaxis:perpendicular()
            if min1 < min2 then
                perp = -perp
            end
            clock:union(-perp, perp)
        end
        if dist > maxdist then
            maxdist = dist
            maxsep = sep
            maxdir = fullaxis
        end
    end

    if maxdist < 0 then
        -- Shapes are already colliding
        -- TODO should maybe...  return something more specific here?
        return
    end

    -- TODO there must be a more sensible way to calculate this
    -- Vector describing the shortest gap
    local gap = maxsep:projectOn(maxdir)
    local allowed = movement:projectOn(maxdir)
    local dv
    if math.abs(allowed.x) > math.abs(allowed.y) then
        dv = gap.x / allowed.x
    else
        dv = gap.y / allowed.y
    end
    if dv > 1 then
        -- Won't actually hit!
        return
    end
    -- TODO i don't reeeally like this since it seems to suggest we will very
    -- slowly sink into a diagonal surface
    return dv, clock
end

-- An AABB, i.e., an unrotated rectangle
local _XAXIS = Vector(1, 0)
local _YAXIS = Vector(0, 1)
local Box = Class{
    __includes = Polygon,
    -- Handily, an AABB only has two normals: the x and y axes
    _normals = { [_XAXIS] = _XAXIS, [_YAXIS] = _YAXIS },
}

function Box:init(x, y, width, height)
    Shape.init(self)
    Polygon.init(self, x, y, x + width, y, x + width, y + height, x, y + height)
    self.width = width
    self.height = height
end

function Box:_generate_normals()
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
}
