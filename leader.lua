local mp = require 'mp' -- isn't actually required, mp still gonna be defined

local opts = {}

(require 'mp.options').read_options(opts, mp.get_script_name())

package.path =
  mp.command_native({"expand-path", "~~/script-modules/?.lua;"})..package.path

local leader = require "leader"

leader:init(opts) -- binds leader key

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
        {'c', 'prefix', 'chapters', {
           {'m', 'chapters-menu', 'open current video chapters'},
           {'n', 'add chapter 1', 'seek to the next chapter'},
           {'p', 'add chapter -1', 'seek to the previous chapter'},
        }},
        {'<', 'seek -60', 'seek 1 minute backward'},
        {'>', 'seek 60', 'seek 1 minute forward'},
        {'.', 'frame-step', 'advance one frame and pause'},
        {',', 'frame-back-step', 'go back by one frame and pause'},
        -- {'k', 'increase-db', 'open video history'},
        {'s', 'prefix', 'subtitles', {
           {'-', 'add sub-delay -0.1', 'shift subtitles 100 ms earlier'},
           {'+', 'add sub-delay +0.1', 'shift subtitles 100 ms'},
           {'t', 'cycle sub-visibility', 'hide or show the subtitles'},
           {'n', 'no-osd sub-seek 1', 'seek to the previous subtitle'},
           {'p', 'no-osd sub-seek -1', 'seek to the next subtitle'},
           {'s', 'cycle sub-ass-vsfilter-aspect-compat', 'toggle stretching SSA/ASS subtitles with anamorphic videos to match the historical renderer'},
           {'O', 'cycle-values sub-ass-override "force" "no"', 'toggle overriding SSA/ASS subtitle styles with the normal styles'},
           {'o', 'cycle sub', 'switch subtitle track'}
        }},
        {'a', 'prefix', 'audio', {
           {'+', 'add audio-delay 0.100', 'change audio/video sync by delaying the audio'},
           {'-', 'add audio-delay -0.100', 'change audio/video sync by shifting the audio'}
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
