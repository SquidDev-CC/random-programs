local inflate_zlib = require "deflate".inflate_zlib
local sha = require "sha1"

local band, bor, lshift, rshift = bit32.band, bit32.bor, bit32.lshift, bit32.rshift
local byte, format, sub = string.byte, string.format, string.sub

local types = { [0] = "none", "commit", "tree", "blob", "tag", nil, "ofs_delta", "ref_delta", "any", "max" }

--- Get the type of a specific object
-- @tparam Object x The object to get the type of
-- @treturn string The object's type.
local function get_type(x) return types[x.ty] or "?" end

local event = ("luagit-%08x"):format(math.random(0, 2^24))
local function check_in()
  os.queueEvent(event)
  os.pullEvent(event)
end

local sha_format = ("%02x"):rep(20)

local function reader(str)
  local expected_checksum = format(sha_format, byte(str, -20, -1))
  local actual_checksum = sha(str:sub(1, -21));
  if expected_checksum ~= actual_checksum then
    error(("checksum mismatch: expected %s, got %s"):format(expected_checksum, actual_checksum))
  end

  str = str:sub(1, -20)

  local pos = 1

  local function consume_read(len)
    if len <= 0 then error("len < 0", 2) end
    if pos > #str then error("end of stream") end

    local cur_pos = pos
    pos = pos + len
    local res = sub(str, cur_pos, pos - 1)
    if #res ~= len then error("expected " .. len .. " bytes, got" .. #res) end
    return res
  end

  local function read8()
    if pos > #str then error("end of stream") end
    local cur_pos = pos
    pos = pos + 1
    return byte(str, cur_pos)
  end

  return {
    offset = function() return pos - 1 end,
    read8 = read8,
    read16 = function() return (read8() * (2^8)) + read8() end,
    read32 = function() return (read8() * (2^24)) + (read8() * (2^16)) + (read8() * (2^8)) + read8() end,
    read = consume_read,

    close = function()
      if pos ~= #str then error(("%d of %d bytes remaining"):format(#str - pos + 1, #str)) end
    end,
  }
end

--- Consume a string from the given input buffer
--
-- @tparam Reader handle The handle to read from
-- @tparam number size The number of decompressed bytes to read
-- @treturn string The decompressed data
local function get_data(handle, size)
  local tbl, n = {}, 1

  inflate_zlib {
    input = handle.read8,
    output = function(x) tbl[n], n = string.char(x), n + 1 end
  }

  local res = table.concat(tbl)
  if #res ~= size then error(("expected %d decompressed bytes, got %d"):format(size, #res)) end
  return res
end

--- Decode a binary delta file, applying it to the original
--
-- The format is described in more detail in [the Git documentation][git_pack]
--
-- [git_pack]: https://git-scm.com/docs/pack-format#_deltified_representation
--
-- @tparam string original The original string
-- @tparam string delta The binary delta
-- @treturn string The patched string
local function apply_delta(original, delta)
  local delta_offset = 1
  local function read_size()
    local c = byte(delta, delta_offset)
    delta_offset = delta_offset + 1

    local size = band(c, 0x7f)
    local shift = 7
    while band(c, 0x80) ~= 0 do
      c, delta_offset = byte(delta, delta_offset), delta_offset + 1
      size, shift = size + lshift(band(c, 0x7f), shift), shift + 7
    end

    return size
  end

  local original_length = read_size()
  local patched_length = read_size()
  if original_length ~= #original then
    error(("expected original of size %d, got size %d"):format(original_length, #original))
  end

  local parts, n = {}, 1
  while delta_offset <= #delta do
    local b = byte(delta, delta_offset)
    delta_offset = delta_offset + 1

    if band(b, 0x80) ~= 0 then
      -- Copy from the original file. Each bit represents which optional length/offset
      -- bits are used.
      local offset, length = 0, 0

      if band(b, 0x01) ~= 0 then
        offset, delta_offset = bor(offset, byte(delta, delta_offset)), delta_offset + 1
      end
      if band(b, 0x02) ~= 0 then
        offset, delta_offset = bor(offset, lshift(byte(delta, delta_offset), 8)), delta_offset + 1
      end
      if band(b, 0x04) ~= 0 then
        offset, delta_offset = bor(offset, lshift(byte(delta, delta_offset), 16)), delta_offset + 1
      end
      if band(b, 0x08) ~= 0 then
        offset, delta_offset = bor(offset, lshift(byte(delta, delta_offset), 24)), delta_offset + 1
      end

      if band(b, 0x10) ~= 0 then
        length, delta_offset = bor(length, byte(delta, delta_offset)), delta_offset + 1
      end
      if band(b, 0x20) ~= 0 then
        length, delta_offset = bor(length, lshift(byte(delta, delta_offset), 8)), delta_offset + 1
      end
      if band(b, 0x40) ~= 0 then
        length, delta_offset = bor(length, lshift(byte(delta, delta_offset), 16)), delta_offset + 1
      end
      if length == 0 then length = 0x10000 end

      parts[n], n = sub(original, offset + 1, offset + length), n + 1
    elseif b > 0 then
      -- Copy from the delta. The opcode encodes the length
      parts[n], n = sub(delta, delta_offset, delta_offset + b - 1), n + 1
      delta_offset = delta_offset + b
    else
      error(("unknown opcode '%02x'"):format(b))
    end
  end

  local patched = table.concat(parts)
  if patched_length ~= #patched then
    error(("expected patched of size %d, got size %d"):format(patched_length, #patched))
  end

  return patched
end

--- Unpack a single object, populating the output table
--
-- @tparam Reader handle The handle to read from
-- @tparam { [string] = Object } out The populated data
local function unpack_object(handle, out)
  local c = handle.read8()
  local ty = band(rshift(c, 4), 7)
  local size = band(c, 15)
  local shift = 4
  while band(c, 0x80) ~= 0 do
    c = handle.read8()
    size = size + lshift(band(c, 0x7f), shift)
    shift = shift + 7
  end

  local data
  if ty >= 1 and ty <= 4 then
    -- commit/tree/blob/tag
    data = get_data(handle, size)
  elseif ty == 6 then
    -- ofs_delta
    data = get_data(handle, size)
    error("ofs_delta not yet implemented")

  elseif ty == 7 then
    -- ref_delta
    local base_hash = sha_format:format(handle.read(20):byte(1, 20))
    local delta = get_data(handle, size)

    local original = out[base_hash]
    if not original then error(("cannot find object %d to apply diff"):format(base_hash)) return end
    ty = original.ty
    data = apply_delta(original.data, delta)
  else
    error(("unknown object of type '%d'"):format(ty))
  end

  -- We've got to do these separately. Format doesn't like null bytes
  local whole = ("%s %d\0"):format(types[ty], #data) .. data
  local sha = sha(whole)
  out[sha] = { ty = ty, data = data, sha = sha }
end

local function unpack(handle, progress)
  local header = handle.read(4)
  if header ~= "PACK" then error("expected PACK, got " .. header, 0) end

  local version = handle.read32()
  local entries = handle.read32()

  local out = {}
  for i = 1, entries do
    if progress then progress(i, entries) end
    check_in()

    unpack_object(handle, out)
  end

  return out
end

local function build_tree(objects, object, prefix, out)
  if not prefix then prefix = "" end
  if not out then out = {} end

  local idx = 1

  while idx <= #object do
    -- dddddd NAME\0<SHA>
    local _, endidx, mode, name = object:find("^(%x+) ([^%z]+)%z", idx)
    if not endidx then break end
    name = prefix .. name

    local sha = object:sub(endidx + 1, endidx + 20):gsub(".", function(x) return ("%02x"):format(string.byte(x)) end)

    local entry = objects[sha]
    if not entry then error(("cannot find %s %s (%s)"):format(mode, name, sha)) end
    entry = { ty = 3; data = "" }

    if entry.ty == 3 then
      out[name] = entry.data
    elseif entry.ty == 2 then
      build_tree(objects, entry.data, name .. "/", out)
    else
      error("unknown type for " .. name .. " (" .. sha .. "): " .. get_type(entry))
    end

    idx = endidx + 21
  end

  return out
end

local function build_commit(objects, sha)
  local commit = objects[sha]
  if not commit then error("cannot find commit " .. sha) end
  if commit.ty ~= 1 then error("Expected commit, got " .. types[commit.ty]) end

  local tree_sha = commit.data:match("tree (%x+)\n")
  if not tree_sha then error("Cannot find tree from commit") end

  local tree = objects[tree_sha]
  if not tree then error("cannot find tree " .. tree_sha) end
  if tree.ty ~= 2 then error("Expected tree, got " .. tree[tree.ty]) end

  return build_tree(objects, tree.data)
end

return {
  reader = reader,
  unpack = unpack,
  build_tree = build_tree,
  build_commit = build_commit,
  type = get_type,
}
