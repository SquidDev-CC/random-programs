local helpers = require "helpers"
local root = fs.combine(fs.getDir(shell.getRunningProgram()), "challenges")

local function randomise(str)
  return str:gsub("${([^}]*)}", function(body)
    local candidates = {}
    for candidate in body:gmatch("([^|]*)|?") do
      candidates[#candidates + 1] = candidate
    end

    return candidates[math.random(1, #candidates)]
  end)
end

return function(name)
  local path = fs.combine(root, name)

  local template, err = helpers.read_file(path .. '.txt')
  if not template then error(err, 2) end

  local cipher = helpers.do_file(path .. ".lua")

  local data = {}
  local results_path = path .. ".results"
  local contents = helpers.read_file(results_path)
  if contents then data = textutils.unserialise(contents) end

  local function save()
    helpers.write_file(results_path, textutils.serialise(data))
  end

  return {
    name = name,

    has_player = function(player)
      return data[player.id] ~= nil
    end,

    has_player_submitted = function(player)
      local info = data[player.id]
      return info and info.finished
    end,

    generate = function(player)
      local info = data[player.id]
      if not info then
        local key = cipher.key()
        local plaintext = randomise(template)
        local ciphertext = cipher.encrypt(plaintext, key)

        data[player.id] = {
          name = player.name,
          started = os.epoch('utc'),
          plaintext = plaintext,
          ciphertext = ciphertext
        }

        save()
        return ciphertext
      elseif info.finished then
        error("Player has already submitted", 2)
      else
        return info.ciphertext
      end
    end,

    submit = function(player, plaintext)
      local info = data[player.id]
      if not info then error("No such player!", 2) end
      if info.finished then error("Player has already submitted", 2) end

      if cipher.strip(info.plaintext) == cipher.strip(plaintext) then
        info.name = player.name
        info.finished = os.epoch('utc')
        save()
        return true
      else
        return false
      end
    end,

    submissions = function()
      local out = {}
      for _, info in pairs(data) do
        if info.finished then
          table.insert(out, {
            name = info.name,
            time = info.finished - info.started
          })
        end
      end

      table.sort(out, function(a, b) return a.time < b.time end)

      return out
    end
  }
end
