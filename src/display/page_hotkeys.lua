-- Overlay page keys, requested from ModpackLib's hotkeys capability. Lib owns the bindings, reports
-- conflicts with other modules, and dispatches presses; LiveSplit only pages.

local deps = ...
local paging = deps.paging
local isPagingActive = deps.isPagingActive
local pageKeys = deps.pageKeys

local pageHotkeys = {}

function pageHotkeys.attach(module)
    module.hotkeys.request(pageKeys.previous.id, {
        label = "Previous page",
        default = pageKeys.previous.default,
        alias = pageKeys.previous.alias,
        tooltip = "Shows older finished runs in the multi-run overlay. Returns to the newest page when a run finishes.",
        onPress = function()
            if isPagingActive() then
                paging.previous()
            end
        end,
    })
    module.hotkeys.request(pageKeys.next.id, {
        label = "Next page",
        default = pageKeys.next.default,
        alias = pageKeys.next.alias,
        tooltip = "Shows newer finished runs; past the last page the overlay follows the newest runs again.",
        onPress = function()
            if isPagingActive() then
                paging.next()
            end
        end,
    })
end

return pageHotkeys
