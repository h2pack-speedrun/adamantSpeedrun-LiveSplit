local deps = ...
local timer = deps.timer

local settings = {}
local MODE_ALIASES = {
    igt = "ShowIGT",
    rta = "ShowRTA",
    lrt = "ShowLrT",
}

function settings.isRawTimerRowsEnabled(runtime)
    return runtime.data.read("ShowRawTimers") == true
        and timer.recording.status().kind == "active"
end

function settings.isRecordingTableVisible(runtime)
    return runtime.data.read("ShowRecordingTable") == true
end

--- The single-run splits table; hidden when the multi-run table already shows the current
--- attempt's splits.
function settings.isSplitsTableVisible(runtime)
    return settings.isRecordingTableVisible(runtime)
        and not (timer.recording.isMultiRunMode() == true and timer.batch.keepsSplits() == true)
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
