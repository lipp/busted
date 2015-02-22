local copas = require'copas'
local super = require'busted.loop.default'

local protected
local xprotected
if _VERSION == 'Lua 5.1' then
   protected = copcall
   xprotected = coxpcall
else
   protected = pcall
   xprotected = xpcall
end

-- create OO table, using `loop.default` as the ancestor/super class
return setmetatable({ 
    step = function()
      copas.step(0)
      super.step()  -- call ancestor to check for timers 
    end,
    pcall = protected,
    xpcall = xprotected
  }, { __index = super})

