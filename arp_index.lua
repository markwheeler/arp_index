-- The Arp Index
-- 1.0.0 @markeats
-- llllllll.co/t/arp-index
--
-- xxxxxxxxxx.
--
-- E1 : Xxxxxx
--

local ControlSpec = require "controlspec"
local Graph = require "graph"
local MusicUtil = require "musicutil"
local Passersby = require "passersby/lib/passersby_engine"

engine.name = "Passersby"

local SCREEN_FRAMERATE = 15
local screen_dirty = true

local current_range = 1
local ranges = {"1m", "3m", "1y"}
local range_names = {"1 month", "3 months", "1 year"}

local price_history
local current_price
local price_change


local stock_graph


local function get_stock_price_json(symbol, range)
  range = range or "1m"
  local token = "pk_f33c104ac1674f268ddb10ed18012c33"
  local data = util.os_capture( "curl -s https://cloud.iexapis.com/stable/stock/" .. symbol .. "/chart/" .. range .. "?token=" .. token .. "&chartCloseOnly=true")
  return data
end

local function process_stock_price_json(json)
  
  price_history = {}
  current_price = nil
  price_change = nil
  
  for entry in string.gmatch(json, "{(.-)}") do
    local closing_price = tonumber(string.match(entry, "\"close\":([%d.-]+)"))
    table.insert(price_history, closing_price)
    current_price = closing_price
    price_change = tonumber(string.match(entry, "\"change\":([%d.-]+)"))
  end
  
end

local function update_graph()
  
  stock_graph:remove_all_points()
  
  local min_price, max_price = 9999, 0
  local num_prices = #price_history
  
  for i = 1, num_prices do
    stock_graph:add_point(i, price_history[i])
    min_price = math.min(min_price, price_history[i])
    max_price = math.max(max_price, price_history[i])
  end
  
  stock_graph:set_x_max(num_prices)
  stock_graph:set_y_min(min_price)
  stock_graph:set_y_max(max_price)
  
end

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
      
      current_range = current_range % #ranges + 1
      
    elseif n == 3 then
      
      local data = get_stock_price_json("aapl", ranges[current_range])
      -- print(data)
      process_stock_price_json(data)
      
      update_graph()
      
      
    end
    
    screen_dirty = true
  end
end


function init()
  
  Passersby.add_params()
  
  stock_graph = Graph.new(1, 10, "lin", 0, 100, "lin", "line", false, false)
  stock_graph:set_position_and_size(3, 23, 122, 38)
  stock_graph:set_active(false)
  
  local screen_refresh_metro = metro.init()
  screen_refresh_metro.event = function()
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
  
  screen.level(3)
  if current_price and price_change then
    screen.move(3, 18)
    local price_change_string = price_change
    if price_change > 0 then price_change_string = "+" .. price_change_string end
    screen.text(current_price .. " " .. price_change_string)
  end
  
  screen.move(125, 9)
  screen.text_right(range_names[current_range])
  
  
  screen.fill()
  
  screen.update()
end
