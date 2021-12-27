--- xcall.lua
---
--- Call and handle responses to x-callback-url events (as documented in
--- http://x-callback-url.com/). Uses the local xcall cli tool to create a
--  blocking call to the remote application.

local obj = {}
obj.__index = obj

local http = require("hs.http")
local json = require("hs.json")

local log = hs.logger.new("xcall", "info")

-- the xcall cli is originally from
-- https://github.com/martinfinke/xcall
-- as pulled from here (recent universal build):
-- https://github.com/cdzombak/bear-backlinks/tree/master/lib
obj.xcbin = hs.spoons.resourcePath("xcall.app/Contents/MacOS/xcall")
log.d("xcall binary:", obj.xcbin)

--- xcall.encode(t)
--- function
--- Encodes a table into a URL query string
---
--- Parameters:
---  * t - a table of key/value pairs
---
--- Returns:
---  * a string of the encoded query string
function obj.encode(t)
    local argts = {}
    local i = 1
    for k, v in pairs(t) do
        argts[i] = http.encodeForQuery(k) .. "=" .. http.encodeForQuery(v)
        i = i + 1
    end
    return table.concat(argts, "&")
end

--- xcall.call(scheme, path, params, activate)
--- function
--- Executes the remote x-callback-url call using the underlying xcall cli too.   
---
--- Parameters:
---  * scheme - the scheme of the x-callback-url, without the ":", e.g. "bear"
---  * path - the path of the x-callback-url, e.g. "open-note", with no leading "/"
---  * params - a table of key/value pairs to be encoded and passed as the query string
---  * activate - whether to activate the app during the call
---
--- Returns:
---  * a table of the decoded response from the x-callback-url
function obj.call(scheme, path, params, activate)
    if not params then params = {} end
    local url = scheme .. "://x-callback-url/" .. path .. "?" .. obj.encode(params)
    local cmd = obj.xcbin .. " -url \"" .. url .. "\""
    if activate then
        cmd = cmd .. " -activate=\"YES\""
    end
    log.d("Calling:", cmd)
    o, status, _, _ = hs.execute(cmd)
    if status then
        return json.decode(o)
    else
        log.e("xcall failed: " .. o)
        return nil
    end
end

return obj
