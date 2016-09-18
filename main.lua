local utf8 = require 'utf8'

local anim8 = require 'vendor.anim8'
local Class = require 'vendor.hump.class'
local Gamestate = require 'vendor.hump.gamestate'
local Vector = require 'vendor.hump.vector'

local Player = require 'isaacsdescent.actors.player'
local ResourceManager = require 'isaacsdescent.resources'
local WorldScene = require 'isaacsdescent.scenes.world'
local TiledMap = require 'isaacsdescent.tiledmap'


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

function SpriteInstance:update(dt)
    self.anim:update(dt)
end

function SpriteInstance:draw_at(point)
    -- TODO hm, how do i auto-batch?  shame there's nothing for doing that
    -- built in?  seems an obvious thing
    self.anim:draw(self.sprite.image, point:unpack())
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

    -- TODO list resources to load declaratively and actually populate them in this function?
    p8_spritesheet = love.graphics.newImage('assets/images/spritesheet.png')
    game.sprites.wooden_switch = Sprite(p8_spritesheet, TILE_SIZE, TILE_SIZE, 0, 0)
    game.sprites.wooden_switch:add_pose('default', {9, 4}, 1, 'pauseAtEnd')
    game.sprites.magical_bridge = Sprite(p8_spritesheet, TILE_SIZE, TILE_SIZE, 0, 0)
    game.sprites.magical_bridge:add_pose('default', {11, 3}, 1, 'pauseAtEnd')

    local resource_manager = ResourceManager()
    resource_manager:register_default_loaders()
    resource_manager.locked = false  -- TODO make an api for this lol
    game.resource_manager = resource_manager
    map = TiledMap("data/maps/pico8-01.tmx.json", resource_manager)
    --map = TiledMap("data/maps/slopetest.tmx.json", resource_manager)
    worldscene = WorldScene(map)
    worldscene:add_actor(Player(Vector(1, 8) * TILE_SIZE))

    Gamestate.registerEvents()
    Gamestate.switch(worldscene)

    dialogueboximg = love.graphics.newImage('assets/images/isaac-dialogue.png')
    local fontscale = 2
    m5x7 = love.graphics.newFont('assets/fonts/m5x7.ttf', 16 * fontscale)
    m5x7:setLineHeight(0.75)  -- TODO figure this out for sure
end

function love.draw()
    love.graphics.print(tostring(love.timer.getFPS( )), 10, 10)
end

--------------------------------------------------------------------------------

local dialogue_state
function tmp_draw_dialogue()
    if not dialogue_state then
        dialogue_state = {
            progress = 0,
            time_passed = 0,
            total_time = 2,
            curline = 1,
            curchar = 0,
            done = false,
        }
        -- TODO æons  :(
        local full_text = "I would wager no one has set foot in these caves in eons.  It's a miracle any of these mechanisms still work."
        local _textwidth
        local wraplimit = love.graphics.getWidth() - 20 * 2
        _textwidth, dialogue_state.text_lines = m5x7:getWrap(full_text, wraplimit)
    end
    local dt = 1/60
    dialogue_state.time_passed = dialogue_state.time_passed + dt

    while not dialogue_state.done do
        dialogue_state.curchar = dialogue_state.curchar + 1
        if dialogue_state.curchar > string.len(dialogue_state.text_lines[dialogue_state.curline]) then
            if dialogue_state.curline == #dialogue_state.text_lines then
                dialogue_state.done = true
            else
                dialogue_state.curline = dialogue_state.curline + 1
                dialogue_state.curchar = 0
            end
            break
        end
        if string.sub(dialogue_state.text_lines[dialogue_state.curline], dialogue_state.curchar, dialogue_state.curchar) ~= " " then
            break
        end
    end


    love.graphics.setColor(0, 0, 0, 128)
    love.graphics.rectangle('fill', 0, 0, love.graphics.getDimensions())
    love.graphics.setColor(255, 255, 255)

    local boxheight = 160
    local boxwidth = love.graphics.getWidth()
    local boxtop = love.graphics.getHeight() - boxheight

    local boxrepeatleft, boxrepeatright = 192, 224
    local boxquadl = love.graphics.newQuad(0, 0, boxrepeatleft, dialogueboximg:getHeight(), dialogueboximg:getDimensions())
    love.graphics.draw(dialogueboximg, boxquadl, 0, boxtop, 0, 2)
    local boxquadm = love.graphics.newQuad(boxrepeatleft, 0, boxrepeatright - boxrepeatleft, dialogueboximg:getHeight(), dialogueboximg:getDimensions())
    love.graphics.draw(dialogueboximg, boxquadm, boxrepeatleft * 2, boxtop, 0, math.floor(love.graphics.getWidth() / (boxrepeatright - boxrepeatleft)) + 1, 2)
    local boxquadr = love.graphics.newQuad(boxrepeatright, 0, dialogueboximg:getWidth() - boxrepeatright, dialogueboximg:getHeight(), dialogueboximg:getDimensions())
    love.graphics.draw(dialogueboximg, boxquadr, love.graphics.getWidth() - (dialogueboximg:getWidth() - boxrepeatright) * 2, boxtop, 0, 2)


    local joinedtext = ""
    for line = 1, dialogue_state.curline do
         if line == dialogue_state.curline then
            joinedtext = joinedtext .. string.sub(dialogue_state.text_lines[line], 1, dialogue_state.curchar)
        else
            joinedtext = joinedtext .. dialogue_state.text_lines[line] .. "\n"
        end
    end
    local text = love.graphics.newText(m5x7, joinedtext)
    love.graphics.setColor(0, 0, 0, 128)
    love.graphics.draw(text, 32 - 2, boxtop + 32 + 2)
    love.graphics.setColor(255, 255, 255)
    love.graphics.draw(text, 32, boxtop + 32)

    local offset = 64
    if not dialogue_state.done and math.mod(dialogue_state.time_passed, 0.8) > 0.4 then
        offset = 128
    end
    local quad = love.graphics.newQuad(offset, 416, 64, 96, p8_spritesheet:getWidth(), p8_spritesheet:getHeight())
    local scale = 4
    love.graphics.draw(p8_spritesheet, quad, 32 + 64 * scale, boxtop - 96 * scale, 0, -scale, scale)
end
