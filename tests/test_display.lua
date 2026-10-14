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
