local tick = require 'vendor.tick'
local Vector = require 'vendor.hump.vector'

local BaseScene = require 'klinklang.scenes.base'

local CreditsScene = BaseScene:extend{
    __tostring = function(self) return "credits" end,
}

function CreditsScene:init()
end

function CreditsScene:update(dt)
end

function CreditsScene:draw()
    love.graphics.push('all')
    love.graphics.printf("You did it, Isaac!\n\nYou found the Flurry, the legendary enchanted sabre.\n\nNow you just need to, ah, get back out of here.\n\nGood luck with that!\n\n\n\nThanks for playing!\nStay tuned for the full game, coming...  ah...  sometime!", 50, 150, 700, "center")
    love.graphics.pop()
end

return CreditsScene
