--[[
  MIT LICENSE

  Copyright (c) 2013 Enrique García Cota + Eike Decker + Jeffrey Friedl

  Permission is hereby granted, free of charge, to any person obtaining a
  copy of this software and associated documentation files (the
  "Software"), to deal in the Software without restriction, including
  without limitation the rights to use, copy, modify, merge, publish,
  distribute, sublicense, and/or sell copies of the Software, and to
  permit persons to whom the Software is furnished to do so, subject to
  the following conditions:

  The above copyright notice and this permission notice shall be included
  in all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
  OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]


-- loading this file (takes a while but grants a boost of factor 13)
-- local storing of global functions (minor speedup)
local floor, modf = math.floor,math.modf
local char,format,rep = string.char,string.format,string.rep

-- merge 4 bytes to an 32 bit word
local function bytes_to_w32(a,b,c,d) return a*0x1000000+b*0x10000+c*0x100+d end

-- shift the bits of a 32 bit word. Don't use negative values for "bits"
local function w32_rot(bits,a)
  local b2 = 2^(32-bits)
  local a,b = modf(a/b2)
  return a+b*b2*(2^(bits))
end

local band, bor, bxor, bnot = bit32.band, bit32.bor, bit32.bxor, bit32.bnot

--- adding 2 32bit numbers, cutting off the remainder on 33th bit
local function w32_add(a,b) return (a+b) % 4294967296 end

--- adding n 32bit numbers, cutting off the remainder (again)
local function w32_add_n(a,...)
  for i=1,select('#',...) do
    a = (a+select(i,...)) % 4294967296
  end
  return a
end

-- converting the number to a hexadecimal string
local function w32_to_hexstring(w) return format("%08x",w) end

-- calculating the SHA1 for some text
local function sha1(msg)
  local H0,H1,H2,H3,H4 = 0x67452301,0xEFCDAB89,0x98BADCFE,0x10325476,0xC3D2E1F0
  local msg_len_in_bits = #msg * 8

  local first_append = char(0x80) -- append a '1' bit plus seven '0' bits

  local non_zero_message_bytes = #msg +1 +8 -- the +1 is the appended bit 1, the +8 are for the final appended length
  local current_mod = non_zero_message_bytes % 64
  local second_append = current_mod>0 and rep(char(0), 64 - current_mod) or ""

  -- now to append the length as a 64-bit number.
  local B1, R1 = modf(msg_len_in_bits	/ 0x01000000)
  local B2, R2 = modf( 0x01000000 * R1 / 0x00010000)
  local B3, R3 = modf( 0x00010000 * R2 / 0x00000100)
  local B4		= 0x00000100 * R3

  local L64 = char( 0) .. char( 0) .. char( 0) .. char( 0) -- high 32 bits
        .. char(B1) .. char(B2) .. char(B3) .. char(B4) --	low 32 bits

  msg = msg .. first_append .. second_append .. L64

  assert(#msg % 64 == 0)

  local chunks = #msg / 64

  local W = { }
  local start, A, B, C, D, E, f, K, TEMP
  local chunk = 0

  while chunk < chunks do
    --
    -- break chunk up into W[0] through W[15]
    --
    start,chunk = chunk * 64 + 1,chunk + 1

    for t = 0, 15 do
      W[t] = bytes_to_w32(msg:byte(start, start + 3))
      start = start + 4
    end

    --
    -- build W[16] through W[79]
    --
    for t = 16, 79 do
      -- For t = 16 to 79 let Wt = S1(Wt-3 XOR Wt-8 XOR Wt-14 XOR Wt-16).
      W[t] = w32_rot(1, bxor(W[t-3], W[t-8], W[t-14], W[t-16])) -- TODO: bxor many
    end

    A,B,C,D,E = H0,H1,H2,H3,H4

    for t = 0, 79 do
      if t <= 19 then
        -- (B AND C) OR ((NOT B) AND D)
        f = bor(band(B, C), band(bnot(B), D))
        K = 0x5A827999
      elseif t <= 39 then
        -- B XOR C XOR D
        f = bxor(B, C, D) -- TODO: bxor many
        K = 0x6ED9EBA1
      elseif t <= 59 then
        -- (B AND C) OR (B AND D) OR (C AND D)
        f = bor(band(B, C), band(B, D), band(C, D)) -- TODO: bor many
        K = 0x8F1BBCDC
      else
        -- B XOR C XOR D
        f = bxor(B, C, D) -- TODO: bxor many
        K = 0xCA62C1D6
      end

      -- TEMP = S5(A) + ft(B,C,D) + E + Wt + Kt;
      A,B,C,D,E = w32_add_n(w32_rot(5, A), f, E, W[t], K), A, w32_rot(30, B), C, D
    end
    -- Let H0 = H0 + A, H1 = H1 + B, H2 = H2 + C, H3 = H3 + D, H4 = H4 + E.
    H0,H1,H2,H3,H4 = w32_add(H0, A),w32_add(H1, B),w32_add(H2, C),w32_add(H3, D),w32_add(H4, E)
  end

  local f = w32_to_hexstring
  return f(H0) .. f(H1) .. f(H2) .. f(H3) .. f(H4)
end

return sha1
