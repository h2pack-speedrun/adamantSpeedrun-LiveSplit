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

local function updateLiveRecordingRows(runtime, timer, run, timerSnapshot)
    if timer then
        recording.adoptRun(run)
        splits.recordCompletedBiomes(timer, run, timerSnapshot)
        splits.updateLiveRows(timer, run, timerSnapshot)
        recording.captureBiomes(runtime, run)
    end
end

function runLoop.updateTick(runtime)
    local timer = singleRun.updateTick()
    updateLiveRecordingRows(runtime, timer, getCurrentRun(), snapshot())
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
        onRunStarted = function(runtime)
            recording.onRunStarted(runtime, getCurrentRun())
        end,
        onLoadEvent = function(runtime, isLoading)
            recording.onLoadEvent(isLoading)
            onChanged(runtime)
        end,
        onRunFinalized = function(runtime)
            recording.onRunFinalized(runtime, activeTimer(), getCurrentRun(), snapshot())
        end,
        onDisplayChanged = function(runtime)
            recording.onPlayResumed(runtime)
            updateLiveRecordingRows(runtime, activeTimer(), getCurrentRun(), snapshot())
            onChanged(runtime)
        end,
        onCheckpoint = function(runtime)
            recording.checkpoint(runtime)
        end,
    })
end

return runLoop
