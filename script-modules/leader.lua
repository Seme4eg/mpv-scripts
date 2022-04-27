local mp = require 'mp'
local utils = require 'mp.utils'
local assdraw = require 'mp.assdraw'

local opts = {
  leader_key = ',',
  pause_on_open = false,
  resume_on_exit = "only-if-was-paused", -- another possible value is true
  hide_timeout = 2, -- timeout in seconds to hide menu
  which_key_timeout = 0.1, -- timeout in seconds to show which-key menu
  strip_cmd_at = 28, -- max symbols for cmd names in which-key menu

  -- styles
  font_size = 21,
  menu_x_padding = 3, -- this padding for now applies only to 'left', not x
  which_key_menu_y_padding = 3,
}

-- create namespace
local leader = {
  is_active = false,
  -- https://mpv.io/manual/master/#lua-scripting-mp-create-osd-overlay(format)
  ass = mp.create_osd_overlay("ass-events"),
  was_paused = false, -- flag that indicates that vid was paused by this script

  leader_bindings = {},
  prefixes = {}, -- needed for some display info only
  matching_commands = {},
  which_key_timer = nil, -- timer obj, that opens which-key
  close_timer = nil, -- timer obj, that closes menu

  text_color = {
    key = 'a9dfa1',
    command = 'fcddb5',
    prefix = 'd8a07b',
    comment = '636363',
  },

  key_sequence = '',
  key_bindings = {},
}

function leader:init(options)
  local _opts = opts
  _opts.__index = _opts
  opts = options
  setmetatable(opts, _opts)

  -- keybind to launch menu
  mp.add_forced_key_binding(opts.leader_key, "leader", function()
                       self:start_key_sequence()
  end)
end

-- REVIEW: remove this func, ain't needed (since im copying emacs behavior)
function leader:exit()
  self:undefine_key_bindings()
  self.close_timer:kill()
  collectgarbage()
end

function leader:start_key_sequence()
  -- remove close timer in case user started another sequence before status
  -- line disappeared
  if self.close_timer then self.close_timer:kill() end

  self:set_active(true)
end

-- basically a getter for 'matching_commands', but also returns prefixes
function leader:matching_commands()
  local result = {}

    -- include all prefixed on n-th level
    for key, value in ipairs(self.prefixes) do
      if value.level == #self.key_sequence + 1 then
        table.insert(result, {key = key, name = 'prefix', cmd = value.prefix_name})
      end
    end

  -- in case user pressed jsut leader key - compose 'matching_commands' from
  -- self.leader_bidnings with key.length == 1
  if #self.key_sequence == 0 then
    -- include all commands that consist of only 1 key
    for i,v in ipairs(self.leader_bindings) do
      if #v.key == 1 then
        table.insert(result, v)
      end
    end
  else -- in case there is at least 1 key pressed after leadre handle prefixes

    -- include all commands that consist of only 1 key
    for i,v in ipairs(self.matching_commands) do
      if #v.key == #self.key_sequence + 1 then
        table.insert(result, v)
      end
    end
  end

    -- TODO: sorting alphabetically

  return result
end

-- opts: {is_prefix = Bool, show_which_key = Bool, is_undefined_kbd = Bool}
function leader:update(params)
  -- ASS tags documentation here - https://aegi.vmoe.info/docs/3.0/ASS_Tags/

  params = params or {}

  -- do not bother if function was called to close the menu..
  if not self.is_active then
    leader.ass:remove()
    return
  end

  local ww, wh = mp.get_osd_size() -- window width & height
  local menu_y_pos = wh - opts.font_size
  local which_key_lines_amount = math.min(#self.matching_commands, 6)

  -- if case of which-key for 'leader' raise 8 lines max number to 8
  if #self.key_sequence == 0 then
    which_key_lines_amount = math.min(#self.leader_bindings, 8)
  end

  -- y pos where to start drawing which key (1 is pixels from divider line)
  local which_key_y_offset = menu_y_pos - 1 - opts.font_size *
    which_key_lines_amount - opts.which_key_menu_y_padding * 2

  -- function to get rid of some copypaste
  local function ass_new_wrapper()
    local a = assdraw.ass_new()
    a:new_event()
    a:append('{\\an7\\bord0\\shad0}') -- alignment top left, border 0, shadow 0
    a:append('{\\fs' .. opts.font_size .. '}')
    return a
  end

  local function get_font_color(style)
    return '{\\1c&H' .. self.text_color[style] .. '}'
  end

  local function get_background()
    local a = ass_new_wrapper()

    -- draw keybind background
    a:append('{\\1c&H1c1c1c}') -- background color
    a:pos(0, 0)
    a:draw_start()
    a:rect_cw(0, menu_y_pos, ww, wh)
    a:draw_stop()

    -- draw separator line
    if params.show_which_key then
      a:new_event()
      a:append('{\\1c&Hffffff}') -- background color
      a:pos(0, 0)
      a:draw_start()
      a:rect_cw(0, menu_y_pos - 1, ww, menu_y_pos)
      a:draw_stop()
    end

    -- draw lines of background based on matching_command length (max 6 lines)
    -- (for which-key functionality)
    if params.show_which_key then
      a:new_event()
      a:append('{\\1c&H1c1c1c}') -- background color
      a:pos(0, 0)
      a:draw_start()
      a:rect_cw(0, which_key_y_offset, ww, menu_y_pos)
      a:draw_stop()
    end

    return a.text
  end

  local function get_display_kbd()
    local str = ''
    for char in self.key_sequence:gmatch'.' do
      str = str .. char .. ' '
    end
    return str:gsub("(.-)%s*$", "%1")
  end

  local function get_input_string()
    local a = ass_new_wrapper()
    a:pos(opts.menu_x_padding, menu_y_pos)
    a:append(self:ass_escape(opts.leader_key) ..
             (#self.key_sequence == 0 and '' or '\\h'))
    a:append(self:ass_escape(get_display_kbd()))

    a:append(params.is_undefined_kbd and '\\his undefined' or "-")

    if params.is_prefix and params.show_which_key then
      a:append(get_font_color('comment'))
      -- get last key of current keybinding and append prefix name after
      -- keybinding string
      local last_key = self.key_sequence:gsub('.*(.)$', '%1')
      a:append('\\h' .. self.prefixes[last_key].prefix_name)
    end

    return a.text
  end

  local function get_spaces(num)
    -- returns num-length string full of spaces
    local s = ''
    for _=1,num do s = s .. '\\h' end
    return s
  end

  local function which_key()
    local a = assdraw.ass_new()

    local function get_line(i)
      -- get last key of current command binding
      local key = self.matching_commands[i].key:gsub('.*(.)$', '%1')
      -- if cmd is longer than max length - strip it
      local cmd = #self.matching_commands[i].cmd > opts.strip_cmd_at
        and string.sub(self.matching_commands[i].cmd, 1,
                       opts.strip_cmd_at - 3) .. '...'
        or self.matching_commands[i].cmd

      a:append(get_font_color('key'))
      a:append(key)
      a:append(get_font_color('comment'))
      a:append('\\h→\\h')
      a:append(get_font_color('command'))
      a:append(cmd)
      -- 2 for 2 spaces between columns
      a:append(get_spaces(opts.strip_cmd_at + 2 -
                          #self.matching_commands[i].cmd))
    end

    for i=1,which_key_lines_amount do
      local y_offset = which_key_y_offset + opts.which_key_menu_y_padding +
        opts.font_size * (i - 1)

      a:new_event()
      -- reset styles
      a:append('{\\an7\\bord0\\shad0}') -- alignment top left, border 0, shadow 0
      a:append('{\\fs' .. opts.font_size .. '}')

      a:pos(opts.menu_x_padding, y_offset)

      get_line(i)

      -- compose lines out of elements A(n) and A(n+6)
      local j = i
      while self.matching_commands[j + 6] do
        get_line(j+6)
        j = j + 6
      end
    end

    return a.text

  end

  print(#self.key_sequence, 'len')

  leader.ass.res_x = ww
  leader.ass.res_y = wh
  leader.ass.data = table.concat({get_background(),
                                  get_input_string(),
                                  (params.is_prefix or #self.key_sequence == 0) and which_key()}, "\n")

  leader.ass:update()

end

function leader:set_leader_bindings(bindings)

  local function get_full_cmd_name(cmd)
    local b_list = mp.get_property_native("input-bindings")

    -- supposing there's gonna be only one match
    for _,v in ipairs(b_list) do
      if v.cmd:find(cmd, 1, -1) then return v.cmd end
    end
  end

  local function set(_bindings, prefix, level)

    local key, name, comment, innerBindings

    level = level or 1 -- variable that is needed to be put in 'prefix' table

    for _,binding in ipairs(_bindings) do
      key, name, comment, innerBindings = table.unpack(binding)

      if name == 'prefix' then
        -- fill prefixes object with prefixes names
        self.prefixes[key] = {prefix_name = comment, level = level}
        set(innerBindings, key, level + 1)
      else
        name = get_full_cmd_name(name)

        table.insert(self.leader_bindings, {
                       key = (prefix and prefix or '') .. key,
                       cmd = name,
                       comment = comment})

      end
    end

    local bindings_json = utils.format_json(self.leader_bindings)
    mp.commandv("script-message-to", "M_x", "merge-leader-bindings",
                bindings_json, opts.leader_key)

  end

  set(bindings)

end

function leader:update_matching_commands(kbd)
  self.matching_commands = {}
  for _,v in ipairs(self.leader_bindings) do
    -- only match the beginning of the string
    if v.key:sub(1, #kbd):find(kbd) then
      table.insert(self.matching_commands, v)
    end
  end
end

-- Set the REPL visibility
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
    self.close_timer = mp.add_timeout((delayed and opts.hide_timeout or 0), function ()
        self:update()
    end)
    collectgarbage()
  end
end

function leader:handle_input(c)
  self.key_sequence = self.key_sequence .. c
  self:update_matching_commands(self.key_sequence)

  -- always kill current timer if present
  if self.which_key_timer then
    self.which_key_timer:kill()
  end

  if #self.matching_commands == 0 then
    self:update({is_undefined_kbd = true})
    self:set_active(false, true)
  end

  if #self.matching_commands > 1 then
    self:update({is_prefix = true}) -- show just leader string

      -- and set timeout to show which-key
    self.which_key_timer = mp.add_timeout(
      opts.which_key_timeout, function ()
        self:update({is_prefix = true, show_which_key = true})
    end)
  end

  if #self.matching_commands == 1 then
    -- if key sequence matches only one command, but key sequence isn't full..
    if #self.matching_commands[1].key ~= #self.key_sequence then
      self:update({is_prefix = true}) -- show just leader string

      -- and set timeout to show which-key
      self.which_key_timer = mp.add_timeout(
        opts.which_key_timeout, function ()
          self:update({is_prefix = true, show_which_key = true})
      end)

      return
    end

    -- in case there is bound command to that key, but it's undefined..
    if not self.matching_commands[1].cmd then
      self:update({is_undefined_kbd = true})
      self:set_active(false, true)
      return
    end

    mp.command(self.matching_commands[1].cmd)

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
