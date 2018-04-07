local challenge = require 'challenge'

local current_challenge = challenge 'challenge_01'

for _, player in pairs(current_challenge.submissions()) do
  print(("%15s | %.3f"):format(player.name, player.time / 1000 / 60))
end
