local mp = require 'mp' -- isn't actually required, mp still gonna be defined

-- should not be altered here, edit options in corresponding .conf file
local opts = {
  -- This script has no options used in itself, all of the options below are for
  -- 'extended-menu' script

  toggle_menu_binding = 'g',
  lines_to_show = 17,
  pause_on_open = true,
  resume_on_exit = "only-if-was-paused",

  -- styles
  font_size=21,
  line_bottom_margin = 1,
  menu_x_padding = 5,
  menu_y_padding = 2,

  search_heading = 'Select chapter',
  index_field = 'index',
  filter_by_fields = {'content'},
}

(require 'mp.options').read_options(opts, mp.get_script_name())

package.path =
  mp.command_native({"expand-path", "~~/script-modules/?.lua;"})..package.path
local em = require "extended-menu"

local chapter_menu = em:new(opts)

local chapter = {list = {}, current_i = nil}

local function get_chapters()
  local chaptersCount = mp.get_property("chapter-list/count")
  if chaptersCount == 0 then
    return {}
  else
    local chaptersArr = {}

    -- We need to start from 0 here cuz mp returns titles starting with 0
    for i=0, chaptersCount do
      local chapterTitle = mp.get_property_native("chapter-list/"..i.."/title")
      if chapterTitle then
        table.insert(chaptersArr, {index = i + 1, content = chapterTitle})
      end
    end

    return chaptersArr
  end
end

function chapter_menu:submit(val)
  -- .. and we subtract one index when we set to mp
  mp.set_property_native("chapter", val.index - 1)
end

local function chapter_info_update()
  chapter.list = get_chapters()

  if not #chapter.list then return end

  -- tho list might b already present, but 'chapter' still might b nil
  -- and we also add one index when we get from mp
  chapter.current_i = (mp.get_property_native("chapter") or 0) + 1
end

mp.register_event("file-loaded", chapter_info_update)
mp.observe_property("chapter-list/count", "number", chapter_info_update)
mp.observe_property("chapter", "number", chapter_info_update)

-- keybind to launch menu
mp.add_key_binding(opts.toggle_menu_binding, "chapters-menu", function()
                     chapter_menu:init(chapter)
end)
