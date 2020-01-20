--- The tinest and worst debugger
--
-- Run as "buggerit PROGRAM [ARGS...]". If your program crashes _on the top
-- level_, then we'll start a Lua REPL with access to all locals, so you can
-- inspect the current stack.

local expect = require "cc.expect".expect

local function gather_info(co, level)
  expect(1, co, "thread")
  expect(2, level, "number", "nil")
  if not level then level = 0 end

  local info = debug.getinfo(co, level)
  local locals, upvalues, vars = {}, {}, {}

  for i = 1, info.nups do
    local name, value = debug.getupvalue(info.func, i)
    if name then
      local var = { tag = "upvalue", name = name, value = value, slot = i, func = info }
      table.insert(upvalues, var)
      vars[name] = var
    end
  end

  for i = 1, 250 do
    local name, value = debug.getlocal(co, level, i)
    if name then
      local var = { tag = "local", name = name, value = value, slot = i, func = info }
      table.insert(locals, var)
      vars[name] = var
    end
  end

  info.locals = locals
  info.upvalues = upvalues
  info.vars = vars
  return info
end

local function load_program(file, env)
  local dir = fs.getDir(file)

  local package = env.package
  package.loaded = {}
  package.preload = {}
  package.loaders = {
    function(name)
      if package.preload[name] then
        return package.preload[name]
      else
        return nil, "no field package.preload['" .. name .. "']"
      end
    end,
    function(name)
      local fname = string.gsub(name, "%.", "/")
      local errors = {}
      for pattern in string.gmatch(package.path, "[^;]+") do
        local path = string.gsub(pattern, "%?", fname)
        if path:sub(1, 1) ~= "/" then path = fs.combine(dir, path) end

        if fs.exists(path) and not fs.isDir(path) then
          local fn, error = loadfile( path, nil, env)
          if fn then
            return fn, path
          else
            return nil, error
          end
        else
          table.insert(errors, "no file '" .. path .. "'")
        end
      end

      return nil, table.concat(errors, "\n  ")
    end,
  }

  return loadfile(file, nil, env)
end

local program = ...
if not program then
  printError(("%s PROGRAM [ARGS...]"):format(shell.getRunningProgram()))
  error()
end

local file = shell.resolveProgram(program)
if not file then
  printError(("Cannot find %q"):format(program))
  error()
end

local fn, error = load_program(file, _ENV)
if not fn then
  printError(error)
  error()
end

local co = coroutine.create(fn)
local event, event_filter = table.pack(select(2, ...)), nil

local ok, result
repeat
  if event_filter == nil or event[1] == "terminate" or event[1] == event_filter then
    ok, result = coroutine.resume(co, table.unpack(event, 1, event.n))
    if not ok then break end
  end

  event = table.pack(coroutine.yield())
until coroutine.status(co) == "dead"
-- If we had no issues, or we had error() then just exit.
if ok or result == nil then return end

printError(debug.traceback(co, tostring(result)))

local info = gather_info(co)
local env = setmetatable({}, {
  __index = function(_, k)
    local var = info.vars[k]
    if var then return var.value end

    return _ENV[k]
  end
})

local lua_file = shell.resolveProgram("lua") or "/rom/programs/lua.lua"
local lua_shell = load_program(lua_file, env)
if not lua_shell then
  printError(err)
  error()
end

return lua_shell()
