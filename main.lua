local utf8 = require 'utf8'

local Class = require 'vendor.hump.class'
local Gamestate = require 'vendor.hump.gamestate'
local Vector = require 'vendor.hump.vector'

local ResourceManager = require 'klinklang.resources'
local WorldScene = require 'klinklang.scenes.world'
local SpriteSet = require 'klinklang.sprite'
local tiledmap = require 'klinklang.tiledmap'

local DialogueScene = require 'klinklang.scenes.dialogue'


game = {
    debug = false,
    resource_manager = nil,
    -- FIXME this seems ugly, but the alternative is to have sprite.lua implicitly depend here
    sprites = SpriteSet._all_sprites,
}

local TILE_SIZE = 32


--------------------------------------------------------------------------------

function love.load(args)
    for i, arg in ipairs(args) do
        if arg == '--xyzzy' then
            print('Nothing happens.')
            game.debug = true
        end
    end

    love.graphics.setDefaultFilter('nearest', 'nearest', 1)

    -- Load all the graphics upfront
    -- FIXME the savepoint sparkle is wrong, because i have no way to specify
    -- where to loop back to
    dialogueboximg = love.graphics.newImage('assets/images/isaac-dialogue.png')
    dialogueboximg2 = love.graphics.newImage('assets/images/lexy-dialogue.png')

    local tspath = 'data/tilesets/pico8.tsx.json'
    local tileset = tiledmap.TiledTileset(tspath, nil, resource_manager)
    resource_manager:add(tspath, tileset)
    local tspath = 'data/tilesets/portraits.tsx.json'
    local tileset = tiledmap.TiledTileset(tspath, nil, resource_manager)
    resource_manager:add(tspath, tileset)

    -- FIXME probably want a way to specify fonts with named roles
    local fontscale = 2
    m5x7 = love.graphics.newFont('assets/fonts/m5x7.ttf', 16 * fontscale)
    --m5x7:setLineHeight(0.75)  -- TODO figure this out for sure
    love.graphics.setFont(m5x7)

    local resource_manager = ResourceManager()
    resource_manager:register_default_loaders()
    resource_manager.locked = false  -- TODO make an api for this lol
    game.resource_manager = resource_manager
    resource_manager:load('assets/sounds/jump.ogg')

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
    map = tiledmap.TiledMap("data/maps/" .. game.maps[game.map_index], resource_manager)
    --map = tiledmap.TiledMap("data/maps/slopetest.tmx.json", resource_manager)
    worldscene = WorldScene()
    worldscene:load_map(map)

    Gamestate.registerEvents()
    Gamestate.switch(worldscene)
    --local tmpscene = DialogueScene(worldscene)
    --Gamestate.switch(tmpscene)
end

function love.draw()
    love.graphics.print(tostring(love.timer.getFPS( )), 10, 10)
end
