--[[
Argh!  The dreaded util module.  You know what to expect.
]]

--------------------------------------------------------------------------------
-- Conspicuous mathematical omissions

local function sign(n)
    if n == math.abs(n) then
        return 1
    else
        return -1
    end
end

local function divmod(n, b)
    return math.floor(n / b), math.mod(n, b)
end

return {
    sign = sign,
    divmod = divmod,
}
