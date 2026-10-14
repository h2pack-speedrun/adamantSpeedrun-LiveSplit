-- luacheck: globals AdamantLiveSplit_PageHotkeys
-- Overlay page hotkeys, polled every frame in the same way as Quick Pause's pause hotkey.
--
-- The always-draw callback is registered once on a persistent anchor and late-reads the current
-- tick, so a hot reload swaps behavior without registering a second callback.

local deps = ...
local paging = deps.paging
local isPagingActive = deps.isPagingActive

local pageHotkeys = {}
local live = {
    host = nil,
    runtime = nil,
}

local function resolveKey(name)
    local keys = rom.ImGuiKey
    if type(keys) ~= "table" or name == nil or name == "" then
        return nil
    end
    return keys[name] or keys["ImGuiKey_" .. name]
end

local function isPressed(runtime, alias)
    local key = resolveKey(runtime.data.read(alias))
    return key ~= nil and rom.ImGui.IsKeyPressed(key, false) == true
end

local function tick()
    local host, runtime = live.host, live.runtime
    if host == nil or runtime == nil or not host.isEnabled() then
        return
    end
    -- Keys typed into the Hell2Modding overlay are not page commands.
    if rom.gui.is_open() == true or not isPagingActive() then
        return
    end
    if isPressed(runtime, "PagePrevKey") then
        paging.previous()
    end
    if isPressed(runtime, "PageNextKey") then
        paging.next()
    end
end

--- Remembers the activated module's host and runtime for the tick.
function pageHotkeys.setLive(host, runtime)
    live.host = host
    live.runtime = runtime
end

function pageHotkeys.install()
    AdamantLiveSplit_PageHotkeys = AdamantLiveSplit_PageHotkeys or {}
    local anchor = AdamantLiveSplit_PageHotkeys
    anchor.tick = tick
    anchor.failed = false
    if anchor.registered then
        return
    end
    anchor.registered = true
    rom.gui.add_always_draw_imgui(function()
        local current = anchor.tick
        if current == nil or anchor.failed then
            return
        end
        local ok, err = pcall(current)
        if not ok then
            -- Report once instead of every frame; a reload installs a fresh tick and clears this.
            anchor.failed = true
            print("[LiveSplit] page hotkey tick disabled: " .. tostring(err))
        end
    end)
end

return pageHotkeys
