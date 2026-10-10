local support = {}

local fakeTime = 0
_worldTime = 0

function support.assertEqual(actual, expected)
    if actual ~= expected then
        error(string.format("expected %q, got %q", expected, actual), 2)
    end
end

function support.setTime(value)
    fakeTime = value
    _worldTime = value
end

function support.currentRun()
    return CurrentRun
end

function support.getFakeTime()
    return fakeTime
end

function support.newRuntimeState(backing)
    backing = backing or {}
    local function aliasFromArgs(first, second)
        return second or first
    end
    return {
        read = function(first, second)
            local alias = aliasFromArgs(first, second)
            local value = backing[alias]
            if value == nil then
                return false
            end
            return value
        end,
        write = function(first, second, third)
            local alias = first
            local value = second
            if third ~= nil then
                alias = second
                value = third
            end
            backing[alias] = value
            return true
        end,
        reset = function(first, second)
            local alias = aliasFromArgs(first, second)
            local hadValue = backing[alias] ~= nil
            backing[alias] = nil
            return hadValue
        end,
    }
end

function support.withImport(callback)
    local previousImport = _G.import
    _G.import = function(path, _, deps)
        return assert(loadfile("src/" .. path))(deps)
    end
    local ok, result = pcall(callback)
    _G.import = previousImport
    if not ok then
        error(result, 2)
    end
    return result
end

support.core = support.withImport(function()
    return assert(loadfile("src/timer/core/00_init.lua"))({
        getTime = function()
            return fakeTime
        end,
        getCurrentRun = support.currentRun,
    })
end)

support.timeFormat = dofile("src/display/time_format.lua")

support.formatCache = assert(loadfile("src/display/format_cache.lua"))({
    formatCentiseconds = support.timeFormat.formatCentiseconds,
})

support.data = dofile("src/data.lua")

support.fonts = { numeric = "NumericP22UndergroundSCMedium" }

support.overlay = support.withImport(function()
    return assert(loadfile("src/display/overlay_rows.lua"))({
        fonts = support.fonts,
    })
end)

return support
