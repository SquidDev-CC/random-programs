--- Git clone in Lua, from the bottom up
--
-- http://stefan.saasen.me/articles/git-clone-in-haskell-from-the-bottom-up/#the_clone_process
-- https://github.com/creationix/lua-git

local network = require "network"
local objects = require "objects"

local url, name = ...
if not url or url == "-h" or url == "--help" then error("clone.lua URL [name]", 0) end

if url:sub(-1) == "/" then url = url:sub(1, -2) end
name = name or fs.getName(url):gsub("%.git$", "")

local destination = shell.resolve(name)
if fs.exists(destination) then
  error(("%q already exists"):format(name), 0)
end

local function report(msg)
  local last = ""
  for line in msg:gmatch("[^\n]+") do last = line end
  term.setCursorPos(1, select(2, term.getCursorPos()))
  term.clearLine()
  term.write(last)
end

local head
do -- Request a list of all refs
  report("Cloning from " .. url)

  local handle = network.force_fetch(url .. "/info/refs?service=git-upload-pack")
  local res = network.receive(handle)

  local sha_ptrn = ("%x"):rep(40)

  local caps = {}
  local refs = {}
  for i = 1, #res do
    local line = res[i]
    if line ~= false and line:sub(1, 1) ~= "#" then
      local sha, name = line:match("(" .. sha_ptrn .. ") ([^%z\n]+)")
      if sha and name then
        refs[name] = sha

        local capData = line:match("%z([^\n]+)\n")
        if capData then
          for cap in (capData .. " "):gmatch("%S+") do
            local eq = cap:find("=")
            if eq then
              caps[cap:sub(1, eq - 1)] = cap:sub(eq + 1)
            else
              caps[cap] = true
            end
          end
        end
      else
        printError("Unexpected line: " .. line)
      end
    end
  end
  head = refs['HEAD'] or refs['refs/heads/master'] or error("Cannot find master", 0)

  if not caps['shallow'] then error("Server does not support shallow fetching", 0) end

  -- TODO: Handle both. We don't even need the side-band really?
  if not caps['side-band-64k'] then error("Server does not support side band", 0) end
end

do -- Now actually perform the clone
  local handle = network.force_fetch(url .. "/git-upload-pack", {
    network.pkt_linef("want %s side-band-64k shallow", head),
    network.pkt_linef("deepen 1"),
    network.flush_line,
    network.pkt_linef("done"),
  }, "application/x-git-upload-pack-request")

  local pack, head = {}, nil
  while true do
    local line = network.read_pkt_line(handle)
    if line == nil then break end

    if line == false or line == "NAK\n" then
      -- Skip
    elseif line:byte(1) == 1 then
      table.insert(pack, line:sub(2))
    elseif line:byte(1) == 2 or line:byte(1) == 3 then
      report(line:sub(2):gsub("\r", "\n"))
    elseif line:find("^shallow ") then
      head = line:sub(#("shallow ") + 1)
    else
      printError("Unknown line: " .. tostring(line))
    end
  end
  handle.close()

  local stream = objects.reader(table.concat(pack))
  local objs = objects.unpack(stream, function(x, n)
    report(("Extracting %d/%d (%.2f%%)"):format(x, n, x/n*100))
  end)
  stream.close()

  if not head then error("Cannot find HEAD commit", 0) end

  for k, v in pairs(objects.build_commit(objs, head)) do
    local out = fs.open(fs.combine(destination, fs.combine(k, "")), "wb")
    out.write(v)
    out.close()
  end
end

report(("Cloned to %q"):format(name))
print()
