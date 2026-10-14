local support = dofile("tests/support.lua")
local assertEqual = support.assertEqual
local withImport = support.withImport

local beginCount = 0
local projectedLines = {}
local projectedTables = {}
local refreshOwnedCount = 0

local settingsFake = {
    isTimerDisplayVisible = function()
        return true
    end,
    isModeVisible = function(mode)
        return mode ~= "rta"
    end,
    isBatchVisible = function()
        return false
    end,
    isRecordingTableVisible = function()
        return false
    end,
}
local projectionFake = {
    begin = function()
        beginCount = beginCount + 1
    end,
    displayTime = function(row, mode)
        row.time = mode .. "-time"
    end,
    batchSession = function()
        return {
            runs = {},
            current = {},
        }
    end,
}

withImport(function()
    local display = assert(loadfile("src/display/display.lua"))({
        fonts = support.fonts,
        timer = {
            batch = {
                hasSession = function()
                    return false
                end,
                session = function()
                    return {
                        runs = {},
                        current = {},
                    }
                end,
            },
            currentRun = {
                hasDetails = function()
                    return false
                end,
                detailsSnapshot = function()
                    return {
                        biomes = {},
                        total = {},
                    }
                end,
            },
        },
    })

    display.project({
        setLine = function(name, values)
            projectedLines[name] = values
        end,
        setTable = function(name, rows)
            projectedTables[name] = rows
        end,
        refreshOwned = function()
            refreshOwnedCount = refreshOwnedCount + 1
        end,
    }, {
        runtime = {},
    })
end, {
    ["display/settings.lua"] = settingsFake,
    ["display/projection.lua"] = projectionFake,
})

assertEqual(beginCount, 1)
assertEqual(projectedLines["summary.igt"].time, "igt-time")
assertEqual(projectedLines["summary.rta"].time, "")
assertEqual(projectedLines["summary.lrt"].time, "lrt-time")
assertEqual(type(projectedTables.batch), "table")
assertEqual(type(projectedTables.splits), "table")
assertEqual(refreshOwnedCount, 1)

-- Page hotkeys: one always-draw registration across reloads; keys page only while active and the
-- Hell2Modding overlay is closed.
local drawCallbacks = {}
local pressed = {}
local guiOpen = false
local previousRom = _G.rom
_G.rom = {
    ImGuiKey = { F7 = "key-f7", F8 = "key-f8" },
    ImGui = {
        IsKeyPressed = function(key)
            return pressed[key] == true
        end,
    },
    gui = {
        add_always_draw_imgui = function(callback)
            drawCallbacks[#drawCallbacks + 1] = callback
        end,
        is_open = function()
            return guiOpen
        end,
    },
}
local pageCalls = {}
local pagingActive = true
local function loadHotkeys()
    return assert(loadfile("src/display/page_hotkeys.lua"))({
        paging = {
            previous = function()
                pageCalls[#pageCalls + 1] = "previous"
            end,
            next = function()
                pageCalls[#pageCalls + 1] = "next"
            end,
        },
        isPagingActive = function()
            return pagingActive
        end,
    })
end
local hotkeys = loadHotkeys()
hotkeys.install()
local hotkeyRuntime = {
    data = {
        read = function(alias)
            return ({ PagePrevKey = "F7", PageNextKey = "F8" })[alias]
        end,
    },
}
hotkeys.setLive({ isEnabled = function() return true end }, hotkeyRuntime)
pressed["key-f7"] = true
drawCallbacks[1]()
assertEqual(pageCalls[1], "previous")
guiOpen = true
drawCallbacks[1]()
assertEqual(#pageCalls, 1)
guiOpen = false
pagingActive = false
drawCallbacks[1]()
assertEqual(#pageCalls, 1)
pagingActive = true
-- A reload replaces the tick without registering a second callback.
local reloaded = loadHotkeys()
reloaded.install()
assertEqual(#drawCallbacks, 1)
reloaded.setLive({ isEnabled = function() return true end }, hotkeyRuntime)
pressed["key-f7"] = false
pressed["key-f8"] = true
drawCallbacks[1]()
assertEqual(pageCalls[2], "next")
_G.rom = previousRom
AdamantLiveSplit_PageHotkeys = nil
