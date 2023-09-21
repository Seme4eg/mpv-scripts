local mp = require 'mp'
local utils = require 'mp.utils'
local assdraw = require 'mp.assdraw'

local opts = {
  leader_key = ',',
  pause_on_open = false,
  resume_on_exit = "only-if-was-paused", -- another possible value is true
  hide_timeout = 2,                      -- timeout in seconds to hide menu
  which_key_show_delay = 0.1,            -- timeout in seconds to show which-key menu
  strip_cmd_at = 28,                     -- max symbols for cmd names in which-key menu

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
  prefixes = {},         -- needed for some display info only
  matching_commands = {},
  which_key_timer = nil, -- timer obj, that opens which-key
  close_timer = nil,     -- timer obj, that closes menu

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
function leader:get_matching_commands()
  local result = {}

  -- include all prefixes on n-th level that match current key sequence
  for prefix, name in pairs(self.prefixes) do
    if #prefix == #self.key_sequence + 1
        and prefix:sub(1, #self.key_sequence):find(self.key_sequence, 1, true)
    then
      table.insert(result,
        { key = prefix, name = 'prefix', cmd = name.prefix_name })
    end
  end

  -- in case user pressed jsut leader key - compose 'matching_commands' from
  -- self.leader_bidnings with key.length == 1
  if #self.key_sequence == 0 then
    -- include all commands that consist of only 1 key
    for i, v in ipairs(self.leader_bindings) do
      if #v.key == 1 then
        table.insert(result, v)
      end
    end
  else -- in case there is at least 1 key pressed after leadre handle prefixes
    -- include all commands that consist of only 1 key
    for i, v in ipairs(self.matching_commands) do
      if #v.key == #self.key_sequence + 1 then
        table.insert(result, v)
      end
    end
  end

  -- aplhabetical sort
  table.sort(result, function(i, j) return i.key < j.key end)

  return result
end

function leader:update_matching_commands(kbd)
  self.matching_commands = {}
  for _, v in ipairs(self.leader_bindings) do
    -- exact match of the beginning of the string
    if v.key:sub(1, #kbd):find(kbd, 1, true) then
      table.insert(self.matching_commands, v)
    end
  end
end

function leader:set_leader_bindings(bindings)
  local function get_full_cmd_name(cmd)
    -- for now i decided to not implement 'guess' logic on which command user
    -- wants to fire, cuz it will make things less obvious and i'd rather have
    -- user explicitly state which functions he wants to call rather than guess
    -- it. I'm only applying this to script-bindings, which full names i find
    -- by 'name' stated when they were defined.

    local b_list = mp.get_property_native("input-bindings")

    -- if there is no spaces, look for full name if present
    -- supposing there's gonna be only one match
    for _, binding in ipairs(b_list) do
      -- if it's a script-binding - find and return it's full name
      if binding.cmd:find(cmd, 1, true) then return binding.cmd end
    end
  end

  local function set(_bindings, prefix_sequence)
    local key, name, comment, innerBindings

    prefix_sequence = prefix_sequence or ''

    for _, binding in ipairs(_bindings) do
      key, name, comment, innerBindings = table.unpack(binding)

      if name == 'prefix' then
        -- fill prefixes object with prefixes names
        self.prefixes[prefix_sequence .. key] = { prefix_name = comment }
        -- recursively call this function to set inner bindings, do not return
        set(innerBindings, prefix_sequence .. key)
      else
        local local_name

        -- if command contains space, most likely it is not script-binding, but
        -- this thing still needs a REVIEW, cuz i think it is not reliable
        -- enough
        if not name:match('.*%s.*') then
          name = get_full_cmd_name(name) or name
        else
          -- gsub for stripping several spaces, since in input.conf those r common
          name = name:gsub('%s+', ' ')
        end

        table.insert(self.leader_bindings, {
          key = prefix_sequence .. key,
          cmd = name,
          comment = comment
        })
      end
    end
  end

  set(bindings)

  self:provide_leader_bindings()
end

-- send leader bindings to M-x
function leader:provide_leader_bindings()
  -- Maybe this func might be extended / made public in the future so people can
  -- redefine it and instead there's gonna be a wrapper of it in this script
  local bindings_json = utils.format_json(self.leader_bindings)
  print('provided')
  mp.commandv("script-message-to", "M_x", "merge-leader-bindings",
    bindings_json, opts.leader_key)
end

-- opts: {is_prefix = Bool, is_undefined_kbd = Bool}
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

  -- matching commands with prefixes included, only for 'which-key'
  local current_matchings = self:get_matching_commands()
  local show_which_key = #current_matchings > 1
  local which_key_lines_amount = math.min(#current_matchings, 6)

  -- if case of which-key for 'leader' raise 8 lines max number to 8
  if #self.key_sequence == 0 then
    which_key_lines_amount = math.min(#current_matchings, 8)
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
    if show_which_key then
      a:new_event()
      a:append('{\\1c&Hffffff}') -- background color
      a:pos(0, 0)
      a:draw_start()
      a:rect_cw(0, menu_y_pos - 1, ww, menu_y_pos)
      a:draw_stop()

      -- draw lines of background based on matching_command length (max 6 lines)
      -- (for which-key functionality)
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
    for char in self.key_sequence:gmatch '.' do
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

    if params.is_prefix and show_which_key then
      a:append(get_font_color('comment'))
      -- in case user just pressed <leader> - show it
      -- if prefix name is undefined - show '+prefix'

      -- get last key of current keybinding and append prefix name after
      -- keybinding string

      local prefix_name
      if #self.key_sequence == 0 then
        prefix_name = '<leader>'
      else
        prefix_name = self.prefixes[self.key_sequence].prefix_name or ''
      end
      a:append('\\h' .. prefix_name)
    end

    return a.text
  end

  local function get_spaces(num)
    -- returns num-length string full of spaces
    local s = ''
    for _ = 1, num do s = s .. '\\h' end
    return s
  end

  local function which_key()
    if #current_matchings <= 1 then return '' end

    local a = assdraw.ass_new()

    local function get_line(i)
      -- get remaining keys of currently matching commands
      local keys = current_matchings[i].key:gsub(self.key_sequence ..
        '(.*)$', '%1')

      -- if cmd is longer than max length - strip it
      local cmd = #current_matchings[i].cmd > opts.strip_cmd_at
          and string.sub(current_matchings[i].cmd, 1,
            opts.strip_cmd_at - 3) .. '...'
          or current_matchings[i].cmd

      -- prepend all prefix names with '+'
      if current_matchings[i].name == 'prefix' then cmd = '+' .. cmd end

      a:append(get_font_color('key'))
      a:append(self:ass_escape(keys))
      a:append(get_font_color('comment'))
      a:append('\\h→\\h')
      -- in case current key is not pre-last one - show kbd as 'prefix'
      a:append(get_font_color(
        (#keys == 1 and current_matchings[i].name ~= 'prefix')
        and 'command'
        or 'prefix'))
      a:append(#keys == 1 and self:ass_escape(cmd) or '+prefix')
      -- 2 for 2 spaces between columns
      a:append(get_spaces(opts.strip_cmd_at + 2 - #cmd))
    end

    for i = 1, which_key_lines_amount do
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
      while current_matchings[j + which_key_lines_amount] do
        get_line(j + which_key_lines_amount)
        j = j + which_key_lines_amount
      end
    end

    return a.text
  end

  leader.ass.res_x = ww
  leader.ass.res_y = wh
  leader.ass.data = table.concat({ get_background(),
    get_input_string(),
    which_key() }, "\n")

  leader.ass:update()
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
    self.close_timer = mp.add_timeout((delayed and opts.hide_timeout or 0), function()
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
    self:update({ is_undefined_kbd = true })
    self:set_active(false, true)
  end

  if #self.matching_commands > 1 then
    self:update({ is_prefix = true }) -- show just leader string

    -- and set timeout to show which-key
    self.which_key_timer = mp.add_timeout(
      opts.which_key_show_delay, function()
        self:update({ is_prefix = true })
      end)
  end

  if #self.matching_commands == 1 then
    -- if key sequence matches only one command, but key sequence isn't full..
    if #self.matching_commands[1].key ~= #self.key_sequence then
      self:update({ is_prefix = true }) -- show just leader string

      -- and set timeout to show which-key
      self.which_key_timer = mp.add_timeout(
        opts.which_key_show_delay, function()
          self:update({ is_prefix = true })
        end)

      return
    end

    -- in case there is bound command to that key, but it's undefined..
    if not self.matching_commands[1].cmd then
      self:update({ is_undefined_kbd = true })
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
]]
   --

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
    { 'ctrl+[', function() self:set_active(false) end },
    { 'ctrl+g', function() self:set_active(false) end },
    { 'esc',    function() self:set_active(false) end },
    { 'enter',  function() self:handle_input('enter') end },
    { 'bs',     function() self:handle_input('bs') end },

    -- { 'ctrl+h',      function() self:handle_backspace() end        },
  }

  for i = 0, 9 do
    bindings[#bindings + 1] =
    { 'kp' .. i, function() self:handle_input('' .. i) end }
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
    mp.add_forced_key_binding(bind[1], name, bind[2], { repeatable = true })
  end
  mp.add_forced_key_binding("any_unicode", "leader_input", function(...)
    self:text_input(...)
  end, { repeatable = true, complex = true })
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
