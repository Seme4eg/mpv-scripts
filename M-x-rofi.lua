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

local mx = {
  list = {},          -- list of all commands (tables)
  lines = {},         -- command tables brought to pango markup strings concat with '\n'
  was_paused = false, -- flag that indicates that vid was paused by this script
}

function mx:init()
  setmetatable({}, self)
  self.__index = self

  self:get_cmd_list()
  self:sort_cmd_list()
  self:form_lines()

  -- keybind to launch menu
  mp.add_key_binding(opts.toggle_menu_binding, "M-x-rofi", function()
    self:handler()
  end)
end

function mx:get_cmd_list()
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

  self.list = bindings
end

function mx:sort_cmd_list()
  table.sort(self.list, function(i, j)
    if opts.sort_commands_by == 'priority' then
      return tonumber(i.priority) > tonumber(j.priority)
    end
    -- sort by command name by default
    return i.cmd < j.cmd
  end)
end

function mx:form_lines()
  for _, v in ipairs(self.list) do
    table.insert(self.lines, self:get_line(v))
  end
end

function mx:get_line(v)
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

function mx:merge_leader_bindings(le, leader_key)
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
    for y, b in ipairs(self.list) do
      if b.cmd:find(lb.cmd, 1, true) then
        self.list[y].priority = 13
        self.list[y].key = leader_key .. ' ' .. split_with_spaces(lb.key)
        -- if it's a script binding - initially it won't have comment field
        -- but leader binding can (and should) have comment field, so we set it
        -- and if it is normal keybinding and it had it's own comment field then
        -- leave it as it was
        self.list[y].comment = lb.comment or self.list[y].comment
        goto continue1
      end

      -- if binding was not found - append it to list
      if y == #self.list then
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

  for _, v in ipairs(bindings_to_append) do table.insert(self.list, v) end

  -- TODO: handle warning about not found leader kbd better
  -- for i,v in ipairs(not_found_leader_kbds) do
  --   print(v, 'not found')
  -- end
end

function mx:handler()
  local function update_bindings()
    mx:get_cmd_list()
    self:sort_cmd_list()
    self:form_lines()
    mp.commandv("script-message-to", "leader", "leader-bindings-request")
  end

  -- set flag 'was_paused' only if vid wasn't paused before EM init
  if opts.pause_on_open and not mp.get_property_bool("pause", false) then
    mp.set_property_bool("pause", true)
    self.was_paused = true
  end

  -- NOTE: when using external tool to view list it is necessary to reopen it
  -- when command list updates to see changes
  mp.observe_property('input-bindings', 'native', update_bindings)

  self:register_script_message()

  local command, status = self:get_rofi_choice()
  if status == 0 and command then
    mp.command(string.match(command, "(.-)<"))
  end

  self:unregister_script_message()

  mp.unobserve_property(update_bindings)

  if opts.resume_on_exit == true or
      (opts.resume_on_exit == "only-if-was-paused" and self.was_paused) then
    mp.set_property_bool("pause", false)
  end

  collectgarbage()
end

function mx:get_rofi_choice()
  local rofi = mp.command_native({
    name = "subprocess",
    args = { "rofi", "-dmenu", "-i", "-markup-rows" },
    capture_stdout = true,
    playback_only = false,
    stdin_data = table.concat(self.lines, "\n"),
  })
  return rofi.stdout, rofi.status
end

function mx:register_script_message()
  mp.register_script_message("merge-leader-bindings", function(bindings, leader_key)
    bindings = utils.parse_json(bindings)
    self:merge_leader_bindings(bindings, leader_key)
    self:sort_cmd_list()
  end)
end

function mx:unregister_script_message()
  mp.unregister_script_message("merge-leader-bindings")
end

mx:init()
