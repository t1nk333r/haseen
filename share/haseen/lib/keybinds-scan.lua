-- keybinds-scan.lua — run the Hyprland Lua config under a stub `hl` and print
-- every described bind as
--   modmask<TAB>description<TAB>key<TAB>kind<TAB>arg<TAB>section
-- kind "exec" (arg: the command), "lua" (arg: a `hl.dsp.…(…)` expression
-- `hyprctl dispatch` accepts) or "" (a Lua function: nothing to replay).
-- section is the `-- Name ------` comment above the line that made the bind,
-- so a bind written in a loop ("Workspace " .. n) still gets its section.
--
-- Why: Hyprland 0.56 reports every Lua bind as dispatcher `__lua` with a
-- function id for an argument, and a `code:N` bind with an empty key, so
-- `hyprctl binds` alone can neither name nor run them.
--
-- usage: lua keybinds-scan.lua CONFIG
--
-- Adapted from Omarchy bin/omarchy-menu-keybindings, build_lua_bind_cache
-- (MIT, Copyright (c) David Heinemeier Hansson). Changes: a file of its own
-- instead of a heredoc, the config path as an argument, `hl.unbind` drops the
-- binds it removes (haseen.rebind), the section, and errors always go to
-- stderr.

local modifiers = { SHIFT = 1, CAPS = 2, CTRL = 4, CONTROL = 4, ALT = 8, MOD2 = 16, MOD3 = 32, SUPER = 64, MOD5 = 128 }

local function split_keys(keys)
  local modmask, key = 0, ""
  for part in string.gmatch(tostring(keys or ""), "[^+]+") do
    local value = part:gsub("^%s+", ""):gsub("%s+$", "")
    local modifier = modifiers[string.upper(value)]
    if modifier then
      modmask = modmask + modifier
    else
      key = value
    end
  end
  return modmask, key
end

local function lua_literal(value)
  local t = type(value)
  if t == "string" then
    return string.format("%q", value)
  elseif t == "number" or t == "boolean" then
    return tostring(value)
  elseif t == "table" then
    local parts, keys, n = {}, {}, #value
    for i = 1, n do
      parts[#parts + 1] = lua_literal(value[i])
    end
    for k in pairs(value) do
      if not (type(k) == "number" and k >= 1 and k <= n and math.floor(k) == k) then
        keys[#keys + 1] = k
      end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      local prefix
      if type(k) == "string" and k:match("^[%a_][%w_]*$") then
        prefix = k .. " = "
      else
        prefix = "[" .. lua_literal(k) .. "] = "
      end
      parts[#parts + 1] = prefix .. lua_literal(value[k])
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
  end
  return "nil"
end

local function dispatcher(kind, arg)
  return { __haseen_dispatcher = true, kind = kind, arg = arg }
end

local function dsp_proxy(path)
  return setmetatable({ path = path }, {
    __index = function(self, key)
      return dsp_proxy(self.path .. "." .. tostring(key))
    end,
    __call = function(self, ...)
      local first = ...
      if self.path == "hl.dsp.exec_cmd" and type(first) == "string" then
        return dispatcher("exec", first)
      end
      local args = {}
      for i = 1, select("#", ...) do
        args[i] = lua_literal(select(i, ...))
      end
      return dispatcher("lua", self.path .. "(" .. table.concat(args, ", ") .. ")")
    end,
  })
end

local noop
noop = setmetatable({}, {
  __index = function() return noop end,
  __call = function() return noop end,
})

-- In bind order; an unbind removes what an earlier bind put on the same keys.
local binds = {}

-- The nearest `-- Name -----` comment above LINE in FILE (the sheet's
-- sections, as bin/haseen-keybinds reads them).
local file_lines = {}
local function section_at(file, line)
  local lines = file_lines[file]
  if not lines then
    lines = {}
    local f = io.open(file, "r")
    if f then
      for l in f:lines() do
        lines[#lines + 1] = l
      end
      f:close()
    end
    file_lines[file] = lines
  end
  for i = math.min(line, #lines), 1, -1 do
    local name = lines[i]:match("^%s*%-%-%s*([A-Z][^-]-)%s*%-%-%-+%s*$")
    if name then
      return name
    end
  end
  return ""
end

-- The bind's call site: the first main chunk up the stack, past helpers
-- such as haseen.bind; a loop in binds.lua is still its main chunk.
local function caller_section()
  for level = 3, 32 do
    local info = debug.getinfo(level, "Sl")
    if not info then
      break
    end
    if info.what == "main" and info.source:sub(1, 1) == "@" then
      return section_at(info.source:sub(2), info.currentline)
    end
  end
  return ""
end

local function combo(keys)
  local modmask, key = split_keys(keys)
  return modmask .. "\t" .. string.upper(key), modmask, key
end

hl = setmetatable({
  dsp = dsp_proxy("hl.dsp"),
  bind = function(keys, d, opts)
    opts = opts or {}
    if type(opts) == "table" and type(opts.description) == "string" and opts.description ~= "" then
      local id, modmask, key = combo(keys)
      local kind, arg = "", ""
      if type(d) == "table" and d.__haseen_dispatcher then
        kind, arg = d.kind, d.arg
      elseif type(d) == "string" and d ~= "" then
        kind, arg = "exec", d
      end
      binds[#binds + 1] = { id = id, modmask = modmask, key = key, description = opts.description, kind = kind, arg = arg, section = caller_section() }
    end
    return noop
  end,
  unbind = function(keys)
    local id = combo(keys)
    for i = #binds, 1, -1 do
      if binds[i].id == id then
        table.remove(binds, i)
      end
    end
    return noop
  end,
  get_config = function() return nil end,
}, { __index = function() return noop end })

local config = arg and arg[1]
if not config or config == "" then
  io.stderr:write("usage: lua keybinds-scan.lua CONFIG\n")
  os.exit(2)
end

local ok, err = pcall(dofile, config)
if not ok then
  io.stderr:write("keybinds-scan: " .. tostring(err) .. "\n")
end

local function clean(s)
  return (tostring(s):gsub("[\t\n]", " "))
end

for _, b in ipairs(binds) do
  print(table.concat({ tostring(b.modmask), clean(b.description), clean(b.key), b.kind, clean(b.arg), clean(b.section) }, "\t"))
end
