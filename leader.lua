local mp = require 'mp' -- isn't actually required, mp still gonna be defined

-- should not be altered here, edit options in corresponding .conf file
local opts = {
  leader_key = ',',
  -- TODO: rest keybindings
}

(require 'mp.options').read_options(opts, mp.get_script_name())

package.path =
  mp.command_native({"expand-path", "~~/script-modules/?.lua;"})..package.path

local leader = require "leader"

leader:init(opts) -- binds leader key

-- REVIEW: do i even need this wrapper? or better return class method instead?
function add_leader_key_binding(...)
  leader:add_key_binding(...)
end

-- return {add_leader_key_binding, ...} -- make something like this in future
return add_leader_key_binding
