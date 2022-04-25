local mp = require 'mp' -- isn't actually required, mp still gonna be defined
local assdraw = require 'mp.assdraw'

-- should not be altered here, edit options in corresponding .conf file
local opts = {
  -- options for this script --------------------------------------------------
  strip_cmd_at = 65,

  -- options for extended menu ------------------------------------------------
  toggle_menu_binding = 't',
  lines_to_show = 17,
  pause_on_open = true,
  resume_on_exit = "only-if-was-paused", -- another possible value is true

  -- styles
  font_size=21,
  line_bottom_margin = 1,
  menu_x_padding = 5,
  menu_y_padding = 2,

  search_heading = 'M-x',
  -- filter_by_fields = {'cmd', 'key', 'comment'},
  filter_by_fields = [[ [ "cmd", "key", "comment" ] ]],
}

(require 'mp.options').read_options(opts, mp.get_script_name())

package.path =
  mp.command_native({"expand-path", "~~/script-modules/?.lua;"})..package.path
local em = require "extended-menu"

local mx_menu = em:new(opts)

local data = {list = {}}

function mx_menu:submit(val)
  mp.msg.info(val.cmd)
  mp.command(val.cmd)
end

local function get_cmd_list()
  local bindings = mp.get_property_native("input-bindings")

  -- sort bindings by priority to show bindings from highest priority to lowest
  table.sort(bindings, function(i, j)
               return tonumber(i.priority) > tonumber(j.priority)
  end)

  -- sets a flag 'shadowed' to all binding that have a binding with higher
  -- priority using same key binding
  for _,v in ipairs(bindings) do
    for _,v1 in ipairs(bindings) do
      if v.key == v1.key and v.priority < v1.priority then
        v.shadowed = true
        break
      end
    end
  end

  data.list = bindings
end

-- [i]ndex [v]alue
function em:get_line(_, v)
    local a = assdraw.ass_new()
    -- 20 is just a hardcoded value, cuz i don't think any keybinding string
    -- length might exceed this value
    local comment_offset = opts.strip_cmd_at + 20

    local cmd = v.cmd

    if #cmd > opts.strip_cmd_at then
      cmd = string.sub(cmd, 1, opts.strip_cmd_at - 3) .. '...'
    end

    -- we need to count length of strings without escaping chars, so we
    -- calculate it before defining excaped strings
    local cmdkbd_len = #(cmd .. v.key) + 3 -- 3 is ' ()'

    cmd = self:ass_escape(cmd)
    local key = self:ass_escape(v.key)
    -- 'comment' field might be nil
    local comment = self:ass_escape(v.comment or '')

    local function get_spaces(num)
      -- returns num-length string full of spaces
      local s = ''
      for _=1,num do s = s .. '\\h' end
      return s
    end

    -- handle inactive keybindings
    if v.shadowed or v.priority == -1 then
      local why_inactive = (v.priority == -1)
        and 'inactive keybinding'
        or 'that binding is currently shadowed by another one'

      a:append(self:get_font_color('comment'))
      a:append(cmd)
      a:append('\\h(' .. key .. ')')
      a:append(get_spaces(comment_offset - cmdkbd_len))
      a:append('(' .. why_inactive .. ')')
      return a.text
    end

    a:append(self:get_font_color('default'))
    a:append(cmd)
    a:append(self:get_font_color('accent'))
    a:append('\\h(' .. key .. ')')
    a:append(self:get_font_color('comment'))
    a:append(get_spaces(comment_offset - cmdkbd_len))
    a:append(comment and comment or '')
    return a.text
end

-- mp.register_event("file-loaded", get_cmd_list)
get_cmd_list()

-- keybind to launch menu
mp.add_key_binding(opts.toggle_menu_binding, "M-x", function()
                     mx_menu:init(data)
end)
