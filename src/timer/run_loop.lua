local deps = ... or {}
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
    return true
end

function runLoop.hasActiveDisplayLoop()
    return singleRun.hasSummary() or batch.isActive()
end

function runLoop.ensureDisplayLoop()
    if singleRun.startDisplayLoop() then
        return runLoop.hasActiveDisplayLoop()
    end

    return runLoop.hasActiveDisplayLoop()
end

function runLoop.cleanup(runtime)
    singleRun.clear()
    recording.stop(runtime)
end

function runLoop.installHooks(hooks)
    singleRun.installHooks(hooks, {
        isEnabled = function(host)
            return host.isEnabled() == true
        end,
        onRunStarted = function()
            recording.onRunStarted(getCurrentRun(), activeTimer(), snapshot())
        end,
        onLoadEvent = function(runtime, isLoading)
            recording.onLoadEvent(isLoading)
            onChanged(runtime)
        end,
        onRunFinalized = function()
            recording.onRunFinalized(activeTimer(), getCurrentRun(), snapshot())
        end,
        onDisplayChanged = function(runtime)
            updateLiveRecordingRows(activeTimer(), getCurrentRun(), snapshot())
            onChanged(runtime)
        end,
    })
end

return runLoop
