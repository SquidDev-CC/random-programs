local helpers = require "helpers"
local screen = require 'screen'
local challenge = require 'challenge'

local config = helpers.do_file(fs.combine(shell.getRunningProgram(), "../config.lua"))

local entity_blacklist = {
  "Item", "XPOrb",
  "Creeper", "Zombie", "Skeleton",
  "Cow", "Sheep", "Chicken"
}
for i = 1, #entity_blacklist do entity_blacklist[entity_blacklist[i]] = true end

local manipulator = peripheral.find("manipulator")
  or error("Cannot find manipulator", 0)

local primary_screen = screen(config.primary_monitor, 'main_screen', { challenge = 1})
local secondary_screen = screen(config.secondary_monitor, 'disk_nobody')
local drive = peripheral.wrap(config.drive) or error("Cannot find drive", 0)

local current_challenge = challenge 'challenge_01'

local player_count, player = 0, nil
local last_player, last_disk = false, false
local function update_drive()
  if player_count ~= 1 then return end

  local mount = drive.getMountPath()
  if not mount then return end

  if current_challenge.has_player_submitted(player) then
    secondary_screen.set 'disk_submit_already'
    return
  end

  local cipher_path = fs.combine(mount, current_challenge.name .. '.txt')
  local plain_path = fs.combine(mount, current_challenge.name .. '_answer.txt')

  if not current_challenge.has_player(player) then
    -- If they've not got the challenge then let's begin
    local cipher = current_challenge.generate(player)
    helpers.write_file(cipher_path, cipher)
    secondary_screen.set('disk_go', { path = current_challenge.name })
    return
  end

  if fs.exists(plain_path) and not fs.isDir(plain_path) then
    local plaintext, err = helpers.read_file(plain_path)
    if plaintext then
      local ok = current_challenge.submit(player, plaintext)
      if ok then
        secondary_screen.set 'disk_submit_correct'
      else
        secondary_screen.set 'disk_submit_incorrect'
      end

      return
    end
  end

  -- Override the cipher again, just in case
  local cipher = current_challenge.generate(player)
  helpers.write_file(cipher_path, cipher)

  -- And display a failing message
  secondary_screen.set('disk_submit_missing', { path = current_challenge.name .. '_answer' })
end

local entity_timer = os.startTimer(config.entity_delay)
while true do
  local event, arg1 = os.pullEvent()

  if event == "timer" and arg1 == entity_timer then
    local previous = player_count == 1 and player
    player_count, player = 0, nil
    for _, entity in pairs(manipulator.sense()) do
      if not entity_blacklist[entity.name] and
         entity.x >= config.box.x[1] and entity.x <= config.box.x[2] and
         entity.y >= config.box.y[1] and entity.y <= config.box.y[2] and
         entity.z >= config.box.z[1] and entity.z <= config.box.z[2] then

        player_count = player_count + 1
        player = { name = entity.name, id = entity.id }
      end
    end

    if player_count == 0 then
      secondary_screen.set 'disk_nobody'
    elseif player_count > 1 then
      secondary_screen.set 'disk_many'
    elseif not helpers.eq(previous, player) then
      secondary_screen.set('disk_somebody', player)
    end

    entity_timer = os.startTimer(config.entity_delay)
    update_drive()
    drive.ejectDisk()
  elseif event == "disk" then
    update_drive()
    drive.ejectDisk()
  end
end
