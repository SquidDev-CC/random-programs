--[[- Tiny Lua profiler for ComputerCraft.

This generates a speedscope.json file, compatible with https://www.speedscope.app/.

Run like `scope.lua program arg1 arg2 arg3`. You can also pass
`scope.lua -n100 ...` to sample every 100 instructions (default is 1k).
]]

local args = { ... }

local count = 1e4

if args[1] and args[1]:sub(1, 2) == "-n" then
  local arg = table.remove(args, 1)
  if arg == "-n" then
    count = tonumber(table.remove(args, 2))
  else
    count = tonumber(arg:sub(3))
  end

  if not count then error("Expected -n COUNT", 0) end
end

local profiles = {}

local native_co_create, getinfo, clock = coroutine.create, debug.getinfo, os.epoch
local function coroutine_create(func)
  local co = native_co_create(func)

  -- Create a profiler for this coroutine, and set up the basic speedscope structure.
  local stacks, stacks_n = {}, 0
  profiles[#profiles + 1] = {
    type = "sampled",
    name = tostring(co),
    unit = "milliseconds",
    startValue = clock("utc"),
    -- Temporary values
    stacks = stacks,
    -- Not yet filled out:
    -- endValue,
    -- samples,
    -- weights,
  }
  -- Then install a debug hook which runs every n instructions and captures the whole stack.
  debug.sethook(co, function()
    -- We capture the time here, in an attempt to measure "slow" native functions.
    -- We may want to have a mode to ignore this, and just measure pure Lua time.
    local i, frames = 1, { time = clock("utc") }
    while true do
      local info = getinfo(i + 1, "Sn")
      if not info then break end
      frames[i] = info
      i = i + 1
    end

    stacks_n = stacks_n + 1
    stacks[stacks_n] = frames
  end, "", count)

  return co
end

-- Run our coroutine. We replace coroutine.create for the duration of that call.
local co = coroutine_create(function() return shell.execute(table.unpack(args)) end)
coroutine.create = coroutine_create
local ok, err = coroutine.resume(co, ...)
coroutine.create = native_co_create

while coroutine.status(co) ~= "dead" do
  local event = table.pack(os.pullEventRaw(err))
  if err == nil or event[1] == err or event[1] == "terminate" then
    coroutine.create = coroutine_create
    ok, err = coroutine.resume(co, table.unpack(event, 1, event.n))
    coroutine.create = native_co_create
  end
end

if not ok then printError(err) end

-- Now de-duplicate our stacks and fill in the remaining speedscope information.

local frames, frame_map, frame_n = {}, {}, 0
local function get_frame_idx(frame)
  -- Not really a great hash key, but not sure what a better one is!
  local name = ("%s\0%s"):format(frame.source, frame.linedefined)

  local frame_idx = frame_map[name]
  if frame_idx then return frame_idx end

  frame_n = frame_n + 1
  local scope_frame = {
    name = frame.name or (frame.source .. ":" .. frame.linedefined),
    file = frame.source,
    line = frame.linedefined,
  }
  frame_map[name], frames[frame_n] = frame_n, scope_frame
  return frame_n
end

for _, profile in ipairs(profiles) do
  local previous, frames, weights = profile.startValue, {}, {}
  for i, stack in ipairs(profile.stacks) do
    local new_stack = {}
    for j, frame in ipairs(stack) do new_stack[#stack - j + 1] = get_frame_idx(frame) - 1 end
    frames[i] = new_stack
    weights[i] = math.max(stack.time - previous, 1)
    previous = stack.time
  end

  profile.stacks, profile.samples, profile.weights = nil, frames, weights
  profile.endValue = math.max(profile.startValue + 1, previous)
end

-- Now finally write to a file.
local handle = fs.open(shell.resolve("speedscope.json"), "w")
handle.write(textutils.serialiseJSON {
  ["$schema"] = "https://www.speedscope.app/file-format-schema.json",
  shared = { frames = frames },
  profiles = profiles,
  name = args[1],
  exporter = "speedscope-lua@1.0.0",
})
handle.close()
