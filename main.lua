local utf8 = require 'utf8'

local anim8 = require 'vendor.anim8'
local Class = require 'vendor.hump.class'
local Gamestate = require 'vendor.hump.gamestate'
local Vector = require 'vendor.hump.vector'

local ResourceManager = require 'isaacsdescent.resources'
local WorldScene = require 'isaacsdescent.scenes.world'
local TiledMap = require 'isaacsdescent.tiledmap'

local DialogueScene = require 'isaacsdescent.scenes.dialogue'


game = {
    sprites = {},
}

local TILE_SIZE = 32


--------------------------------------------------------------------------------
-- Sprite
-- Contains a number of 'poses', each of which is an anim8 animation.  Can
-- switch between them and draw with a simplified API.

local Sprite = Class{}
local SpriteInstance  -- defined below

-- TODO this restricts a single sprite to only pull frames from a single image,
-- which isn't unreasonable, but also seems like a needless limitation
-- TODO seems like this could be wired in with Tiled?  apparently Tiled can
-- even define animations, ha!
function Sprite:init(image, tilewidth, tileheight, x, y, margin)
    self.image = image
    self.grid = anim8.newGrid(
        tilewidth, tileheight,
        image:getWidth(), image:getHeight(),
        x, y, margin)
    self.poses = {}
    self.default_pose = nil
end

function Sprite:add_pose(name, grid_args, durations, endfunc)
    -- TODO this is pretty hokey, but is a start at support for non-symmetrical
    -- characters.  maybe add an arg to set_pose rather than forcing the caller
    -- to do this same name mangling though?
    local rightname = name .. '/right'
    local leftname = name .. '/left'
    assert(not self.poses[rightname], ("Pose %s already exists"):format(rightname))
    local anim = anim8.newAnimation(
        self.grid(unpack(grid_args)), durations, endfunc)
    self.poses[rightname] = anim
    self.poses[leftname] = anim:clone():flipH()
    if not self.default_pose then
        self.default_pose = rightname
    end
end

-- A Sprite is a definition; call this to get an instance with state, which can
-- draw itself and remember its current pose
function Sprite:instantiate()
    return SpriteInstance(self)
end

SpriteInstance = Class{}

function SpriteInstance:init(sprite)
    self.sprite = sprite
    self.scale = 1
    self.pose = nil
    self.anim = nil
    self:set_pose(sprite.default_pose)
end

function SpriteInstance:set_pose(pose)
    if pose == self.pose then
        return
    end
    assert(self.sprite.poses[pose], ("No such pose %s"):format(pose))
    self.pose = pose
    self.anim = self.sprite.poses[pose]:clone()
end

function SpriteInstance:set_scale(scale)
    self.scale = scale
end

function SpriteInstance:update(dt)
    self.anim:update(dt)
end

function SpriteInstance:draw_at(point)
    -- TODO hm, how do i auto-batch?  shame there's nothing for doing that
    -- built in?  seems an obvious thing
    self.anim:draw(self.sprite.image, point.x, point.y, 0, self.scale, self.scale)
end


--------------------------------------------------------------------------------

function love.load(arg)
    love.graphics.setDefaultFilter('nearest', 'nearest', 1)

    -- Load all the graphics upfront
    -- TODO i wouldn't mind having this defined in some json
    local character_sheet = love.graphics.newImage('assets/images/player.png')
    -- TODO istm i'll end up repeating this bit a lot
    game.sprites.isaac = Sprite(character_sheet, TILE_SIZE, TILE_SIZE * 2, 32, 32)
    game.sprites.isaac:add_pose('stand', {1, 1}, 0.05, 'pauseAtEnd')
    game.sprites.isaac:add_pose('walk', {'2-9', 1}, 0.1)
    game.sprites.isaac:add_pose('fall', {'10-11', 1}, 0.1)
    game.sprites.isaac:add_pose('jump', {'12-13', 1}, 0.05, 'pauseAtEnd')

    -- TODO list resources to load declaratively and actually populate them in this function?
    p8_spritesheet = love.graphics.newImage('assets/images/spritesheet.png')
    game.sprites.spikes_up = Sprite(p8_spritesheet, TILE_SIZE, TILE_SIZE, 0, 0)
    game.sprites.spikes_up:add_pose('default', {9, 1}, 1, 'pauseAtEnd')
    game.sprites.wooden_switch = Sprite(p8_spritesheet, TILE_SIZE, TILE_SIZE, 0, 0)
    game.sprites.wooden_switch:add_pose('default', {9, 4}, 1, 'pauseAtEnd')
    game.sprites.magical_bridge = Sprite(p8_spritesheet, TILE_SIZE, TILE_SIZE, 0, 0)
    game.sprites.magical_bridge:add_pose('default', {11, 3}, 1, 'pauseAtEnd')
    game.sprites.savepoint = Sprite(p8_spritesheet, TILE_SIZE, TILE_SIZE, 0, 0)
    game.sprites.savepoint:add_pose('default', {'9-15', 2}, {1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1})

    dialogue_spritesheet = love.graphics.newImage('assets/images/dialogue.png')
    game.sprites.isaac_dialogue = Sprite(dialogue_spritesheet, 64, 96, 0, 0)
    game.sprites.isaac_dialogue:add_pose('default', {2, 1}, 1, 'pauseAtEnd')
    game.sprites.isaac_dialogue:add_pose('default/talk', {"2-3", 1}, 0.25)
    game.sprites.lexy_dialogue = Sprite(dialogue_spritesheet, 64, 96, 0, 0)
    game.sprites.lexy_dialogue:add_pose('default', {1, 1}, 1, 'pauseAtEnd')
    game.sprites.lexy_dialogue:add_pose('default/talk', {1, 1, 4, 1}, 0.25)
    game.sprites.lexy_dialogue:add_pose('yeahsure', {6, 1}, 1, 'pauseAtEnd')
    game.sprites.lexy_dialogue:add_pose('yeahsure/talk', {6, 1, 5, 1}, 0.25)

    dialogueboximg = love.graphics.newImage('assets/images/isaac-dialogue.png')
    dialogueboximg2 = love.graphics.newImage('assets/images/lexy-dialogue.png')
    local fontscale = 2
    m5x7 = love.graphics.newFont('assets/fonts/m5x7.ttf', 16 * fontscale)
    m5x7:setLineHeight(0.75)  -- TODO figure this out for sure
    love.graphics.setFont(m5x7)

    local resource_manager = ResourceManager()
    resource_manager:register_default_loaders()
    resource_manager.locked = false  -- TODO make an api for this lol
    game.resource_manager = resource_manager

    game.maps = {
        'pico8-01.tmx.json',
        'pico8-02.tmx.json',
        'pico8-03.tmx.json',
        'pico8-04.tmx.json',
        'pico8-05.tmx.json',
        'pico8-06.tmx.json',
        'pico8-07.tmx.json',
        'pico8-08.tmx.json',
        'pico8-09.tmx.json',
        'pico8-10.tmx.json',
        'pico8-11.tmx.json',
    }
    -- TODO should maps instead hardcode their next maps?  or should they just
    -- have a generic "exit" a la doom?
    game.map_index = 1
    map = TiledMap("data/maps/" .. game.maps[game.map_index], resource_manager)
    --map = TiledMap("data/maps/slopetest.tmx.json", resource_manager)
    worldscene = WorldScene(map)

    Gamestate.registerEvents()
    Gamestate.switch(worldscene)
    --local tmpscene = DialogueScene(worldscene)
    --Gamestate.switch(tmpscene)
end

function love.draw()
    love.graphics.print(tostring(love.timer.getFPS( )), 10, 10)
end
