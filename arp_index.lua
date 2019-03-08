-- The Arp Index 1.0.0
--
-- xxxxxxxxxx.
--
-- Mark Eats
--

local ControlSpec = require "controlspec"
local Graph = require "mark_eats/graph"
local MusicUtil = require "mark_eats/musicutil"
local Passersby = require "mark_eats/passersby"
-- local Socket = require "socket"
-- local Http = require "socket.http"

engine.name = "Passersby"

local SCREEN_FRAMERATE = 15
local screen_dirty = true

local stock_graph = nil


-- Encoder input
function enc(n, delta)
  
  if n == 2 then
          
  elseif n == 3 then
    
  end
end

-- Key input
function key(n, z)
  if z == 1 then
    if n == 2 then
      
    elseif n == 3 then
      
    end
  end
end


function init()
  
  Passersby.add_params()
  
  -- print(Socket._VERSION)
  
  stock_graph = Graph.new(0, 6, "lin", 0, 100, "lin", "line", false, false)
  stock_graph:set_position_and_size(3, 23, 122, 38)
  stock_graph:set_active(false)
  
  for i = 0, 14 do
    stock_graph:add_point(util.linlin(0, 14, 0, 6, i), math.random(0, 100))
  end
  
  local screen_refresh_metro = metro.alloc()
  screen_refresh_metro.callback = function()
    if screen_dirty then
      screen_dirty = false
      redraw()
    end
  end
  
  screen_refresh_metro:start(1 / SCREEN_FRAMERATE)
  screen.aa(1)
end


function redraw()
  screen.clear()
  
  stock_graph:redraw()
  
  screen.move(3, 9)
  screen.level(15)
  screen.text("AAPL")
  screen.move(3, 18)
  screen.level(3)
  screen.text("157.14 +0.91")
  
  screen.move(125, 9)
  screen.text_right("1 week")
  
  
  screen.fill()
  
  screen.update()
end
