local mp = require 'mp' -- isn't actually required, mp still gonna be defined

local opts = {
  leader_key = ',',
  pause_on_open = false,
  resume_on_exit = "only-if-was-paused", -- another possible value is true
  hide_timeout = 2, -- timeout in seconds to hide menu
  which_key_show_delay = 0.1, -- timeout in seconds to show which-key menu
  strip_cmd_at = 28, -- max symbols for cmd names in which-key menu

  -- styles
  font_size = 21,
  menu_x_padding = 3, -- this padding for now applies only to 'left', not x
  which_key_menu_y_padding = 3,
}

(require 'mp.options').read_options(opts, mp.get_script_name())

package.path =
  mp.command_native({"expand-path", "~~/script-modules/?.lua;"})..package.path

local leader = require "leader"

leader:init(opts) -- binds leader key

mp.register_script_message("leader-bindings-request", function()
                             leader:provide_leader_bindings()
end)

-- FIXME: need timeout below since we need all functions to be defined before
-- this script will run. Trying to call init() with this timeout won't work
-- since it's gonna pause loading of all other scripts.

-- another more reliable, but longer way to set leader bindings after all
-- scripts have loaded is to set a timer, threshold and set an observer on
-- 'input-bindings' mpv prop and run timer each time this prop gets updated. And
-- if timer passes threshold - run 'set_leader_bindings'

mp.add_timeout(0.3, function ()
    leader:set_leader_bindings(
      -- key, name (must be unique!), comment, [follower bindings]
      {
        -- Scripts
        {'x', 'M-x', 'execute-extended-command'},

        -- Playback
        {'<', 'seek -60', 'seek 1 minute backward'},
        {'>', 'seek 60', 'seek 1 minute forward'},
        {'.', 'frame-step', 'advance one frame and pause'},
        {',', 'frame-back-step', 'go back by one frame and pause'},
        {'N', 'playlist-next', 'skip to the next file'},
        {'P', 'playlist-previous', 'skip to the previous file'},

        -- Other
        {'l', 'ab-loop', 'set/clear A-B loop points'},
        {'L', 'cycle-values loop-file "inf" "no"', 'toggle infinite looping'},
        -- TODO: check if this one works
        {' ', 'show-text ${playlist}', 'show the playlist'},
        {'/', 'show-text ${track-list}', 'show the list of video, audio and sub tracks'},
        {'q', 'quit-watch-later', 'exit and remember the playback position'},

        -- Prefixes
        {'c', 'prefix', 'chapters', {
           {'m', 'chapters-menu', 'open current video chapters'},
           {'n', 'add chapter 1', 'seek to the next chapter'},
           {'p', 'add chapter -1', 'seek to the previous chapter'},
        }},

        {'s', 'prefix', 'subtitles', {
           {'-', 'add sub-delay -0.1', 'shift subtitles 100 ms earlier'},
           {'+', 'add sub-delay +0.1', 'shift subtitles 100 ms'},
           {'t', 'cycle sub-visibility', 'hide or show the subtitles'},

           -- should it be here? it's more about playback section
           {'n', 'no-osd sub-seek 1', 'seek to the previous subtitle'},
           {'p', 'no-osd sub-seek -1', 'seek to the next subtitle'},

           {'s', 'cycle sub-ass-vsfilter-aspect-compat', 'toggle stretching SSA/ASS subtitles with anamorphic videos to match the historical renderer'},
           {'O', 'cycle-values sub-ass-override "force" "no"', 'toggle overriding SSA/ASS subtitle styles with the normal styles'},
           {'o', 'cycle sub', 'switch subtitle track'}
        }},

        {'a', 'prefix', 'audio', {
           {'+', 'add audio-delay 0.100', 'change audio/video sync by delaying the audio'},
           {'-', 'add audio-delay -0.100', 'change audio/video sync by shifting the audio'},
           {'c', 'cycle audio', 'switch audio track'},
        }},

        {'f', 'prefix', 'filters', {
           -- example of multi-nested prefixes
           {'c', 'prefix', 'contrast', {
              {'+', 'add contrast 1'},
              {'-', 'add contrast -1'}
           }},
           {'b', 'add brightness 1'},
           {'B', 'add brightness -1'},
           {'g', 'add gamma 1'},
           {'G', 'add gamma -1'},
           {'s', 'add saturation 1'},
           {'S', 'add saturation -1'},
        }}
      }
    )
end)
