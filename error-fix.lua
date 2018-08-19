local mt, void = {}, function() return nil end
local methods = {
  "__call", "__index", "__newindex",
  "__len", "__unm",
  "__add", "__sub", "__mul", "__div", "__pow",
  "__concat",
}
for _, method in ipairs(methods) do mt[method] = void end
debug.setmetatable(nil, mt)
