local deps = ... or {}
local singleRun = deps.singleRun
local recording = deps.recording
local splits = deps.splits
local batch = deps.batch
local getCurrentRun = deps.getCurrentRun
local emit = deps.emit or function() end
local eventNames = deps.events

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
        onRunStarted = function(runtime)
            recording.onRunStarted(getCurrentRun(), activeTimer(), snapshot())
            emit(eventNames.currentRunStarted, runtime)
            emit(eventNames.currentRunSummaryChanged, runtime)
            emit(eventNames.currentRunDetailsChanged, runtime)
            emit(eventNames.batchSessionChanged, runtime)
        end,
        onDisplayLoopStarted = function(runtime)
            emit(eventNames.currentRunDisplayStarted, runtime)
            emit(eventNames.currentRunSummaryChanged, runtime)
        end,
        onLoadEvent = function(runtime, isLoading)
            recording.onLoadEvent(isLoading)
            emit(isLoading and eventNames.loadRemovalStarted or eventNames.loadRemovalEnded, runtime)
            emit(eventNames.currentRunSummaryChanged, runtime)
            emit(eventNames.batchSessionChanged, runtime)
        end,
        onRunFinalized = function(runtime)
            recording.onRunFinalized(activeTimer(), getCurrentRun(), snapshot())
            emit(eventNames.currentRunFinalized, runtime)
            emit(eventNames.currentRunSummaryChanged, runtime)
            emit(eventNames.currentRunDetailsChanged, runtime)
            emit(eventNames.batchSessionChanged, runtime)
            emit(eventNames.recordingStatusChanged, runtime)
        end,
        onDisplayChanged = function(runtime)
            updateLiveRecordingRows(activeTimer(), getCurrentRun(), snapshot())
            emit(eventNames.currentRunSummaryChanged, runtime)
            emit(eventNames.currentRunDetailsChanged, runtime)
        end,
    })
end

return runLoop
