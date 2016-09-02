local utf8 = require 'utf8'

local Class = require 'vendor.hump.class'
local Gamestate = require 'vendor.hump.gamestate'
local Vector = require 'vendor.hump.vector'

local PlayerActor = require 'isaacsdescent.actors.player'
local TiledMap = require 'isaacsdescent.tiledmap'
local WorldScene = require 'isaacsdescent.scenes.world'


game = {
    sprites = {},
}

local TILE_SIZE = 32


--------------------------------------------------------------------------------
-- Sprite definitions

local SpriteFrame = Class{}

function SpriteFrame:init(spritesheet, region)
    self.spritesheet = spritesheet
    self.region = region
    self.quad = love.graphics.newQuad(
        self.region.l, self.region.t, self.region.w, self.region.h,
        spritesheet:getDimensions())
end

function SpriteFrame:draw_at(point, dt, hflip)
    local x, y = point:unpack()
    local sx, sy = 1, 1
    if hflip then
        x = x + self.region.w
        sx = sx * -1
    end
    love.graphics.draw(self.spritesheet, self.quad, x, y, 0, sx, sy)
end


--------------------------------------------------------------------------------

function love.load(arg)
    love.graphics.setDefaultFilter('nearest', 'nearest', 1)
    -- TODO list all this declaratively and actually populate it in this function?
    p8_spritesheet = love.graphics.newImage('assets/images/spritesheet.png')
    game.sprites.isaac_stand = SpriteFrame(
        -- TODO need a better way to chop up spritesheet; probably exists already
        p8_spritesheet, { l = 32, t = 0, w = 32, h = 64})

    map = TiledMap("assets/maps/all-pico8.tiled.json", function() return p8_spritesheet end)
    worldscene = WorldScene(map)
    worldscene:add_actor(PlayerActor(Vector(1, 6) * TILE_SIZE))

    Gamestate.registerEvents()
    Gamestate.switch(worldscene)

    dialogueboximg = love.graphics.newImage('assets/images/isaac-dialogue.png')
    local fontscale = 2
    m5x7 = love.graphics.newFont('assets/fonts/m5x7.ttf', 16 * fontscale)
    m5x7:setLineHeight(0.75)  -- TODO figure this out for sure
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
