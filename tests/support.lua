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
        -- Table storage: an in-memory stand-in for a Lib table handle (colon-call methods).
        get = function(alias)
            backing[alias] = backing[alias] or {}
            local rows = backing[alias]
            local function copy(row)
                local result = {}
                for key, value in pairs(row) do
                    result[key] = value
                end
                return result
            end
            return {
                count = function()
                    return #rows
                end,
                append = function(_, row)
                    rows[#rows + 1] = copy(row)
                    return true
                end,
                insert = function(_, index, row)
                    table.insert(rows, index, copy(row))
                    return true
                end,
                remove = function(_, index)
                    table.remove(rows, index)
                    return true
                end,
                clear = function()
                    for index = #rows, 1, -1 do
                        rows[index] = nil
                    end
                    return true
                end,
                snapshots = function()
                    local result = {}
                    for index, row in ipairs(rows) do
                        result[index] = copy(row)
                    end
                    return result
                end,
            }
        end,
    }
end

-- Runs callback with a test `import`; `overrides` maps import paths to stand-in modules.
function support.withImport(callback, overrides)
    local previousImport = _G.import
    _G.import = function(path, _, deps)
        if overrides and overrides[path] ~= nil then
            return overrides[path]
        end
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

support.keys = dofile("src/timer/keys.lua")
support.routeOf = support.keys.routeOf
support.resolveKeys = support.keys.resolve
support.Session = assert(loadfile("src/timer/session.lua"))({
    core = support.core,
})
support.newSession = support.Session.new
support.store = dofile("src/timer/session_store.lua")
support.categories = dofile("src/timer/categories.lua")

--- Settings of the old multi-run batch (Custom with default rules) for `runs` runs.
function support.batchSettings(runs)
    return support.categories.settingsFor("custom", {
        read = function(alias)
            if alias == "BatchTargetRuns" then
                return runs
            end
            return nil
        end,
    })
end

function support.batchDeps()
    return {
        newSession = support.newSession,
        isRunSuccess = support.isRunSuccess,
        keys = support.keys,
        categoryNames = support.categories.NAMES,
    }
end

--- Recording dependencies shared by tests; game reads default to "no save loaded".
function support.recordingDeps(overrides)
    local result = {
        normalizeRecordingMode = support.data.normalizeRecordingMode,
        newSession = support.newSession,
        restoreSession = support.Session.restore,
        resolveKeys = support.resolveKeys,
        isRunSuccess = support.isRunSuccess,
        currentRunOrdinal = function()
            return nil
        end,
        findRunResult = function()
            return nil
        end,
        store = support.store,
        categories = support.categories,
    }
    for key, value in pairs(overrides or {}) do
        result[key] = value
    end
    return result
end

function support.isRunSuccess(run)
    return run ~= nil and run.Cleared == true
end

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

-- Recomputes split rows and returns biome row `index`, or nil when that row is empty.
function support.splitRow(splits, index, timer, run, snapshot)
    splits.updateRows(timer, run, snapshot)
    local row = splits.details().biomes[index]
    if row.label == "" then
        return nil
    end
    return row
end

return support
