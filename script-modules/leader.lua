local mp = require 'mp'
-- local utils = require 'mp.utils'
local assdraw = require 'mp.assdraw'

local opts = {
  leader_key = ',',
  pause_on_open = true,
  resume_on_exit = "only-if-was-paused", -- another possible value is true
  bar_hide_timeout = 2, -- timeout in seconds

  -- styles
  font_size = 21,
  menu_x_padding = 3, -- this padding for now applies only to 'left', not x
  menu_y_padding = 0, -- but this one applies to both - top & bottom
}

-- create namespace
local leader = {
  is_active = false,
  -- https://mpv.io/manual/master/#lua-scripting-mp-create-osd-overlay(format)
  ass = mp.create_osd_overlay("ass-events"),
  was_paused = false, -- flag that indicates that vid was paused by this script

  leader_bindings = {},

  key_sequence = '',
  -- history = {},
  -- history_pos = 1,
  key_bindings = {},
}

function leader:init(options)
  local _opts = opts
  _opts.__index = _opts
  opts = options
  setmetatable(opts, _opts)

  -- self:get_cmd_list()

  -- keybind to launch menu
  mp.add_forced_key_binding(opts.leader_key, "M-x", function()
                       self:start_key_sequence()
  end)
end

function leader:exit()
  self:undefine_key_bindings()
  collectgarbage()
end

function leader:start_key_sequence()
  self:set_active(true)
end

function leader:update(is_undefined_kbd)
  -- ASS tags documentation here - https://aegi.vmoe.info/docs/3.0/ASS_Tags/

  -- do not bother if function was called to close the menu..
  if not self.is_active then
    leader.ass:remove()
    return
  end

  local ww, wh = mp.get_osd_size() -- window width & height
  -- TODO: make alignment for this whole module bottom left, not bottom right
  -- so i can set y-position more elegantly
  local menu_y_pos =
    wh - (opts.font_size + opts.menu_y_padding * 2)

  -- function to get rid of some copypaste
  local function ass_new_wrapper()
    local a = assdraw.ass_new()
    a:new_event()
    a:append('{\\an7\\bord0\\shad0}') -- alignment top left, border 0, shadow 0
    a:append('{\\fs' .. opts.font_size .. '}')
    return a
  end

  local function get_background()
    local a = ass_new_wrapper()
    a:append('{\\1c&H1c1c1c}') -- background color
    -- a:append('{\\1a&H19}') -- opacity
    a:pos(0, 0)
    a:draw_start()
    a:rect_cw(0, menu_y_pos, ww, wh)
    a:draw_stop()
    return a.text
  end

  local function get_input_string()
    local a = ass_new_wrapper()
    a:pos(opts.menu_x_padding, menu_y_pos + opts.menu_y_padding)
    a:append(self:ass_escape(opts.leader_key) .. '+')
    a:append(self:ass_escape(self.key_sequence))
    a:append(is_undefined_kbd and '\\his undefined' or "")
    return a.text
  end

  leader.ass.res_x = ww
  leader.ass.res_y = wh
  leader.ass.data = table.concat({
      get_background(),
      get_input_string(),
  }, "\n")

  leader.ass:update()

end

-- TODO: make this func more like the one in emacs
function leader:add_key_binding(key, name, cmd)
  -- 'name' for now will be unused, but just for now
  print(key, name, cmd)
  table.insert(self.leader_bindings, {key = key, name = name, cmd = cmd})
end

function leader:get_matching_commands(kbd)
  local bindings = {}
  for _,v in ipairs(self.leader_bindings) do
    if v.key:lower():find(kbd:lower()) then
      table.insert(bindings, v)
    end
  end
  return bindings
end

function leader:handle_input(c)
  self.key_sequence = self.key_sequence .. c
  local matching_commands = self:get_matching_commands(self.key_sequence)

  -- if #matching_commands < 20 then print(matching_commands) end
  print(matching_commands[0], 'lgn')

  if #matching_commands == 0 then
    self:update(true)
    self:set_active(false, true)
  end

  if #matching_commands > 1 then
    self.key_sequence = self.key_sequence .. '+'
    self:update()
  end

  if #matching_commands == 1 then
    matching_commands[1].cmd()

    print(self.key_sequence)
    self:update()
    self:set_active(false)
  end
end


--[[
  The below code is a modified implementation of text input from mpv's console.lua:
  https://github.com/mpv-player/mpv/blob/87c9eefb2928252497f6141e847b74ad1158bc61/player/lua/console.lua

  I was too lazy to list all modifications i've done to the script, but if u
  rly need to see those - do diff with the original code
]]--

-------------------------------------------------------------------------------
--                          START ORIGINAL MPV CODE                          --
-------------------------------------------------------------------------------

-- Copyright (C) 2019 the mpv developers
--
-- Permission to use, copy, modify, and/or distribute this software for any
-- purpose with or without fee is hereby granted, provided that the above
-- copyright notice and this permission notice appear in all copies.
--
-- THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
-- WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
-- MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
-- SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
-- WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION
-- OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
-- CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

-- Escape a string for verbatim display on the OSD
function leader:ass_escape(str)
  -- There is no escape for '\' in ASS (I think?) but '\' is used verbatim if
  -- it isn't followed by a recognised character, so add a zero-width
  -- non-breaking space
  str = str:gsub('\\', '\\\239\187\191')
  str = str:gsub('{', '\\{')
  str = str:gsub('}', '\\}')
  -- Precede newlines with a ZWNBSP to prevent ASS's weird collapsing of
  -- consecutive newlines
  str = str:gsub('\n', '\239\187\191\\N')
  -- Turn leading spaces into hard spaces to prevent ASS from stripping them
  str = str:gsub('\\N ', '\\N\\h')
  str = str:gsub('^ ', '\\h')
  return str
end

-- Set the REPL visibility ("enable", Esc)
function leader:set_active(active, delayed)
  if active == self.is_active then return end
  if active then
    self.is_active = true
    -- mp.enable_messages('terminal-default') -- REVIEW: what's that?
    self:define_key_bindings()

    -- set flag 'was_paused' only if vid wasn't paused before EM init
    if opts.pause_on_open and not mp.get_property_bool("pause", false) then
      mp.set_property_bool("pause", true)
      self.was_paused = true
    end

    self:update()
  else
    -- no need to call 'update' in this block cuz 'clear' method is calling it
    self.is_active = false
    self:undefine_key_bindings()

    if opts.resume_on_exit == true or
      (opts.resume_on_exit == "only-if-was-paused" and self.was_paused) then
        mp.set_property_bool("pause", false)
    end

    -- clearing up
    self.key_sequence = ''
    self.was_paused = false
    mp.add_timeout((delayed and opts.bar_hide_timeout or 0), function ()
        self:update()
    end)
    collectgarbage()
  end
end

-- TODO: bind this to C-h maybe and pop extended-menu?
function leader:help_command(param)
  local cmdlist = mp.get_property_native('command-list')
  local output = ''
  if param == '' then
    output = 'Available commands:\n'
    for _, cmd in ipairs(cmdlist) do
      output = output  .. '  ' .. cmd.name
    end
    output = output .. '\n'
    output = output .. 'Use "help command" to show information about a command.\n'
    output = output .. "ESC or Ctrl+d exits the console.\n"
  else
    local cmd = nil
    for _, curcmd in ipairs(cmdlist) do
      if curcmd.name:find(param, 1, true) then
        cmd = curcmd
        if curcmd.name == param then
          break -- exact match
        end
      end
    end
    output = output .. 'Command "' .. cmd.name .. '"\n'
    for _, arg in ipairs(cmd.args) do
      output = output .. '    ' .. arg.name .. ' (' .. arg.type .. ')'
      if arg.optional then
        output = output .. ' (optional)'
      end
      output = output .. '\n'
    end
    if cmd.vararg then
      output = output .. 'This command supports variable arguments.\n'
    end
  end
  -- log_add('', output)
end

-- List of input bindings. This is a weird mashup between common GUI text-input
-- bindings and readline bindings.
function leader:get_bindings()
  local bindings = {
    { 'ctrl+[',      function() self:set_active(false) end           },
    { 'ctrl+g',      function() self:set_active(false) end           },
    { 'esc',         function() self:set_active(false) end           },
    { 'enter',       function() self:handle_input('enter') end },
    { 'bs',          function() self:handle_input('bs') end    },

    -- { 'ctrl+h',      function() self:handle_backspace() end        },
  }

  for i = 0, 9 do
    bindings[#bindings + 1] =
      {'kp' .. i, function() self:handle_input('' .. i) end}
  end

  return bindings
end

function leader:text_input(info)
  if info.key_text and (info.event == "press" or info.event == "down"
                        or info.event == "repeat")
  then
    self:handle_input(info.key_text)
  end
end

function leader:define_key_bindings()
  if #self.key_bindings > 0 then return end

  for _, bind in ipairs(self:get_bindings()) do
    -- Generate arbitrary name for removing the bindings later.
    local name = "leader_" .. (#self.key_bindings + 1)
    self.key_bindings[#self.key_bindings + 1] = name
    mp.add_forced_key_binding(bind[1], name, bind[2], {repeatable = true})
  end
  mp.add_forced_key_binding("any_unicode", "leader_input", function (...)
                              self:text_input(...)
  end, {repeatable = true, complex = true})
  self.key_bindings[#self.key_bindings + 1] = "leader_input"
end

function leader:undefine_key_bindings()
  for _, name in ipairs(self.key_bindings) do
    mp.remove_key_binding(name)
  end
  self.key_bindings = {}
end

-------------------------------------------------------------------------------
--                           END ORIGINAL MPV CODE                           --
-------------------------------------------------------------------------------

return leader
