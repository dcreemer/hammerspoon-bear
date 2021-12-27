-- xcall.lua
-- call and handle responses to x-callback-url events
-- uses the local xcall cli tool to create a blocking call

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "XCall"
obj.version = "1.0"
obj.author = "@dcreemer"
obj.homepage = "https://github.com/dcreemer/hammerspoon-bear"
obj.license = "MIT - https://opensource.org/licenses/MIT"

obj.requests = {}

http = require("hs.http")
json = require("hs.json")
fs = require("hs.fs")

local log = hs.logger.new('xcall', 'info')
-- the xcall cli is originally from
-- https://github.com/martinfinke/xcall
-- as pulled from here (recent universal build):
-- https://github.com/cdzombak/bear-backlinks/tree/master/lib
obj.xcbin = hs.spoons.resourcePath("xcall.app/Contents/MacOS/xcall")
log.i('xcall binary: ' .. obj.xcbin)

function obj.encode(t)
    local argts = {}
    local i = 1
    for k, v in pairs(t) do
        argts[i] = http.encodeForQuery(k) .. "=" .. http.encodeForQuery(v)
        i = i + 1
    end
    return table.concat(argts, '&')
end

function obj.call(scheme, path, params, activate)
    if not params then params = {} end
    local url = scheme .. "://x-callback-url/" .. path .. "?" .. obj.encode(params)
    local cmd = obj.xcbin .. " -url \"" .. url .. "\""
    if activate then
        cmd = cmd .. " -activate=\"YES\""
    end
    o, status, _, _ = hs.execute(cmd)
    if status then
        return json.decode(o)
    else
        log.e("xcall failed: " .. o)
        return nil
    end
end

return obj
