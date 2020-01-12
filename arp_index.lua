-- The Arp Index
-- 1.0.1 @markeats
-- llllllll.co/t/the-arp-index
--
-- Check the stock market.
-- Requires internet.
--
-- E1 : Company
-- E2 : Time span
-- E3 : Steps
-- K2 : Play/Stop
-- K1+K2 : Reset clock
-- K3 : Refresh
--
-- Data provided by
-- http://iexcloud.io
--

local ControlSpec = require "controlspec"
local Graph = require "graph"
local BeatClock = require "beatclock"
local MusicUtil = require "musicutil"
local MollyThePoly = require "molly_the_poly/lib/molly_the_poly_engine"

engine.name = "MollyThePoly"

local options = {}
options.OUTPUT = {"Audio", "MIDI", "Audio + MIDI"}
options.STEP_LENGTH_NAMES = {"1 bar", "1/2", "1/3", "1/4", "1/6", "1/8", "1/12", "1/16", "1/24", "1/32"}
options.STEP_LENGTH_DIVIDERS = {1, 2, 3, 4, 6, 8, 12, 16, 24, 32}
options.SCALE_NAMES = {}

local RANGES = {"1d", "1m", "3m", "1y"}
local RANGE_NAMES = {"1 day", "1 month", "3 months", "1 year"}
local API_TOKEN = "pk_f33c104ac1674f268ddb10ed18012c33"
local API_BASE_URL = "https://cloud.iexapis.com/v1/"

local SCREEN_FRAMERATE = 15
local screen_dirty = true

local shift_mode = false

local downloading = false
local steps_changed_timeout = 0
local show_steps_changed = false

local current_company_id = 1
local current_range_id = 1

local num_companies = 0
local companies = {}
local notes = {}
local scale
local sequences = {internal = 1}
local active_notes = {}
local step_on = true
local need_to_switch = false

local stock_graph

local beat_clock

local midi_in_device
local midi_in_channel
local midi_out_device
local midi_out_channel


local function format_note_num(param)
  return MusicUtil.note_num_to_name(param:get(), true)
end


local function note_on(note_num)
  
  -- print("note_on", note_num, MusicUtil.note_num_to_name(note_num, true))
  
  -- Audio engine out
  if params:get("output") == 1 or params:get("output") == 3 then
    engine.noteOn(note_num, MusicUtil.note_num_to_freq(note_num), 0.75)
  end
  
  -- MIDI out
  if (params:get("output") == 2 or params:get("output") == 3) then
    midi_out_device:note_on(note_num, 96, midi_out_channel)
  end
  
end

local function note_off(note_num)
  
  -- print("note_off", note_num, MusicUtil.note_num_to_name(note_num, true))
  
  -- Audio engine out
  if params:get("output") == 1 or params:get("output") == 3 then
    engine.noteOff(note_num)
  end
  
  -- MIDI out
  if (params:get("output") == 2 or params:get("output") == 3) then
    midi_out_device:note_off(note_num, nil, midi_out_channel)
  end
  
end

local function all_notes_kill()
  
  -- Audio engine out
  engine.noteKillAll()
  
  for k, v in pairs(active_notes) do
    -- MIDI out
    if (params:get("output") == 2 or params:get("output") == 3) then
      midi_out_device:note_off(v, 96, midi_out_channel)
    end
    active_notes[k] = nil
  end
end


-- Get data

local function curl_request(url)
  print("Requesting...", url)
  return util.os_capture( "curl -sS --max-time 20 \"" .. url .. "\"", true)
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
      data = {},
      preset = {}
    })
  end
  table.sort(companies, function (k1, k2) return k1.symbol < k2.symbol end)
  
  num_companies = #companies
  
  if num_companies < 1 then
    print("Error proessing companies", json)
  end
  
  current_company_id = util.clamp(current_company_id, 1, num_companies)
  downloading = false
  screen_dirty = true
  
  print("Got companies", num_companies)
end

local function get_companies()
  downloading = true
  redraw()
  local json = get_companies_json()
  process_companies_json(json)
end

local function get_stock_price_json(symbol, range)
  range = range or "1m"
  
  local filter = "close,change"
  local interval = 1
  if range == "1d" then
    interval = 4
    filter = "close"
  elseif range == "1y" then
    interval = 3
  end
  
  local url = API_BASE_URL .. "stock/" .. symbol .. "/chart/" .. range .. "?filter=" .. filter .. "&chartInterval=" .. interval .. "&token=" .. API_TOKEN
  return curl_request(url)
end

local function process_stock_price_json(json, range)
  
  local current_price
  local price_change
  
  local data = {
    price_history = {},
    min_price = 9999,
    max_price = 0,
  }
  
  for entry in string.gmatch(json, "{(.-)}") do
    local closing_price = tonumber(string.match(entry, "\"close\":([%d.-]+)"))
    if closing_price then
      table.insert(data.price_history, closing_price)
      data.min_price = math.min(data.min_price, closing_price)
      data.max_price = math.max(data.max_price, closing_price)
      current_price = closing_price
      price_change = tonumber(string.match(entry, "\"change\":([%d.-]+)"))
    end
  end
  
  if #data.price_history < 1 then
    print("Error processing prices", json)
    return
  end
  
  if range == "1d" then
    price_change = util.round(data.price_history[#data.price_history] - data.price_history[1], 0.001)
  end
  
  -- Find range ID
  local range_id
  for k, v in pairs(RANGES) do
    if v == range then
      range_id = k
      break
    end
  end
  
  companies[current_company_id].data[range_id] = data
  if not companies[current_company_id].current_price or range == "1d" then
    companies[current_company_id].current_price = current_price
    companies[current_company_id].price_change = price_change
  end
  
  print("Got prices", #data.price_history)
  
end

local function get_stock_prices(symbol)
  print("Getting", symbol)
  beat_clock:stop()
  downloading = true
  redraw()
  
  for _, r in pairs(RANGES) do
    local json = get_stock_price_json(symbol, r)
    process_stock_price_json(json, r)
  end
  
  downloading = false
  beat_clock:start()
  print("Got all", symbol)
end

local function generate_synth_preset()
  
  if math.random() > 0.9 then
    MollyThePoly.randomize_params("percussion")
  else
    MollyThePoly.randomize_params("lead")
  end
  
end

local function store_synth_preset()
  
  local param_names = {
    "osc_wave_shape",
    "pulse_width_mod",
    "pulse_width_mod_src",
    "freq_mod_lfo",
    "freq_mod_env",
    "glide",
    "main_osc_level",
    "sub_osc_level",
    "sub_osc_detune",
    "noise_level",
    "hp_filter_cutoff",
    "lp_filter_cutoff",
    "lp_filter_resonance",
    "lp_filter_type",
    "lp_filter_env",
    "lp_filter_mod_env",
    "lp_filter_mod_lfo",
    "lp_filter_tracking",
    "lfo_freq",
    "lfo_wave_shape",
    "lfo_fade",
    "env_1_attack",
    "env_1_decay",
    "env_1_sustain",
    "env_1_release",
    "env_2_attack",
    "env_2_decay",
    "env_2_sustain",
    "env_2_release",
    "amp",
    "amp_mod",
    "ring_mod_freq",
    "ring_mod_fade",
    "ring_mod_mix",
    "chorus_mix",
  }
  
  for _, v in pairs(param_names) do
    companies[current_company_id].preset[v] = params:get(v)
  end
  
end

local function switch_synth_preset()
  for k, v in pairs(companies[current_company_id].preset) do
    params:set(k, v)
  end
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

local function generate_scale()
  scale = MusicUtil.generate_scale(params:get("scale_root"), params:get("scale_type"), params:get("octaves"))
end

local function generate_notes()
  notes = {}
  
  if num_companies > 0 and companies[current_company_id].data[current_range_id] then
    
    local data = companies[current_company_id].data[current_range_id]
    local num_prices = #data.price_history
    local scale_len = #scale
    
    for i = 1, params:get("num_steps") do
      local note = {}
      
      local price_position = util.linlin(1, params:get("num_steps"), 1, num_prices, i)
      local prev_price = data.price_history[math.floor(price_position)]
      local next_price = data.price_history[math.ceil(price_position)]
      local price = util.linlin(0, 1, prev_price, next_price, price_position % 1)
      local scale_position = util.round(util.linlin(data.min_price, data.max_price, 1, scale_len, price))
      
      note.num = scale[scale_position]
      note.x = util.round(util.linlin(1, params:get("num_steps"), 0, stock_graph:get_width(), i) + stock_graph:get_x())
      note.y = util.round(util.linlin(1, scale_len, stock_graph:get_height(), 0, scale_position) + stock_graph:get_y())
      table.insert(notes, note)
    end
  
  end
end


-- Beat clock

local function start_sequence(id)
  sequences[id] = 0
end

local function stop_sequence(id)
  sequences[id] = nil
end

local function advance_step()
  
  if step_on then
    
    if #notes == params:get("num_steps") then
      
      if need_to_switch then
        switch_synth_preset()
        need_to_switch = false
      end
      
      -- Advance and note on
      for id, step in pairs(sequences) do
        local next_step = step % params:get("num_steps") + 1
        local note_id = notes[next_step].num
        if id ~= "internal" then
          note_id = note_id + id - 60
        end
        if not active_notes[note_id] then
          note_on(note_id)
          active_notes[note_id] = step
        end
        sequences[id] = next_step
      end
      
      screen_dirty = true
    
    end
    
  else
    
    -- Note offs
    for k, v in pairs(active_notes) do
      note_off(k)
      active_notes[k] = nil
    end
    
  end
  
  step_on = not step_on
end

local function stop()
  all_notes_kill()
  for _, step in pairs(sequences) do
    step = 1
  end
  beat_clock:reset()
end

local function reset_step()
  for _, step in pairs(sequences) do
    step = 1
  end
  beat_clock:reset()
  -- TODO does this call stop or do I need to kill notes here?
end


-- Encoder input
function enc(n, delta)
  
  if not downloading then
  
    delta = util.clamp(delta, -1, 1)
    
    if n == 1 then
      if num_companies > 0 then
        if not need_to_switch then -- Don't store if we haven't had time to switch
          store_synth_preset()
        end
        current_company_id = util.clamp(current_company_id + delta, 1, num_companies)
        need_to_switch = true
        generate_notes()
        update_stock_graph()
      end
    
    elseif n == 2 then
      if num_companies > 0 then
        current_range_id = util.clamp(current_range_id + delta, 1, #RANGES)
        generate_notes()
        update_stock_graph()
      end
      
    elseif n == 3 then
      params:delta("num_steps", delta)
    end
    
    screen_dirty = true
  end
end

-- Key input
function key(n, z)
  
  if n == 1 then
    shift_mode = z == 1
  end
  
  if z == 1 and not downloading then
    if n == 2 then
      
      if shift_mode then
        
        -- Reset clock
        beat_clock:reset()
        for k, v in pairs(sequences) do
          if v then
            sequences[k] = 0
          end
        end
        
      else
        
        -- Stop / play
        if sequences.internal then
          sequences.internal = nil
        else
          sequences.internal = 0
        end
        
      end
      
    elseif n == 3 then
      
      if num_companies > 0 then
      
        -- Download stock history and generate preset
        if not companies[current_company_id].data[current_range_id] then
          get_stock_prices(companies[current_company_id].symbol)
          generate_synth_preset()
          store_synth_preset()
          generate_notes()
          update_stock_graph()
          
        -- Generate a new preset
        else
          generate_synth_preset()
          store_synth_preset()
          
        end
        
      else
        get_companies()
        
      end
      
      
    end
    
    screen_dirty = true
  end
end


-- MIDI events
local function midi_event(data)
  local msg = midi.to_msg(data)
  if msg.ch == midi_in_channel then
    if msg.type == "note_on" then
      start_sequence(msg.note)
    elseif msg.type == "note_off" then
      stop_sequence(msg.note)
    end
  end
end


function init()
  
  for _, v in ipairs(MusicUtil.SCALES) do
    table.insert(options.SCALE_NAMES, v.name)
  end
  
  stock_graph = Graph.new(1, 10, "lin", 0, 100, "lin", "line", false, false)
  stock_graph:set_position_and_size(4, 27, 120, 34)
  stock_graph:set_active(false)
  
  midi_in_device = midi.connect(1)
  midi_in_device.event = midi_event
  
  midi_out_device = midi.connect(1)
  
  local screen_refresh_metro = metro.init()
  screen_refresh_metro.event = function()
    update()
    if screen_dirty then
      screen_dirty = false
      redraw()
    end
  end
  
  beat_clock = BeatClock.new()
  
  beat_clock.on_step = advance_step
  beat_clock.on_stop = stop
  
  -- Add params
  
  params:add{type = "option", id = "output", name = "Output", options = options.OUTPUT, action = all_notes_kill}
  
  params:add{type = "number", id = "midi_in_device", name = "MIDI In Device", min = 1, max = 4, default = 1,
    action = function(value)
      midi_in_device.event = nil
      midi_in_device = midi.connect(value)
      midi_in_device.event = midi_event
    end}
  
  params:add{type = "number", id = "midi_in_channel", name = "MIDI In Channel", min = 1, max = 16, default = 1,
    action = function(value)
      midi_in_channel = value
    end}
  
  params:add{type = "number", id = "midi_out_device", name = "MIDI Out Device", min = 1, max = 4, default = 1,
    action = function(value)
      midi_out_device = midi.connect(value)
    end}
  
  params:add{type = "number", id = "midi_out_channel", name = "MIDI Out Channel", min = 1, max = 16, default = 1,
    action = function(value)
      all_notes_kill()
      midi_out_channel = value
    end}
  
  params:add{type = "option", id = "clock_out", name = "Clock Out", options = {"Off", "On"}, default = beat_clock.send or 2 and 1,
    action = function(value)
      if value == 1 then beat_clock.send = false
      else beat_clock.send = true end
    end}
  
  params:add{type = "number", id = "bpm", name = "BPM", min = 1, max = 240, default = beat_clock.bpm,
    action = function(value)
      beat_clock:bpm_change(value)
      screen_dirty = true
    end}
  
  params:add{type = "option", id = "step_length", name = "Step Length", options = options.STEP_LENGTH_NAMES, default = 8,
    action = function(value)
      beat_clock.ticks_per_step = 96 / options.STEP_LENGTH_DIVIDERS[value]
      beat_clock.steps_per_beat = options.STEP_LENGTH_DIVIDERS[value] / 2
      beat_clock:bpm_change(beat_clock.bpm)
    end}
    
  params:add{type = "number", id = "num_steps", name = "Steps", min = 1, max = 32, default = 4,
    action = function(value)
      steps_changed_timeout = 1
      show_steps_changed = true
      generate_notes()
    end}
    
  params:add{type = "number", id = "scale_root", name = "Scale Root", min = 0, max = 127, default = 60, formatter = format_note_num, 
    action = function(value)
      generate_scale()
      generate_notes()
    end}
    
  params:add{type = "option", id = "scale_type", name = "Scale", options = options.SCALE_NAMES, default = 1,
    action = function(value)
      generate_scale()
      generate_notes()
    end}
    
  params:add{type = "number", id = "octaves", name = "Octaves", min = 1, max = 4, default = 1,
    action = function(value)
      generate_scale()
      generate_notes()
    end}
    
  params:add_separator()
  
  MollyThePoly.add_params()
  
  midi_in_channel = params:get("midi_in_channel")
  midi_out_channel = params:get("midi_out_channel")
  
  get_companies()

  -- Start metros
  screen.aa(1)  
  screen_refresh_metro:start(1 / SCREEN_FRAMERATE)
  beat_clock:start()
  
end


function update()
  if steps_changed_timeout > 0 then
    steps_changed_timeout = steps_changed_timeout - 1 / SCREEN_FRAMERATE
  else
    show_steps_changed = false
    screen_dirty = true
  end
  
end

function redraw()
  
  screen.clear()
  
  -- Downloading
  if downloading then
    
    screen.move(63, 34)
    screen.level(3)
    screen.text_center("Downloading...")
    screen.fill()
    
  else
  
    -- No companies
    if num_companies == 0 then
      screen.move(63, 34)
      screen.level(3)
      screen.text_center("No companies, K3 to retry") --TODO show downloading/fail status?
      screen.fill()
    
    -- Company
    else
    
      -- Symbol and name
      local title = companies[current_company_id].symbol .. " " .. companies[current_company_id].name
      title = util.trim_string_to_width(title, 122)
      screen.move(3, 9)
      screen.level(3)
      screen.text(title)
      screen.move(3, 9)
      screen.level(15)
      screen.text(companies[current_company_id].symbol)
      
      -- Byline
      screen.move(3, 20)
      screen.level(3)
      if show_steps_changed then
         -- Number of steps
         screen.text(params:get("num_steps") .. " steps")
      else
        -- Range
        screen.text(RANGE_NAMES[current_range_id])
      end
      screen.fill()
      
      -- Price and price change
      if companies[current_company_id].current_price and companies[current_company_id].price_change then
        screen.move(125, 20)
        screen.level(3)
        local price_change_string = companies[current_company_id].price_change
        if companies[current_company_id].price_change > 0 then price_change_string = "+" .. price_change_string end
        screen.text_right("$" .. companies[current_company_id].current_price .. " " .. price_change_string)
      end
      
      -- Graph and notes
      if companies[current_company_id].data[current_range_id] then
        
        stock_graph:redraw()
        
        local BACK_SIZE = 6.5
        local FRONT_SIZE = 3.5
        
        local note_level = 15
        
        for _, v in pairs(sequences) do
          if notes[v] then
            
            local n = notes[v]
            
            screen.move(n.x, n.y - BACK_SIZE)
            screen.line(n.x + BACK_SIZE, n.y)
            screen.line(n.x, n.y + BACK_SIZE)
            screen.line(n.x - BACK_SIZE, n.y)
            screen.close()
            screen.level(0)
            screen.fill()
            
            screen.move(n.x, n.y - FRONT_SIZE)
            screen.line(n.x + FRONT_SIZE, n.y)
            screen.line(n.x, n.y + FRONT_SIZE)
            screen.line(n.x - FRONT_SIZE, n.y)
            screen.close()
            screen.level(note_level)
            screen.stroke()
            
            note_level = math.max(3, note_level - 3)
          end
        end
        
      -- Download prompt
      else
        screen.move(3, 42)
        screen.level(3)
        screen.text("K3 to download")
        screen.fill()
      
      end
    
    end
  
  end
  
  screen.update()
end
