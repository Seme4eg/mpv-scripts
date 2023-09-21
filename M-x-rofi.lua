local mp = require 'mp' -- isn't actually required, mp still gonna be defined
local utils = require 'mp.utils'

-- NOTE: should not be altered here, edit options in corresponding .conf file
local opts = {
  strip_cmd_at = 65,
  sort_commands_by = 'priority',
  toggle_menu_binding = 't',
  pause_on_open = true,
  resume_on_exit = "only-if-was-paused", -- another possible value is true
}

(require 'mp.options').read_options(opts, mp.get_script_name())

local data = {
  list = {},          -- list of all commands (tables)
  lines = {},         -- command tables brought to pango markup strings concat with '\n'
  was_paused = false, -- flag that indicates that vid was paused by this script
}

local function sort_cmd_list()
  table.sort(data.list, function(i, j)
    if opts.sort_commands_by == 'priority' then
      return tonumber(i.priority) > tonumber(j.priority)
    end
    -- sort by command name by default
    return i.cmd < j.cmd
  end)
end

local function get_line(v)
  local cmd = v.cmd
  local a = ''

  local function escape_pango(text)
    local escapedText = text:gsub("[&<>]", {
      ["&"] = "&amp;",
      ["<"] = "&lt;",
      [">"] = "&gt;"
    })
    return escapedText
  end

  if #cmd > opts.strip_cmd_at then
    cmd = string.sub(cmd, 1, opts.strip_cmd_at - 3) .. '...'
  end

  a = cmd .. ' <b>(' .. escape_pango(v.key) .. ')</b> '

  -- handle inactive keybindings
  if v.shadowed or v.priority == -1 then
    local why_inactive = (v.priority == -1)
        and 'inactive keybinding'
        or 'that binding is currently shadowed by another one'
    a = '<span alpha="50%">' .. a .. '(' .. why_inactive .. ')</span>'
    return a
  end

  if v.comment then
    a = a .. '<span alpha="50%">' .. v.comment .. '</span>'
  end
  return a
end

local function form_lines()
  for _, v in ipairs(data.list) do
    table.insert(data.lines, get_line(v))
  end
end

local function get_cmd_list()
  local bindings = mp.get_property_native("input-bindings")

  -- sets a flag 'shadowed' to all binding that have a binding with higher
  -- priority using same key binding
  for _, v in ipairs(bindings) do
    for _, v1 in ipairs(bindings) do
      if v.key == v1.key and v.priority < v1.priority then
        v.shadowed = true
        break
      end
    end
  end

  data.list = bindings

  sort_cmd_list()
  form_lines()
end

local function merge_leader_bindings(le, leader_key)
  -- REVIEW: sadly mpvs 'input-bindings' is read only and i can't force set
  -- priority -1 for bindings that are overwritten by leader bindings.
  -- Since leader script needs keybinding to be defined in 'input-bindings'.
  -- Therefore i just merge those leader bindings in my own 'data.list'.

  local bindings_to_append = {}

  local function split_with_spaces(str)
    local result_str = ''
    for char in str:gmatch '.' do result_str = result_str .. char .. ' ' end
    -- REVIEW: needed?
    return result_str:gsub("(.-)%s*$", "%1") -- strip spaces
  end

  for _, lb in ipairs(le) do
    -- overwriting binding in data.list
    for y, b in ipairs(data.list) do
      if b.cmd:find(lb.cmd, 1, true) then
        data.list[y].priority = 13
        data.list[y].key = leader_key .. ' ' .. split_with_spaces(lb.key)
        -- if it's a script binding - initially it won't have comment field
        -- but leader binding can (and should) have comment field, so we set it
        -- and if it is normal keybinding and it had it's own comment field then
        -- leave it as it was
        data.list[y].comment = lb.comment or data.list[y].comment
        goto continue1
      end

      -- if binding was not found - append it to list
      if y == #data.list then
        local binding = {}

        binding.priority = 13
        binding.key = leader_key .. ' ' .. split_with_spaces(lb.key)
        binding.cmd = lb.cmd
        -- if it's a script binding - initially it won't have comment field
        -- but leader binding can (and should) have comment field, so we set it
        -- and if it is normal keybinding and it had it's own comment field then
        -- leave it as it was
        binding.comment = lb.comment

        table.insert(bindings_to_append, binding)
      end
    end
    ::continue1::
  end

  for _, v in ipairs(bindings_to_append) do table.insert(data.list, v) end

  sort_cmd_list()

  -- TODO: handle warning about not found leader kbd better
  -- for i,v in ipairs(not_found_leader_kbds) do
  --   print(v, 'not found')
  -- end
end

-- and register them in script itself
mp.register_script_message("merge-leader-bindings", function(bindings, leader_key)
  bindings = utils.parse_json(bindings)
  merge_leader_bindings(bindings, leader_key)
end)

-- NOTE: when using external tool to view list it is necessary to reopen it
-- when command list updates to see changes
local function update_bindings()
  get_cmd_list()
  mp.commandv("script-message-to", "leader", "leader-bindings-request")
end

mp.observe_property('input-bindings', 'native', update_bindings)

get_cmd_list()

-- keybind to launch menu
mp.add_key_binding(opts.toggle_menu_binding, "M-x-rofi", function()
  -- set flag 'was_paused' only if vid wasn't paused before EM init
  if opts.pause_on_open and not mp.get_property_bool("pause", false) then
    mp.set_property_bool("pause", true)
    data.was_paused = true
  end

  local rofi = mp.command_native({
    name = "subprocess",
    args = { "rofi", "-dmenu", "-i", "-markup-rows" },
    capture_stdout = true,
    playback_only = false,
    stdin_data = table.concat(data.lines, "\n"),
  })
  if rofi.status == 0 then
    local command = string.match(rofi.stdout, "(.-)<")
    mp.msg.info(command)
    mp.command(command)
  end

  if opts.resume_on_exit == true or
      (opts.resume_on_exit == "only-if-was-paused" and data.was_paused) then
    mp.set_property_bool("pause", false)
  end
end)
