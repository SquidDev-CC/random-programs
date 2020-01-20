--- This renders a minimap showing nearby ores using the overlay glasses and block scanner.

--- We start the program by specifying a series of configuration options. Feel free to ignore these, and use the values
--- inline. Whilst you don't strictly speaking need a delay between each iteration, it does reduce the impact on the
--- server.

--- It's worth noting, that a more elegant solution here would be to run the scanning and meta updates in sync, and then
-- recentre the blocks + update them. But this code is anything but elegant.
local scanInterval = 0.2
local renderInterval = 0.2
local scannerRange = 8

--- We end our on figuration section by defining the ores we're interested in and what colour we'll draw them as. We
--- define some ores as having a higher priority, so large ore veins don't mask smaller veins of more precious ores.
local ores = {
  ["minecraft:diamond_ore"] = 10,
  ["minecraft:emerald_ore"] = 10,

  ["minecraft:gold_ore"] = 8,

  ["minecraft:redstone_ore"] = 5,
  ["minecraft:lapis_ore"] = 5,
  ["minecraft:iron_ore"] = 2,
  ["minecraft:coal_ore"] = 1,
}

local colours = {
  ["minecraft:coal_ore"] = { 150, 150, 150 },
  ["minecraft:iron_ore"] = { 255, 150, 50 },
  ["minecraft:lava"] = { 150, 75, 0 },
  ["minecraft:gold_ore"] = { 255, 255, 0 },
  ["minecraft:diamond_ore"] = { 0, 255, 255 },
  ["minecraft:redstone_ore"] = { 255, 0, 0 },
  ["minecraft:lapis_ore"] = { 0, 50, 255 },
  ["minecraft:emerald_ore"] = { 0, 255, 0 },
}

--- Now let's get into the interesting stuff! Let's look for a neural interface and check we've got all the required
--- modules.
local modules = peripheral.find("neuralInterface")
if not modules then error("Must have a neural interface", 0) end
if not modules.hasModule("plethora:scanner") then error("The block scanner is missing", 0) end
if not modules.hasModule("plethora:glasses") then error("The overlay glasses are missing", 0) end

--- Now we've got our neural interface, let's extract the canvas and ensure nothing else is on it.
local root = modules.canvas3d()
root.clear()

local canvas = root.create()

local boxes = {}
for x = -scannerRange, scannerRange, 1 do
  boxes[x] = {}

  for y = -scannerRange, scannerRange, 1 do
    boxes[x][y] = {}

    for z = -scannerRange, scannerRange, 1 do
      boxes[x][y][z] = canvas.addBox(x, y, z, 0)
      boxes[x][y][z].setDepthTested(false)
    end
  end
end

--- Our first big function is the scanner: this searches for ores near the player, finds the most important ones, and
--- updates the block table.
local function scan()
  while true do
    local scanned_blocks = modules.scan()

    --- For each nearby position, we search the y axis for interesting ores. We look for the one which has
    --- the highest priority and update the block information
    for i = 1, #scanned_blocks do
      local block = scanned_blocks[i]
      local box = boxes[block.x][block.y][block.z]
      if ores[block.name] then
        box.setColor(table.unpack(colours[block.name]))
        box.setAlpha(255 / (1 + math.sqrt(block.x * block.x + block.y * block.y + block.z * block.z)))
      else
        box.setAlpha(0)
      end
    end

    --- We wait for some delay before starting again. This isn't _strictly_ needed, but helps reduce server load
    sleep(scanInterval)
  end
end

--- The render function takes our block information generated in the previous function and updates the text elements.
local function render()
  while true do
    local meta = modules.getMetaOwner and modules.getMetaOwner()
    if meta then
      local within = meta.withinBlock
      canvas.recenter({-within.x, -within.y, -within.z})
    else
      printError("Cannot find an entity")
    end

    sleep(renderInterval)
  end
end

--- We now run our render and scan loops in parallel, continually updating our block list and redisplaying it to the
--- wearer.
parallel.waitForAll(render, scan)
