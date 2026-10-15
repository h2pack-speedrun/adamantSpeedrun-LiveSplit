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
    isSplitsTableVisible = function()
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

-- Page keys are requested from Lib with their old storage aliases; presses page only while active.
local requests = {}
local pageCalls = {}
local pagingActive = true
local pageHotkeys = assert(loadfile("src/display/page_hotkeys.lua"))({
    paging = {
        previous = function()
            pageCalls[#pageCalls + 1] = "previous"
        end,
        next = function()
            pageCalls[#pageCalls + 1] = "next"
        end,
    },
    pageKeys = support.data.pageKeys,
    isPagingActive = function()
        return pagingActive
    end,
})
pageHotkeys.attach({
    hotkeys = {
        request = function(id, opts)
            requests[id] = opts
        end,
    },
})
assertEqual(requests.PagePrev.alias, "PagePrevKey")
assertEqual(requests.PagePrev.default, "F7")
assertEqual(requests.PageNext.alias, "PageNextKey")
assertEqual(requests.PageNext.default, "F8")
requests.PagePrev.onPress()
requests.PageNext.onPress()
assertEqual(pageCalls[1], "previous")
assertEqual(pageCalls[2], "next")
pagingActive = false
requests.PagePrev.onPress()
assertEqual(#pageCalls, 2)
