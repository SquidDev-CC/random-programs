--[[-
  Maps key codes from 1.12 and before to those used by 1.13 and later.

  Usage:
    key-code-converter my_program
]]
if not fs.exists("old_keys.lua") then
  local request = http.get("https://raw.githubusercontent.com/SquidDev-CC/CC-Tweaked/master/src/main/resources/assets/computercraft/lua/rom/apis/keys.lua")
  if not request then error("Could not download keys", 0) end

  local handle = fs.open("old_keys.lua", "w")
  handle.write(request.readAll())
  handle.close()

  request.readAll()

end

local key_mapping, old_keys, new_keys = {}, {}, _G.keys
do
  local env = setmetatable({}, { __index = _G })
  loadfile("old_keys.lua", nil, env)()

  for k, v in pairs(env) do old_keys[k] = v end
end

for name, code in pairs(new_keys) do
  if type(code) == "number" then
    key_mapping[code] = old_keys[name]
  end
end

local co = coroutine.create(shell.execute)
local args = table.pack(...)

while true do
  _G.keys = old_keys
  local ok, result = coroutine.resume(co, table.unpack(args, 1, args.n))
  _G.keys = new_keys

  if not ok then printError(debug.traceback(co, result)) return end
  if coroutine.status(co) == "dead" then return end

  args = table.pack(coroutine.yield(result))
  if args[1] == "key" or args[1] == "key_up" then
    args[2] = key_mapping[args[2]] or args[2]
  end
end
