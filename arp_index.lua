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

local data_dirty = true
local current_symbol = 1
local current_range = 1
local ranges = {"1d", "1m", "3m", "1y"}
local range_names = {"1 day", "1 month", "3 months", "1 year"}

local symbols = {}
local price_history
local current_price
local price_change

local stock_graph


local function get_symbols_csv()
  -- https://github.com/datasets/s-and-p-500-companies
  local url = "https://raw.githubusercontent.com/datasets/s-and-p-500-companies/master/data/constituents.csv"
  return util.os_capture( "curl -s " .. url, true)
end

local function process_symbols_csv(csv)
  symbols = {}
  
  for symbol in string.gmatch(csv, "[\r\n](.-),") do
    table.insert(symbols, symbol)
  end
  
  current_symbol = util.clamp(current_symbol, 1, #symbols)
end

local function get_stock_price_json(symbol, range)
  range = range or "1m"
  local token = "pk_f33c104ac1674f268ddb10ed18012c33"
  local url = "https://cloud.iexapis.com/stable/stock/" .. symbol .. "/chart/" .. range .. "?token=" .. token .. "&chartCloseOnly=true"
  if range == "1d" then
    print("1 dayer")
    url = url .. "&chartInterval=15" --TODO this doesn't seem to be having an effect?! (count is still 390)
  end
  print(url)
  return util.os_capture( "curl -s " .. url, true)
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
  
  print("SIZE", #price_history)
  
  if current_range == 1 then --TODO could change
    price_change = util.round(price_history[#price_history] - price_history[1], 0.001)
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
  
  data_dirty = false
  
end

-- Encoder input
function enc(n, delta)
  
  if n == 2 then
    current_symbol = util.clamp(current_symbol + delta, 1, #symbols)
    data_dirty = true
          
  elseif n == 3 then
    
  end
  
  screen_dirty = true
end

-- Key input
function key(n, z)
  if z == 1 then
    if n == 2 then
      
      current_range = current_range % #ranges + 1
      data_dirty = true
      
    elseif n == 3 then
      
      print("key 3")
      
      if #symbols > 0 then
      
        local json = get_stock_price_json(symbols[current_symbol], ranges[current_range])
        -- print(data)
        process_stock_price_json(json)
      
        update_graph()
      
      else
        
        local csv = get_symbols_csv()
        process_symbols_csv(csv)
        
      end
      
      
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
  
  if #symbols == 0 then
    screen.move(63, 34)
    screen.level(3)
    screen.text_center("K3 to download index")
  
  else
  
    screen.move(3, 9)
    screen.level(15)
    screen.text(symbols[current_symbol])
    
    if not data_dirty then
      
      if current_price and price_change then
        screen.move(3, 18)
        screen.level(3)
        local price_change_string = price_change
        if price_change > 0 then price_change_string = "+" .. price_change_string end
        screen.text(current_price .. " " .. price_change_string)
      end
      
      stock_graph:redraw()
      
    else
      screen.move(3, 18)
      screen.level(3)
      screen.text("K3 to get prices")
    
    end
    
    screen.move(125, 9)
    screen.level(3)
    screen.text_right(range_names[current_range])
    
    screen.fill()
  
  end
  
  screen.update()
end
