local utils = require 'mp.utils'
local options = require 'mp.options'

local shaders_dir = mp.command_native({"expand-path", "~~/shaders/"})

local function get_paths(dir)
  local result = {}
  local ls = utils.readdir(shaders_dir)
  for i, child in pairs(ls) do
    local info = utils.file_info(shaders_dir .. "/" .. child);
    if info.is_dir then
      for _, grandchild in pairs(get_paths(shaders_dir .. "/" .. child)) do
        result[#result + 1] = grandchild
      end
    elseif string.match(child, "%.glsl$") or string.match(child, "%.hook$") then
      result[#result + 1] = shaders_dir .. "/" .. child
    end
  end
  return result
end

local function get_rofi_choice(lines)
  local rofi = mp.command_native({
    name = "subprocess",
    args = { "rofi", "-dmenu", "-i" },
    capture_stdout = true,
    playback_only = false,
    stdin_data = table.concat(lines, "\n"),
  })
  return rofi.stdout, rofi.status
end

local function handler()
  -- mp.get_property_native("glsl-shaders")
	local paths = get_paths(shaders_dir)
  local names = {}
  for _, path in ipairs(paths) do
    table.insert(names, string.match(path, "[^/]+$"))
  end

  local shader, status = get_rofi_choice(names)
  if status == 0 and shader then
    shader = shader:gsub("^%s*(.-)%s*$", "%1")
    mp.commandv("change-list", "glsl-shaders", "set", shaders_dir .. shader)
  end
end

mp.add_key_binding("Ctrl+s", "shaders-rofi", handler)
