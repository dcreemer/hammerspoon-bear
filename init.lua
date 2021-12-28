-- bear.lua
--[[
    This module wraps some of the Bear "x-callback-url" API
    ( https://bear.app/faq/X-callback-url%20Scheme%20documentation/ ) with
    convenience Lua functions. The wrapping is done using the xcall command-line
    tool which implements the x-callback-url in a synchronous fashion.
    The bottom line is that you can automate Bear from Hammerspoon.

    In addition to implementing the Bear API, this module also implements a simple
    templating system, using the "etlua" template engine
    (https://github.com/leafo/etlua). To use the templates, just create a Bear note
    that containes template text, and then call the `createFromTemplate` method.
    (You likely want to bind this to a hotkey). The template text can access
    any Hammerspoon / Lua function -- so be careful.
    
    For example, if your note looks like this:

    ```
    # A simple bear note template

    Today is <%= os.date("%A, %B %d, %Y") %>. Have a nice day.
    ```

    When you call `createFromTemplate` the new note will look something like:

    ```
    # A simple bear note template

    Today is Monday, December 31, 2019. Have a nice day.
    ```

    See the [etlua](https://github.com/leafo/etlua) documentation for more details.
    The template is evaluated with access to additional symbols defined in the
    `template_env` table. Some convenience functions are pre-defined -- see the
    definitions at the bottom of this file.
]]


local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Bear"
obj.version = "1.0"
obj.author = "@dcreemer"
obj.homepage = "https://github.com/dcreemer/hammerspoon-bear"
obj.license = "MIT - https://opensource.org/licenses/MIT"

local log = hs.logger.new("bear", "info")

local xcall = dofile(hs.spoons.resourcePath("xcall.lua"))
local etlua = dofile(hs.spoons.resourcePath("etlua.lua"))

obj.token = nil
obj.template_env = {}

--- bear:openByTitle(title, show_window, edit)
--- method
--- Opens a note in Bear by matching the title
---
--- Parameters:
---  * title - the title of the note to open
---  * show_window - whether to show the window after opening
---  * edit - whether to edit the note after opening
---
--- Returns:
---  * a table of note data or a table of error data
function obj:openByTitle(title, show_window, edit)
    show_window = "yes"
    edit = "no"
    if show_window == false then
        show_window = "no"
    end
    if edit then
        edit = "yes"
    end
    local params = {show_window = show_window, edit = edit, title = title}
    log.d("Opening note:" , title)
    return xcall.call("bear", "open-note", params)
end

--- bear:openById(id, show_window, edit)
--- method
--- Opens a note in Bear by a specifc ID
---
--- Parameters:
---  * id - the id of the note to open
---  * show_window - whether to show the window after opening
---  * edit - whether to edit the note after opening
---
--- Returns:
---  * a table of note data or a table of error data
function obj:openById(id, show_window, edit)
    show_window = "yes"
    edit = "no"
    if show_window == false then
        show_window = "no"
    end
    if edit == false then
        edit = "no"
    end
    local params = {show_window = show_window, edit = edit, id = id}
    log.d("Opening note:", id)
    return xcall.call("bear", "open-note", params)
end

--- bear:getLink(id, title)
--- method
--- Get an x-callback-url link to open a note in Bear. Pass in either id
--- or title to get a link to a specific note.
---
--- Parameters:
--- * id - the id of the note to open, or nil to use just title
--- * title - the title of the note to open, or nil to use just id
---
--- Returns:
---  * string - the x-callback-url link
function obj:getLink(id, title)
    local params = {show_window = "no", edit = "no"}
    if id then
        params.id = id
    elseif title then
        params.title = title
    end
    return "bear://x-callback-url/open-note?" .. xcall.encode(params)
end

--- bear:getCurrent()
--- method
--- Get data about the currently selected note in Bear.
---
--- Parameters:
---
--- Returns:
---  * a table of note data
function obj:getCurrent()
    if not obj.token then
        log.e("No token, cannot get current note id")
        return nil
    end
    return xcall.call("bear", "open-note", {token = obj.token, selected = "yes"})
end

--- bear:search(term)
--- method
--- Search Bear using the given term, returning a table of results.
---
--- Parameters:
--- * term - the search term
---
--- Returns:
---  * a table of search results
function obj:search(term)
    if not obj.token then
        log.e("No token, cannot search")
        return nil
    end
    results = xcall.call("bear", "search", {
        token = obj.token,
        show_window = "no",
        term = term,
    })
    if results then
        return hs.json.decode(results.notes)
    end
    return nil
end

--- bear:replaceContent(nid, content)
--- method
--- replace the entire content of a note with the given content
---
--- Parameters:
--- * nid - the id of the note to replace
--- * content - the new content of the note
---
--- Returns:
---  * nothing
function obj:replaceContent(nid, content)
    if not obj.token then
        log.e("No token, cannot replace content")
        return nil
    end
    resp = xcall.call("bear", "add-text", {
        token = obj.token,
        id = nid,
        text = content,
        mode = "replace_all",
        open_note = "no",
        show_window = "no",
    })
    if not resp then
        log.e("Failed to update note", nid)
    end
end

--- Templates

--- bear:createFromTemplate(tid)
--- method
--- Create a new note from a template note. Sewe the template documentation
--- at the top of this file.
---
--- Parameters:
--- * tid - the id of the template note
---
--- Returns:
---  * string - identifier of the new note, or nil on failure
function obj:createFromTemplate(tid, env)
    resp = xcall.call("bear", "open-note", {id = tid})
    if not resp then
        log.e("Failed to open template note", tid)
        return nil
    end
    log.d("creating from template:", resp.title)
    if env then
        for k, v in pairs(obj.template_env) do
            env[k] = v
        end
    else
        env = obj.template_env
    end
    local output = etlua.render(resp.note, env)
    if not output then
        log.e("Failed to compile template note", tid)
        return nil
    end
    resp = xcall.call("bear", "create",
                      {show_window = "yes", edit = "yes", text = output})
    if not resp then
        log.e("Failed to create note from template", tid)
        return nil
    end
    return resp.identifier
end

-- some functions to use in templates

local function startOfDay(n)
    n = os.date("*t", n)
    n.hour = 0
    n.min = 0
    n.sec = 0
    return n
end

local function today(t)
    return os.time(startOfDay(t))
end

local function tomorrow(t)
    return os.time(startOfDay(t)) + 86400
end

local function yesterday(t)
    return os.time(startOfDay(t)) - 86400
end

local function date(t)
    -- return a nice datestring like "January 1, 1970"
    return os.date("%B %d, %Y", t)
end

local function isodate(t)
    -- return an ISO datestring like "1970-01-01"
    return os.date("%Y-%m-%d", t)
end

local function link(id, title)
    -- return a x-callback-url link as a string to open a note in Bear,
    -- by either id or title
    return obj:getLink(id, title)
end

obj.template_env = {
    today = today,
    tomorrow = tomorrow,
    yesterday = yesterday,
    date = date,
    isodate = isodate,
    link = link,
}

return obj
