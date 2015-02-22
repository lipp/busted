local uv = require'lluv'

local loop = {}

loop.create_timer = function(secs,on_timeout)
  local timer
  timer = uv.timer(uv.default_loop())
  timer:start(secs*1000, function()
                 timer:close()
    timer = nil
    on_timeout()
  end)

  return {
    stop = function()
                
      if timer then
        timer:close()
        timer = nil
      end
    end
  }
end

loop.step = function()
  uv.default_loop():run(debug.traceback)
end

loop.pcall = pcall

return loop
