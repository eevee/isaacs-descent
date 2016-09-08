local Vector = require 'vendor.hump.vector'

local whammo = require 'isaacsdescent.whammo'
local whammo_shapes = require 'isaacsdescent.whammo.shapes'

describe("Linear decomposition", function()
    it("should work", function()
        local seg1 = whammo_shapes.Segment(5, 0, 5, 10)
        local seg2 = whammo_shapes.Segment(0, 10, 10, 10)
        local dv = whammo_shapes.find_segment_intersection(seg1, seg2, Vector(5, 5))
        assert.are.equal(0, dv)
    end)
end)


describe("Segment", function()
    it("should work with the original PICO-8 demo case", function()
        local seg1 = whammo_shapes.Segment(32, 64, 96, 96)
        local seg2 = whammo_shapes.Segment(112, 16, 112, 96)
        local movement = Vector(32, -32)
        local dv = whammo_shapes.find_segment_intersection(seg1, seg2, movement)
        assert.are.equal(0.5, dv)
    end)
    it("should work when edges press together", function()
        local seg1 = whammo_shapes.Segment(93, 256, 61, 256)
        local seg2 = whammo_shapes.Segment(32, 256, 64, 256)
        local movement = Vector(-28.067511599511, 24.618287730896)
        local dv = whammo_shapes.find_segment_intersection(seg1, seg2, movement)
        assert.are.equal(0, dv)
    end)
end)

describe("Collision", function()
    it("should handle orthogonal movement", function()
        --[[
            +--------+
            | player |
            +--------+
            | floor  |
            +--------+
            movement is straight down; should do nothing
        ]]
        local collider = whammo.Collider(400)
        local floor = whammo_shapes.Box(0, 100, 100, 100)
        collider:add(floor)

        local player = whammo_shapes.Box(0, 0, 100, 100)
        local successful, hits = collider:slide(player, 0, 50)
        assert.are.equal(Vector(0, 0), successful)
        assert.is.truthy(hits[floor])
    end)
    it("should stop at the first obstacle", function()
        --[[
                +--------+
                | player |
                +--------+
            +--------+
            | floor1 |+--------+ 
            +--------+| floor2 | 
                      +--------+
            movement is straight down; should hit floor1 and stop
        ]]
        local collider = whammo.Collider(400)
        local floor1 = whammo_shapes.Box(0, 150, 100, 100)
        collider:add(floor1)
        local floor2 = whammo_shapes.Box(100, 200, 100, 100)
        collider:add(floor2)

        local player = whammo_shapes.Box(50, 0, 100, 100)
        local successful, hits = collider:slide(player, 0, 150)
        assert.are.equal(Vector(0, 50), successful)
        assert.is.truthy(hits[floor1])
        assert.is.falsy(hits[floor2])
    end)
    it("should allow sliding past an obstacle", function()
        --[[
            +--------+
            |  wall  |
            +--------+
                     +--------+
                     | player |
                     +--------+
            movement is straight up; shouldn't collide
        ]]
        local collider = whammo.Collider(400)
        local wall = whammo_shapes.Box(0, 0, 100, 100)
        collider:add(wall)

        local player = whammo_shapes.Box(100, 150, 100, 100)
        local successful, hits = collider:slide(player, 0, -150)
        assert.are.equal(Vector(0, -150), successful)
        assert.is.falsy(hits[wall])
    end)
    it("should handle diagonal movement into lone corners", function()
        --[[
            +--------+
            |  wall  |
            +--------+
                       +--------+
                       | player |
                       +--------+
            movement is up and to the left (more left); should slide left along
            the ceiling
        ]]
        local collider = whammo.Collider(400)
        local wall = whammo_shapes.Box(0, 0, 100, 100)
        collider:add(wall)

        local player = whammo_shapes.Box(200, 150, 100, 100)
        local successful, hits = collider:slide(player, -200, -100)
        assert.are.equal(Vector(-200, -50), successful)
        assert.is.truthy(hits[wall])
    end)
    it("should handle diagonal movement into corners with walls", function()
        --[[
            +--------+
            | wall 1 |
            +--------+--------+
            | wall 2 | player |
            +--------+--------+
            movement is up and to the left; should slide along the wall upwards
        ]]
        local collider = whammo.Collider(400)
        local wall1 = whammo_shapes.Box(0, 0, 100, 100)
        collider:add(wall1)
        local wall2 = whammo_shapes.Box(0, 100, 100, 100)
        collider:add(wall2)

        local player = whammo_shapes.Box(100, 100, 100, 100)
        local successful, hits = collider:slide(player, -50, -50)
        assert.are.equal(Vector(0, -50), successful)
        assert.is.truthy(hits[wall1])
        assert.is.truthy(hits[wall2])
    end)
    it("should slide you down when pressed against a corner", function()
        --[[
                     +--------+
            +--------+ player |
            |  wall  +--------+
            +--------+
            movement is down and to the left; should slide down along the wall
            at full speed
        ]]
        local collider = whammo.Collider(400)
        local wall = whammo_shapes.Box(0, 50, 100, 100)
        collider:add(wall)

        local player = whammo_shapes.Box(100, 0, 100, 100)
        local successful, hits = collider:slide(player, -100, 50)
        assert.are.equal(Vector(0, 50), successful)
        assert.is.truthy(hits[wall])
    end)
    it("should slide you down when pressed against a wall", function()
        --[[
            +--------+
            | wall 1 +--------+
            +--------+ player |
            | wall 2 +--------+
            +--------+
            movement is down and to the left; should slide down along the wall
            at full speed
        ]]
        local collider = whammo.Collider(400)
        local wall1 = whammo_shapes.Box(0, 0, 100, 100)
        collider:add(wall1)
        local wall2 = whammo_shapes.Box(0, 100, 100, 100)
        collider:add(wall2)

        local player = whammo_shapes.Box(100, 50, 100, 100)
        local successful, hits = collider:slide(player, -50, 100)
        assert.are.equal(Vector(0, 100), successful)
        assert.is.truthy(hits[wall1])
        assert.is.truthy(hits[wall2])
    end)

    it("should not let you fall into the floor", function()
        --[[
            Actual case seen when playing:
            +--------+
            | player |
            +--------+--------+
            | floor1 | floor2 |
            +--------+--------+
            movement is right and down (due to gravity)
        ]]
        local collider = whammo.Collider(4 * 32)
        local floor1 = whammo_shapes.Box(448, 384, 32, 32)
        collider:add(floor1)
        local floor2 = whammo_shapes.Box(32, 256, 32, 32)
        collider:add(floor2)

        local player = whammo_shapes.Box(443, 320, 32, 64)
        local successful, hits = collider:slide(player, 4.3068122830999, 0.73455352286288)
        assert.are.equal(Vector(4.3068122830999, 0), successful)
        assert.is.truthy(hits[floor1])
    end)
end)
