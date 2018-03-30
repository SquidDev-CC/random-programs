local helpers = require "helpers"
local root = fs.combine(fs.getDir(shell.getRunningProgram()), "screens")

local colour_map = {}
for i = 0, 15 do colour_map[("%x"):format(i)] = 2^i end

local function set_background(monitor, vars, colour)
  monitor.setBackgroundColour(colour_map[colour])
end

local function set_scale(monitor, vars, scale)
  monitor.setTextScale(scale)
end

local function write_formatted(monitor, str)
  local idx = 1
  while true do
    local next = str:find("$", idx, true)

    if next then
      if next > idx then monitor.write(str:sub(idx, next - 1)) end

      local col = str:sub(next + 1, next + 1)
      monitor.setTextColour(colour_map[col])

      idx = next + 2
    else
      monitor.write(str:sub(idx))
      break
    end
  end
end

local function write_lines(monitor, subst_vars, str)
  monitor.setTextColour(colours.black)
  str = subst_vars(str)

  local _, y = monitor.getCursorPos()
  if str == "" then monitor.setCursorPos(2, y + 1); return end

  monitor.setCursorPos(2, y)
  for line in str:gmatch("([^\n]*)\n?") do
    monitor.clearLine()
    write_formatted(monitor, line)

    y = y + 1
    monitor.setCursorPos(2, y)
  end
end

local function write_centered(monitor, subst_vars, str)
  monitor.setTextColour(colours.black)
  str = subst_vars(str)

  local _, y = monitor.getCursorPos()
  if str == "" then monitor.setCursorPos(2, y + 1); return end

  local tw = monitor.getSize()
  local w = 0
  for line in str:gmatch("([^\n]*)\n?") do
    w = math.max(w, #line:gsub("%$[0-9a-f]", ""))
  end

  local x = math.floor((tw - w) / 2 + 1)
  monitor.setCursorPos(x, y)
  for line in str:gmatch("([^\n]*)\n?") do
    monitor.clearLine()
    write_formatted(monitor, line)

    y = y + 1
    monitor.setCursorPos(x, y)
  end
end

return function(monitor, initial, initial_vars)
  if type(monitor) == "string" then
    monitor = peripheral.wrap(monitor)
  end

  if type(monitor) ~= "table" then
    error("Cannot find monitor", 2)
  end

  local current, current_vars

  local function set(new, new_vars)
    if current == new and helpers.eq(current_vars, new_vars) then return end
    current = new
    current_vars = new_vars

    monitor.setCursorPos(1, 1)
    monitor.setBackgroundColour(colours.white)
    monitor.setTextColour(colours.black)
    monitor.clear()

    local function subst_vars(str)
      if new_vars then
        return str:gsub("%%%[([^%]]*)%]", new_vars)
      else
        return str
      end
    end

    local function wrap(f) return function(...) return f(monitor, subst_vars, ...) end end

    local env = {
      b = wrap(set_background),
      s = wrap(set_scale),

      w = wrap(write_lines),
      c = wrap(write_centered),

      v = new_vars
    }

    return helpers.do_file(fs.combine(root, new .. ".lua"), env)
  end

  set(initial, initial_vars)

  return { set = set }
end
