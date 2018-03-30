local function eq(a, b)
  if a == b then return true end

  local tya = type(a)
  if tya ~= "table" or tya ~= type(b) then return false end

  for k, v in pairs(a) do
    if not eq(v, b[k]) then return false end
  end

  for k, v in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

return {
  read_file = function(path)
    local handle, err = fs.open(path, "r")
    if not handle then return handle, err or "Cannot open " .. path end

    local contents = handle.readAll()
    handle.close()
    return contents
  end,

  write_file = function(path, contents)
    local handle, err = fs.open(path, "w")
    if not handle then return handle, err or "Cannot open " .. path end

    handle.write(contents)
    handle.close()
  end,

  do_file = function(path, env)
    local fn, err = loadfile(path, env or _ENV)
    if not fn then error(err, 2) end

    return fn()
  end,

  eq = eq,
}
