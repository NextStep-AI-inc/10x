-- Install this template manually from 10x's application bundle. It deliberately
-- exposes only the fixed desktop-integration surface used by the app.
tenx = tenx or {}
tenx.integrationVersion = "1.0.0"
-- Set this in your own init.lua after loading the template. 10x never writes it.
tenx.workspaceID = tenx.workspaceID or nil

local watcher = nil

local function validID(value)
    return type(value) == "string" and value:match("^[0-9]+$") ~= nil and tonumber(value) > 0
end

local function checkedWindow(windowID)
    if not validID(windowID) then return nil end
    return hs.window.get(tonumber(windowID))
end

local function checkedSpace(spaceID)
    if not validID(spaceID) then return nil end
    return tonumber(spaceID)
end

local function checkedUserSpace(spaceID)
    local space = checkedSpace(spaceID)
    if space == nil then return nil end
    local resolved, spaceType = pcall(hs.spaces.spaceType, space)
    if not resolved or spaceType ~= "user" then return nil end
    return space
end

local function containsSpace(spaces, target)
    if type(spaces) ~= "table" then return false end
    for _, space in ipairs(spaces) do
        if tonumber(space) == target then return true end
    end
    return false
end

function tenx.probe()
    local workspace = checkedUserSpace(tenx.workspaceID)
    return {
        integrationVersion = tenx.integrationVersion,
        workspaceID = workspace and tostring(workspace) or nil,
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
    local space = checkedUserSpace(workspaceID)
    if window == nil or space == nil then return { ok = false } end
    local moved = hs.spaces.moveWindowToSpace(window:id(), space) == true
    local inspected, spaces = pcall(hs.spaces.windowSpaces, window:id())
    return { ok = moved and inspected and containsSpace(spaces, space) }
end

function tenx.restoreWindow(windowID, workspaceID)
    return tenx.moveWindow(windowID, workspaceID)
end

function tenx.openSpace(workspaceID)
    local space = checkedUserSpace(workspaceID)
    if space == nil then return { ok = false } end
    local opened = hs.spaces.gotoSpace(space) == true
    local inspected, focused = pcall(hs.spaces.focusedSpace)
    return { ok = opened and inspected and tonumber(focused) == space }
end

function tenx.stopWatcher()
    if watcher ~= nil then
        watcher:unsubscribeAll()
        watcher = nil
    end
    return { ok = true }
end

return tenx
