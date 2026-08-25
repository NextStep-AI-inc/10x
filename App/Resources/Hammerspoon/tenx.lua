-- Install this template manually from 10x's application bundle. It deliberately
-- exposes only the fixed desktop-integration surface used by the app.
tenx = tenx or {}
tenx.integrationVersion = "1.0.0"
-- Set this in your own init.lua after loading the template. 10x never writes it.
tenx.workspaceID = tenx.workspaceID or nil

local watcher = nil

local function validID(value)
    return type(value) == "string" and value:match("^[A-Za-z0-9._-]+$") ~= nil
end

local function checkedWindow(windowID)
    if not validID(windowID) then return nil end
    return hs.window.get(tonumber(windowID))
end

local function checkedSpace(spaceID)
    if not validID(spaceID) then return nil end
    return tonumber(spaceID) or spaceID
end

function tenx.probe()
    return {
        integrationVersion = tenx.integrationVersion,
        workspaceID = tenx.workspaceID,
        capabilities = {
            canIsolate = true,
            canMoveWithoutFocus = true,
            canCaptureOffscreen = true,
            canInputInBackground = true,
        },
    }
end

function tenx.listWindows()
    local windows = {}
    for _, window in ipairs(hs.window.allWindows()) do
        local id = tostring(window:id())
        if validID(id) then
            table.insert(windows, {
                id = id,
                processID = window:application():pid(),
                app = window:application():name(),
                workspaceID = nil,
            })
        end
    end
    return windows
end

function tenx.startWatcher()
    if watcher ~= nil then return { ok = true } end
    watcher = hs.window.filter.new()
    watcher:subscribe({ hs.window.filter.windowCreated, hs.window.filter.windowDestroyed }, function() end)
    return { ok = true }
end

function tenx.moveWindow(windowID, workspaceID)
    local window = checkedWindow(windowID)
    local space = checkedSpace(workspaceID)
    if window == nil or space == nil then return { ok = false } end
    hs.spaces.moveWindowToSpace(window:id(), space)
    return { ok = true }
end

function tenx.restoreWindow(windowID, workspaceID)
    return tenx.moveWindow(windowID, workspaceID)
end

function tenx.openSpace(workspaceID)
    local space = checkedSpace(workspaceID)
    if space == nil then return { ok = false } end
    hs.spaces.gotoSpace(space)
    return { ok = true }
end

function tenx.stopWatcher()
    if watcher ~= nil then
        watcher:unsubscribeAll()
        watcher = nil
    end
    return { ok = true }
end
