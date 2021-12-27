-- bear.lua
-- interact with the Bear app from Hammerspoon, using the xcall library
-- which uses the x-callback-url mechanism to communicate with Bear.
-- Uses etlua for simple templating language

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Bear"
obj.version = "1.0"
obj.author = "@dcreemer"
obj.homepage = "https://github.com/dcreemer/hammerspoon-bear"
obj.license = "MIT - https://opensource.org/licenses/MIT"

local log = hs.logger.new('bear', 'info')

local xcall = dofile(hs.spoons.resourcePath("xcall.lua"))
local etlua = dofile(hs.spoons.resourcePath("etlua.lua"))

obj.token = nil
obj.template_env = {}

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
    log.d('Opening note: ' .. title)
    return xcall.call("bear", "open-note", params)
end

function obj:openById(id, show_window)
    show_window = "yes"
    edit = "no"
    if show_window == false then
        show_window = "no"
    end
    if edit == false then
        edit = "no"
    end
    local params = {show_window = show_window, edit = edit, id = id}
    log.d('Opening note: ' .. id)
    return xcall.call("bear", "open-note", params)
end

function obj:getLink(id, title)
    local params = {show_window = "yes", edit = "yes"}
    if id then
        params.id = id
    elseif title then
        params.title = title
    end
    return "bear://x-callback-url/open-note?" .. xcall.encode(params)
end

function obj:getCurrent()
    if not obj.token then
        log.e('No token, cannot get current note id')
        return nil
    end
    return xcall.call("bear", "open-note", {token = obj.token, selected = "yes"})
end

function obj:createFromTemplate(tid)
    resp = xcall.call("bear", "open-note", {id = tid})
    if not resp then
        log.e('Failed to open template note', tid)
        return nil
    end
    log.d('creating from template: ', resp.title)
    local output = etlua.render(resp.note, obj.template_env)
    if not output then
        log.e('Failed to compile template note', tid)
        return nil
    end
    resp = xcall.call("bear", "create",
                      {show_window = "yes", edit = "yes", text = output})
    if not resp then
        log.e('Failed to create note from template', tid)
        return nil
    end
    return resp.identifier
end

function obj:search(term)
    if not obj.token then
        log.e('No token, cannot search')
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

function obj:replaceContent(nid, content)
    if not obj.token then
        log.e('No token, cannot replace content')
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
        log.e('Failed to update note', nid)
    end
end

return obj
