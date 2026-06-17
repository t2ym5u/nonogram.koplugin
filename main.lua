local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = _dir .. "?.lua;" .. _dir .. "common/?.lua;" .. _dir .. "../game-common/?.lua;" .. package.path

local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local PluginBase       = require("plugin_base")
local NonogramScreen   = lrequire("screen")
local _                = require("gettext")

local NonogramPlugin = PluginBase:extend{
    name      = "nonogram",
    menu_text = _("Nonogram"),
    menu_hint = "tools",
}

function NonogramPlugin:createScreen()
    return NonogramScreen:new{ plugin = self }
end

return NonogramPlugin
