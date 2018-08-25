--- A custom ComputerCraft palette based on the zeromini theme.
--
-- One should place this within the startup directory.
--
-- @see https://github.com/SquidDev/where-the-heart-is/blob/master/.emacs.d/zeromini-theme.el

local palette = {
  [colours.black]     = "#282c34",
  [colours.blue]      = "#1f5582",
  [colours.brown]     = "#4a473d",
  [colours.cyan]      = "#61afef",
  [colours.green]     = "#98be65",
  [colours.grey]      = "#5a5a5a",
  [colours.lightBlue] = "#4174ae",
  [colours.lightGrey] = "#666666",
  [colours.lime]      = "#9eac8c",
  [colours.magenta]   = "#c678dd",
  [colours.orange]    = "#da8548",
  [colours.purple]    = "#64446d",
  [colours.red]       = "#ff6c6b",
  [colours.white]     = "#abb2bf",
  [colours.yellow]    = "#ddbd78",
}

for code, hex in pairs(palette) do
   term.setPaletteColour(code, tonumber(hex:sub(2), 16))
end
