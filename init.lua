-- bear.lua
--[[
    Bear.spoon - provides the following fucntionality:

    1. An API for accessing, modifying, and createing Bear notes.
    2. A templating system for creating new notes based on other Bear notes
       treated as a template.
    3. A Daily Journal system for creating and managing a the concept of a
       "Daily" note.
    4. A backlinks processing system, for automatically inserting so-called
         "backlinks" into notes.
    5. A quick open popup with fuzzy completion for jumping to a specific note
       or #tag.
    
    This module wraps some of the Bear "x-callback-url" API
    ( https://bear.app/faq/X-callback-url%20Scheme%20documentation/ ) with
    convenience Lua functions. The wrapping is done using the xcall command-line
    tool which implements the x-callback-url in a synchronous fashion.
    The bottom line is that you can automate Bear from Hammerspoon.

    For speed, some of the read-only functions skip calling the Bear remote API,
    and directly read from the Bear SQLite database. This is much faster.

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
local fs = require("hs.fs")
local sqlite3 = require("hs.sqlite3")
local fnutils = require("hs.fnutils")
local urlevent = require("hs.urlevent")
local eventtap = require("hs.eventtap")

local xcall = dofile(hs.spoons.resourcePath("xcall.lua"))
local etlua = dofile(hs.spoons.resourcePath("etlua.lua"))
local fuzzy = dofile(hs.spoons.resourcePath("fuzzy.lua"))

obj.token = nil
obj.template_env = {}


---
--- Bear API
--- 


--[[
    Use of the Bear SQLite DB. As documented here
    https://bear.app/faq/Where%20are%20Bear's%20notes%20located/ we use the
    underlying SQLite DB in a *READ ONLY* mode, and close the connection
    explicityly and promptly after use. Reading directly from the database is a
    faster than using Bear's API (fewer process context switches)
]]
local dbpath = fs.pathToAbsolute("~/Library/Group Containers/9K33E3U3T4.net.shinyfrog.bear/Application Data/database.sqlite")
local all_fields = "ZUNIQUEIDENTIFIER, ZCREATIONDATE, ZMODIFICATIONDATE, ZTITLE, ZTEXT"
local search_fields = "ZUNIQUEIDENTIFIER, ZCREATIONDATE, ZMODIFICATIONDATE, ZTITLE, ''"

-- convert a db result row to a table that mimics the Bear API response
local function noteFromRow(row)
    return {
        identifier = row[1],
        created = row[2],
        modified = row[3],
        title = row[4],
        note = row[5],
    }
end

--- Get a note from the Bear DB, keyed either by its identifier or by its title.
function obj:getNoteDB(id, title)
    local where = ""
    if title then
        where = "ZTITLE = '" .. title .. "'"
    elseif id then
        where = "ZUNIQUEIDENTIFIER = '" .. id .. "'"
    else
        return nil
    end
    local db = sqlite3.open(dbpath)
    local result = nil
    local query = "select " .. all_fields .. " from ZSFNOTE where ZTRASHED=0 and " .. where .. " limit 1;"
    for row in db:rows(query) do
        result = noteFromRow(row)
        break
    end
    db:close()
    return result
end

--- search for all notes matching a term
function obj:searchNotesDB(term)
    local results = {}
    local query = "select " .. search_fields .. " from ZSFNOTE where ZTRASHED=0 and ZTEXT like '%" .. term .. "%';"
    local db = sqlite3.open(dbpath)
    for row in db:rows(query) do
        table.insert(results, noteFromRow(row))
    end
    db:close()
    return results
end

--- bear:openNote(title, show_window, edit)
--- method
--- Opens a note in Bear by id or matching title
---
--- Parameters:
---  * id - the identifier the note to open or nil to open by title
---  * title - the title of the note to open
---  * show_window - whether to show the window after opening [default true]
---  * edit - whether to edit the note after opening [default false]
---
--- Returns:
---  * a table of note data or a table of error data
function obj:openNote(id, title, show_window, edit)
    if show_window == nil or show_window == true then
        show_window = "yes"
    else
        show_window = "no"
    end
    if edit == nil or edit == false then
        edit = "no"
    else
        edit = "yes"
    end
    local params = {show_window = show_window, edit = edit}
    if id then
        params.id = id
    elseif title then
        params.title = title
    else
        log.e("missing id or title")
        return nil
    end
    log.d("Opening note:" , id, title, hs.inspect(params))
    return xcall.call("bear", "open-note", params)
end

--- bear:openTag(tag)
--- method
--- Opens the tag list of notes
---
--- Parameters:
---  * tag - whether to edit the note after opening
---
--- Returns:
---  * nothing
function obj:openTag(tag)
    return xcall.call("bear", "open-tag", {name = tag})
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
--- Search Bear via the API using the given term, returning a table of results.
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
    return results and hs.json.decode(results.notes)
end

--- bear:tags(term)
--- method
--- Get all in-use tags
---
--- Parameters:
--- * none
---
--- Returns:
---  * a list (table) of tags
function obj:tags()
    if not obj.token then
        log.e("No token, cannot get tags")
        return nil
    end
    results = xcall.call("bear", "tags", {
        token = obj.token,
    })
    return results and fnutils.map(hs.json.decode(results.tags), function(tag)
        return tag.name
    end)
end

--- bear:createNote(content)
--- method
--- Create a new note with the given content.
---
--- Parameters:
--- * content - the new content of the note
--- * show_window - whether to show the window after opening [default true]
--- * edit - whether to edit the note after opening [default false]
---
--- Returns:
---  * The unique note identifier, a string.
function obj:createNote(content, show_window, edit)
    if show_window == nil or show_window == true then
        show_window = "yes"
    else
        show_window = "no"
    end
    if edit == nil or edit == false then
        edit = "no"
    else
        edit = "yes"
    end
    resp = xcall.call("bear", "create", {
        show_window = show_window,
        edit = edit,
        text = content,
    })
    if not resp then
        log.e("Failed to create note")
        return nil
    end
    return resp.identifier
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


---
--- Templates
---


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
    resp = obj:getNoteDB(tid)
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
    input = resp.note
    --[[ strip out and evaluate template code blocks of the form:
        ```lua
        -- BEAR_TEMPLATE
        x = 1
        y = 2
        ...
        ```
    ]]
    input = string.gsub(input, "\n```lua\n%-%- BEAR_TEMPLATE\n(.-)\n```", "<%% %1 %%>")
    local output = etlua.render(input, env)
    if not output then
        log.e("Failed to compile template text", input, env)
        return nil
    end
    return obj:createNote(output)
end

-- Treat the currently selected note (if any) as a template, and create a new
-- note from it.
function obj.newFromCurrentTemplate()
    local current = obj:getCurrent()
    if not current then
        return
    end
    nid = obj:createFromTemplate(current.identifier)
    eventtap.keyStroke({'cmd'}, 'up', 0)
    eventtap.keyStroke({}, 'down', 0)
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

local function tag(txt)
    return "#" .. txt
end

obj.template_env = {
    today = today,
    tomorrow = tomorrow,
    yesterday = yesterday,
    date = date,
    isodate = isodate,
    link = link,
    tag = tag,
}

---
--- Daily Journal
---

local function activateApp(bundleId)
    b = hs.application.applicationsForBundleID(bundleId)
    if b and b[1] then
        b[1]:activate()
    end
end

-- parse date
local function parseDate(dateStr)
    local y, m, d = dateStr:match("(%d+)%-(%d+)%-(%d+)")
    if not y or not m or not d then
        return nil
    end
    return os.time({year=y, month=m, day=d})
end

--- prompt the user to enter a date
local function promptDate()
    local tod = os.date("%Y-%m-%d")
    activateApp("org.hammerspoon.Hammerspoon")
    local btn, date = hs.dialog.textPrompt("Enter date", "Format YYYY-MM-DD", tod, "OK", "Cancel")
    activateApp("net.shinyfrog.bear")
    if btn ~= "OK" or not date then
        return nil
    end
    local result = parseDate(date)
    if not result then
        hs.alert.show("Invalid date")
    end
    return result
end

-- create or open a new "today" note, based on my "daily" template
function obj.openJournalToday()
    local today = os.time()
    obj.openJournal(today)
end

function obj.openJournalAtDate()
    local t = promptDate()
    if not t then
        return
    end
    obj.openJournal(t)
end

function obj.openJournal(date)
    -- construct the title of the today note, and open it:
    local title = obj.template_env["journalTitle"](date)
    log.d("title:", title)
    local note = obj:openNote(nil, title, true, true)
    if note then
        -- found it:
        log.d("found id:" .. note.identifier)
    else
        -- not found -- create using our template
        log.d("Creating new today note:" .. title)
        env = {journalDate = date}
        nid = obj:createFromTemplate(obj.template_env["journalTemplateId"], env)
        -- and force open:
        obj:openNote(nid, nil, true, true)
    end
    activateApp("net.shinyfrog.bear")
    -- put the cursor in a nice place
    eventtap.keyStroke({'cmd'}, 'up', 0)
    for i = 1, 4 do
        eventtap.keyStroke({}, 'down', 0)
    end
end

---
--- Callback Handlers
---

-- handle hammerspoon://bear/<cmd> URLs
-- these are used for Bear to communicate with this Hammerspoon extension
local function _callbackHandler(eventName, params)
    if params.cmd == "journal-goto" then
        if params.date == "today" then
            obj.openJournalToday()
        else
            date = parseDate(params.date)
            if date then
                obj.openJournal(date)
            end
        end
    end
end

---
--- Backlinks
---

-- Backlinks processing
-- This code is very lightly ported from https://github.com/cdzombak/bear-backlinks
-- and is too "pythonic".
-- TODO: make this more lua-ish

local backlink_header = "## Backlinks"

function obj._composeBacklinks(sources)
    -- given a list of sources, compose a backlinks section
    local output = ""
    if #sources == 0 then
        output = "_No backlinks found._"
    else
        -- sort the sources by title
        table.sort(sources, function(a,b) return a.title > b.title end)
        links = fnutils.imap(sources, function(n)
            return "* [[" .. n.title .. "]]"
        end)
        output = table.concat(links, "\n")
    end
    return "\n" .. output .. "\n"
end

-- fn to split a string by pattern,
-- from https://stackoverflow.com/questions/1426954/split-string-in-lua
function string:split(pat)
    pat = pat or '%s+'
    local st, g = 1, self:gmatch("()("..pat..")")
    local function getter(segs, seps, sep, cap1, ...)
        st = sep and seps + #sep
        return self:sub(segs, (seps or 0) - 1), cap1 or sep, ...
    end
    return function() if st then return getter(st, g()) end end
end

local function split(str, pat)
    local t = {}
    for s in str:split(pat) do
        table.insert(t, s)
    end
    return t
end

function obj._processBacklinks(nid, sources)
    -- for a given target note (nid) and a list of source notes (sources),
    -- compose a backlinks section and update the target note.

    -- we re-read the note from the DB (even though we have the contents in the
    -- parent caller), because the note contents may have changed.
    note = obj:getNoteDB(nid)
    log.i("processing backlinks:", note.title)
    new_backlinks = obj._composeBacklinks(sources)
    -- chop the notes into pre and post backlinks sections
    parts = split(note.note, backlink_header)
    if #parts < 2 then
        log.w("missing backlinks header:", note.id, note.title)
        return nil
    end
    if #parts > 2 then
        log.i("mulitple backlinks header. will use last one:", note.title)
    end
    pre = {}
    for i = 1, #parts - 1 do
        table.insert(pre, parts[i])
    end
    pre_backlinks = table.concat(pre, backlink_header .. "\n") .. backlink_header
    -- find the backlinks footer section
    footer_parts = split(parts[#parts], "%-%-%-")
    if #footer_parts < 2 then
        log.w("missing --- in footer:", note.title)
        return nil
    end
    old_backlinks = table.remove(footer_parts, 1)
    post_backlinks = "---" .. table.concat(footer_parts, "---")
    -- if the backlinks have change, update the note
    if old_backlinks == new_backlinks then
        log.i("backlinks already up to date:", note.title)
        return nil
    end
    new_content = pre_backlinks .. new_backlinks .. post_backlinks
    -- don't actually update the content here -- just return the new data
    -- We collect and update later in one shot.
    return {id = nid, text = new_content, title = note.title}
end

--- obj.processBacklinks(nid)
--- Function
--- Scan all notes in Bear, looking for those that have opted in to the "backlinks"
--- feature. This is done by putting in a section like this:
--- ```
--- ## Backlinks
--- ---
--- ```
--- usually at the end of the note.
--- For every note that has this section, we scan all notes for inbound links
--- to this note, and construct a table of these links in this (target) note.
---
--- WARNING
--- Since this modifies notes, you should backup your Bear notes before running
--- WARNING
---
function obj.updateBacklinks()
    local need_backlinks = obj:searchNotesDB("\n" .. backlink_header)
    -- maps a source note ID to a list of note IDs that link to the source
    local backlinks = {}
    for _, note in pairs(need_backlinks) do
        local title = note.title
        log.d("looking for links to:", title)
        sources = obj:searchNotesDB("[[" .. title .. "]]")
        sources = fnutils.imap(sources, function(n)
            return {id = n.identifier, title = n.title}
        end)
        -- may be empty, indicating the note needs backlinks, but there are none
        backlinks[note.identifier] = sources
    end
    -- collect changes
    local to_change = {}
    for nid, sources in pairs(backlinks) do
        n = obj._processBacklinks(nid, sources)
        if n then
            to_change[n.id] = n
        end
    end
    -- process changes
    local changed = 0
    for _, note in pairs(to_change) do
        obj:replaceContent(note.id, note.text)
        log.i("backlinks updated", note.id, note.title)
        changed = changed + 1
    end

    hs.alert.show("Updated: " .. tostring(changed))
end

---
--- Quick open popup
---

function obj.noteChooser()
    all = fnutils.map(
        obj:searchNotesDB(""),
        function(n) return {text=n.title, id=n.identifier, subText=""} end
    )
    fnutils.concat(all,
        fnutils.map(
            obj:tags(),
            function(n) return {text="#" .. n, tag=n, subText=""} end
        )
    )
    local f = fuzzy.new(all, function(c)
        if c then
            if string.sub(c.text, 1, 1) == "#" then
                obj:openTag(c.tag)
            else
                obj:openNote(c.id, nil, true, true)
                eventtap.keyStroke({'cmd'}, 'up', 0)
                eventtap.keyStroke({}, 'down', 0)
            end
        end
    end)
    -- f.chooser:fgColor({hex="#bbf"})
    f.chooser:width(30)
    f.chooser:show()
end

---
--- Object initialization
---

function obj.initFromNote()
    local config = "Hammerspoon-Bear Configuration"
    log.i("Looking for a note called '" .. config .. "' for the following settings:")
    log.i("  bearToken (a string)")
    log.i("  journalTemplateId (a string)")
    log.i("  journalTitle (a function)")
    note = obj:getNoteDB(nil, config)
    if note then
        log.i("found configuration note")
        code = string.match(note.note, "\n```lua\n(.-)\n```")
        if code then
            f = load(code)
            if f then
                f()
                if bearToken ~= nil then
                    log.i("bearToken found")
                    obj.token = bearToken
                    bearToken = nil
                end
                if journalTemplateId ~= nil then
                    log.i("journal template:", journalTemplateId)
                    obj.template_env["journalTemplateId"] = journalTemplateId
                    journalTemplateId = nil
                end
                if journalTitle ~= nil then
                    log.i("defined journal title function.")
                    obj.template_env["journalTitle"] = journalTitle
                end
            end
        end
    end
end

function obj.init(api_token)
    obj.token = api_token
    obj.initFromNote()
    if obj.token == nil then
        log.w("no bear API token")
    end
    if obj.template_env["journalTemplateId"] == nil then
        log.w("no journal template ID found")
    end
    if obj.template_env["journalTitle"] == nil then
        log.w("no journal title function found")
    end
    urlevent.bind("bear", _callbackHandler)
end

return obj
