local deps = ...
local timer = deps.timer

local settings = {}
local MODE_ALIASES = {
    igt = "ShowIGT",
    rta = "ShowRTA",
    lrt = "ShowLrT",
}

--- Timer only: the compact IGT/RTA/LrT rows instead of a table.
function settings.isRawTimerRowsEnabled(runtime)
    return runtime.data.read("OverlayMode") == "timer"
end

function settings.isRecordingTableVisible(runtime)
    return runtime.data.read("OverlayMode") ~= "timer"
end

--- The single-run splits table. Multi-run categories show the current run's splits inside the
--- session table instead.
function settings.isSplitsTableVisible(runtime)
    return settings.isRecordingTableVisible(runtime)
        and timer.recording.isMultiRunMode() ~= true
end

function settings.isBatchVisible(runtime)
    return settings.isRecordingTableVisible(runtime)
        and timer.recording.isMultiRunMode() == true
end

function settings.pageSize(runtime)
    return runtime.data.read("PageSize")
end

function settings.isModeVisible(mode, runtime)
    local alias = MODE_ALIASES[mode]
    if not alias then
        return true
    end
    return runtime.data.read(alias) == true
end

function settings.isTimerDisplayVisible(runtime)
    local hasSingleRunSummary = timer.currentRun.hasSummary() == true
    local hasBatchSession = timer.batch.hasSession() == true
    return settings.isRawTimerRowsEnabled(runtime) == true
        and (hasSingleRunSummary or hasBatchSession)
end

return settings
