local deps = ...
local singleRun = deps.singleRun
local recording = deps.recording
local splits = deps.splits
local batch = deps.batch
local getCurrentRun = deps.getCurrentRun
local onChanged = deps.onChanged

local runLoop = {}

local function activeTimer()
    return singleRun.getActiveTimer()
end

local function snapshot()
    return singleRun.getSnapshot()
end

local function updateLiveRecordingRows(timer, run, timerSnapshot)
    if timer then
        splits.recordCompletedBiomes(timer, run, timerSnapshot)
        splits.updateLiveRows(timer, run, timerSnapshot)
    end
end

function runLoop.updateTick()
    local timer = singleRun.updateTick()
    updateLiveRecordingRows(timer, getCurrentRun(), snapshot())
end

function runLoop.hasActiveDisplayLoop()
    return singleRun.hasSummary() or batch.isActive()
end

function runLoop.ensureDisplayLoop()
    singleRun.startDisplayLoop()
    return runLoop.hasActiveDisplayLoop()
end

function runLoop.cleanup()
    singleRun.clear()
    recording.suspend()
end

function runLoop.installHooks(hooks)
    singleRun.installHooks(hooks, {
        onRunStarted = function()
            recording.onRunStarted(getCurrentRun(), activeTimer(), snapshot())
        end,
        onLoadEvent = function(runtime, isLoading)
            recording.onLoadEvent(isLoading)
            onChanged(runtime)
        end,
        onRunFinalized = function(runtime)
            recording.onRunFinalized(runtime, activeTimer(), getCurrentRun(), snapshot())
        end,
        onDisplayChanged = function(runtime)
            updateLiveRecordingRows(activeTimer(), getCurrentRun(), snapshot())
            onChanged(runtime)
        end,
    })
end

return runLoop
