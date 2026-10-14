local deps = ...
local splits = deps.splits
local batch = deps.batch

local recording = {}
local currentMode = nil
local recordingReady = false

local function normalizeMode(mode)
    if mode == "single" or mode == "multi" then
        return mode
    end
    return "single"
end

local function readRecordingMode(runtime)
    return normalizeMode(runtime.data.read("RecordingMode"))
end

local function readTargetRuns(runtime)
    return runtime.data.read("BatchTargetRuns")
end

local function isRecordingReady(runtime)
    if runtime == nil then
        return recordingReady == true
    end
    return runtime.status.read("RecordingReady") == true
end

local function setRecordingReady(runtime, value)
    recordingReady = value == true
    runtime.status.write("RecordingReady", recordingReady)
end

local function clearSingleRecording(keepReady)
    splits.clear(keepReady == true)
end

local function clearBatchRecording(targetRuns)
    batch.clear(targetRuns)
end

local function startBatchRecording(targetRuns)
    batch.start(targetRuns)
end

local function stopBatchRecording()
    batch.stop()
end

function recording.getMode()
    return currentMode or "single"
end

function recording.isMultiRunMode()
    return recording.getMode() == "multi"
end

function recording.syncSettings(runtime)
    local previousMode = currentMode
    local previousReady = recordingReady
    local nextMode = readRecordingMode(runtime)
    local nextTargetRuns = readTargetRuns(runtime)
    local nextReady = isRecordingReady(runtime)

    currentMode = nextMode
    recordingReady = nextReady

    if not nextReady then
        if previousReady then
            stopBatchRecording()
            clearSingleRecording(false)
        end
        return
    end

    if nextMode == "multi" then
        if previousMode ~= "multi" then
            clearSingleRecording(true)
            startBatchRecording(nextTargetRuns)
            return
        end
        if not batch.isReady() then
            startBatchRecording(nextTargetRuns)
            return
        end
        if batch.targetRuns() ~= nextTargetRuns and not batch.hasProgress() then
            startBatchRecording(nextTargetRuns)
        end
        return
    end

    if previousMode == "multi" then
        clearBatchRecording(nextTargetRuns)
    end

    if not splits.isStarted() then
        clearSingleRecording(true)
    end
end

function recording.status()
    if recording.isMultiRunMode() then
        return batch.status()
    end
    return splits.status()
end

function recording.start(runtime)
    local targetRuns = readTargetRuns(runtime)
    setRecordingReady(runtime, true)
    currentMode = readRecordingMode(runtime)
    if recording.isMultiRunMode() then
        clearSingleRecording(true)
        startBatchRecording(targetRuns)
    else
        clearBatchRecording(targetRuns)
        clearSingleRecording(true)
    end
end

function recording.clear(runtime)
    local targetRuns = readTargetRuns(runtime)
    clearBatchRecording(targetRuns)
    clearSingleRecording(isRecordingReady(runtime))
end

function recording.stop(runtime)
    setRecordingReady(runtime, false)
    stopBatchRecording()
    clearSingleRecording(false)
end

-- Drops in-progress recording state while the module is disabled but keeps it armed:
-- RecordingReady is left as-is, so syncSettings re-arms recording when the module is enabled again.
function recording.suspend()
    stopBatchRecording()
    clearSingleRecording(false)
end

function recording.onRunStarted(run)
    if isRecordingReady() then
        splits.startRun(run)
    end
    if recording.isMultiRunMode() then
        batch.startRun()
    end
end

function recording.onLoadEvent(isLoading)
    if recording.isMultiRunMode() then
        batch.processLoadEvent(isLoading)
    end
end

function recording.onRunFinalized(runtime, timer, run, snapshot)
    if recording.isMultiRunMode() then
        batch.finalizeRun(timer, run)
        -- A completed or failed batch disarms recording so its result stays until Start New.
        if not batch.isActive() then
            setRecordingReady(runtime, false)
        end
    else
        splits.finalizeRun(timer, run, snapshot)
    end
end

function recording.initialize(runtime)
    currentMode = readRecordingMode(runtime)
    recordingReady = isRecordingReady(runtime)

    if currentMode == "multi" then
        clearSingleRecording(recordingReady)
        if recordingReady then
            startBatchRecording(readTargetRuns(runtime))
        else
            stopBatchRecording()
        end
    else
        clearBatchRecording(readTargetRuns(runtime))
        clearSingleRecording(recordingReady)
    end
end

return recording
