local mp = require 'mp' -- isn't actually required, mp still gonna be defined

local opts = {}

(require 'mp.options').read_options(opts, mp.get_script_name())

package.path =
  mp.command_native({"expand-path", "~~/script-modules/?.lua;"})..package.path

local leader = require "leader"

leader:init(opts) -- binds leader key

-- FIXME: need timeout below since we need all functions to be defined before
-- this script will run
mp.add_timeout((0.1 and opts.bar_hide_timeout or 0), function ()
    leader:set_leader_bindings(
      -- key, name (must be unique!), comment, [follower bindings]
      {
        {'c', 'chapters-menu', 'open current video chapters'},
        {'x', 'M-x', 'open m-x menu'},
        {'k', 'increase-db', 'open video history'},
        {'s', 'prefix', 'subtitles', {
           {'-', 'add sub-delay -0.1', 'shift subtitles 100 ms earlier'},
           {'+', 'add sub-delay +0.1', 'shift subtitles 100 ms'},
           {'t', 'cycle sub-visibility', 'hide or show the subtitles'},
           {'s', 'cycle sub-ass-vsfilter-aspect-compat', 'toggle stretching SSA/ASS subtitles with anamorphic videos to match the historical renderer'},
           {'o', 'cycle-values sub-ass-override "force" "no"', 'toggle overriding SSA/ASS subtitle styles with the normal styles'},
           {'o', 'cycle sub', 'switch subtitle track'}
        }},
        {'a', 'prefix', 'audio', {
           {'+', 'add audio-delay 0.100', 'change audio/video sync by delaying the audio'},
           {'-', 'add audio-delay -0.100', 'change audio/video sync by shifting the audio'}
        }},
        {'f', 'prefix', 'filters', {
           {'c', 'add contrast 1'},
           {'C', 'add contrast -1'},
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
