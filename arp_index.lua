-- The Arp Index
-- 1.0.0 @markeats
-- llllllll.co/t/arp-index
--
-- xxxxxxxxxx.
--
-- E1 : Xxxxxx
--
-- Data provided by http://iexcloud.io
--

local ControlSpec = require "controlspec"
local Graph = require "graph"
local MusicUtil = require "musicutil"
local Passersby = require "passersby/lib/passersby_engine"

engine.name = "Passersby"

local RANGES = {"1d", "1m", "3m", "1y"}
local RANGE_NAMES = {"1 day", "1 month", "3 months", "1 year"}
local API_TOKEN = "pk_f33c104ac1674f268ddb10ed18012c33"
local API_BASE_URL = "https://cloud.iexapis.com/v1/"

local SCREEN_FRAMERATE = 15
local screen_dirty = true

local current_company_id = 1
local current_range_id = 1

local num_companies = 0
local companies = {}
local note_steps = 8
local notes = {}

local current_step = 1

local stock_graph
local notes_graph


local function curl_request(url)
  print("Requesting...", url)
  return util.os_capture( "curl -s \"" .. url .. "\"", true)
end

local function get_companies_json()
  local url = API_BASE_URL .. "stock/market/list/mostactive?listLimit=100&filter=symbol,companyName&token=" .. API_TOKEN
  return curl_request(url)
end

local function process_companies_json(json)
  companies = {}
  for entry in string.gmatch(json, "{(.-)}") do
    table.insert(companies, {
      symbol = string.match(entry, "\"symbol\":\"(.-)\""),
      name =  string.match(entry, "\"companyName\":\"(.-)\""),
      data = {}
    })
  end
  table.sort(companies, function (k1, k2) return k1.symbol < k2.symbol end)
  -- table.sort(companies, function (k1, k2) return k1.name:lower() < k2.name:lower() end) --TODO
  
  num_companies = #companies
  current_company_id = util.clamp(current_company_id, 1, num_companies)
  screen_dirty = true
  
  print("Got companies", num_companies)
end

local function get_stock_price_json(symbol, range)
  range = range or "1m"
  
  local interval = 1
  if range == "1d" then
    interval = 4
  elseif range == "1y" then
    interval = 3
  end
  
  local url = API_BASE_URL .. "stock/" .. symbol .. "/chart/" .. range .. "?filter=close&chartInterval=" .. interval .. "&token=" .. API_TOKEN
  return curl_request(url)
end

local function process_stock_price_json(json)
  
  local data = {
    price_history = {},
    min_price = 9999,
    max_price = 0,
    current_price = nil,
    price_change = nil
  }
  
  for entry in string.gmatch(json, "{(.-)}") do
    local closing_price = tonumber(string.match(entry, "\"close\":([%d.-]+)"))
    if closing_price then
      table.insert(data.price_history, closing_price)
      data.min_price = math.min(data.min_price, closing_price)
      data.max_price = math.max(data.max_price, closing_price)
      data.current_price = closing_price
      data.price_change = tonumber(string.match(entry, "\"change\":([%d.-]+)"))
    end
  end
  
  print("Got prices", #data.price_history)
  
  if current_range_id == 1 then --TODO could change??
    data.price_change = util.round(data.price_history[#data.price_history] - data.price_history[1], 0.001)
  end
  
  companies[current_company_id].data[current_range_id] = data
  
end

local function update_stock_graph()
  
  stock_graph:remove_all_points()
  
  if num_companies > 0 and companies[current_company_id].data[current_range_id] then
  
    local data = companies[current_company_id].data[current_range_id]
    local num_prices = #data.price_history
    
    for i = 1, num_prices do
      stock_graph:add_point(i, data.price_history[i])
    end
    
    stock_graph:set_x_max(num_prices)
    stock_graph:set_y_min(data.min_price)
    stock_graph:set_y_max(data.max_price)
  
  end
end

local function generate_notes()
  notes = {}
  
  if num_companies > 0 and companies[current_company_id].data[current_range_id] then
    
    local data = companies[current_company_id].data[current_range_id]
    local num_prices = #data.price_history
    
    for i = 1, note_steps do
      local price = data.price_history[util.round(util.linlin(1, note_steps, 1, num_prices, i))]
      table.insert(notes, util.round(util.linlin(data.min_price, data.max_price, 1, 13, price)))
    end
  
  end
end

local function update_notes_graph()
  
  notes_graph:remove_all_points()
  
  for i = 1, #notes do
    notes_graph:add_point(i, notes[i])
  end
  
end

-- Encoder input
function enc(n, delta)
  
  delta = util.clamp(delta, -1, 1)
  
  if n == 1 then
    if num_companies > 0 then
      current_company_id = util.clamp(current_company_id + delta, 1, num_companies)
      generate_notes()
      update_stock_graph()
      update_notes_graph()
    end
  
  elseif n == 2 then
    if num_companies > 0 then
      current_range_id = util.clamp(current_range_id + delta, 1, #RANGES)
      generate_notes()
      update_stock_graph()
      update_notes_graph()
    end
          
  elseif n == 3 then
    
  end
  
  screen_dirty = true
end

-- Key input
function key(n, z)
  if z == 1 then
    if n == 2 then
      
      
      
    elseif n == 3 then
      
      if num_companies > 0 then
      
        if not companies[current_company_id].data[current_range_id] then
          local json = get_stock_price_json(companies[current_company_id].symbol, RANGES[current_range_id])
          process_stock_price_json(json)
          
          generate_notes()
          update_stock_graph()
          update_notes_graph()
        end
        
      else
        local json = get_companies_json()
        process_companies_json(json)
        
      end
      
      
    end
    
    screen_dirty = true
  end
end


function init()
  
  Passersby.add_params()
  
  stock_graph = Graph.new(1, 10, "lin", 0, 100, "lin", "line", false, false)
  stock_graph:set_position_and_size(3, 27, 122, 34)
  stock_graph:set_active(false)
  
  notes_graph = Graph.new(1, note_steps, "lin", 1, 13, "lin", "point", false, false)
  notes_graph:set_position_and_size(3, 27, 122, 34)
  
  local screen_refresh_metro = metro.init()
  screen_refresh_metro.event = function()
    if screen_dirty then
      screen_dirty = false
      redraw()
    end
  end
  
  screen_refresh_metro:start(1 / SCREEN_FRAMERATE)
  screen.aa(1)
  
  local json = get_companies_json()
  process_companies_json(json)
  
end


function redraw()
  
  screen.clear()
  
  if num_companies == 0 then
    screen.move(63, 34)
    screen.level(3)
    screen.text_center("No companies. K3 to retry.") --TODO show downloading/fail status?
  
  else
  
    local title = companies[current_company_id].symbol .. " " .. companies[current_company_id].name
    if title:len() > 25 then
      title = string.sub(title, 1, 25)
      title = string.gsub(title, "[%p%s]+$", "") -- Trim punctuation and spaces
      title = title .. "..."
    end
    screen.move(3, 9)
    screen.level(3)
    screen.text(title)
    screen.move(3, 9)
    screen.level(15)
    screen.text(companies[current_company_id].symbol)
    
    if companies[current_company_id].data[current_range_id] then
      
      if current_price and price_change then
        screen.move(125, 20)
        screen.level(3)
        local price_change_string = price_change
        if price_change > 0 then price_change_string = "+" .. price_change_string end
        screen.text_right(current_price .. " " .. price_change_string)
      end
      
      stock_graph:redraw()
      notes_graph:redraw()
    
    end
    
    screen.move(3, 20)
    screen.level(3)
    screen.text(RANGE_NAMES[current_range_id])
    
    screen.fill()
  
  end
  
  screen.update()
end
