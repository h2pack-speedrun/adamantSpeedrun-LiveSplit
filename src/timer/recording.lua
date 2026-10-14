local deps = ...
local splits = deps.splits
local batch = deps.batch
local normalizeRecordingMode = deps.normalizeRecordingMode
local newSession = deps.newSession
local resolveKeys = deps.resolveKeys
local isRunSuccess = deps.isRunSuccess
local restoreSession = deps.restoreSession
local currentRunOrdinal = deps.currentRunOrdinal
local findRunResult = deps.findRunResult
local store = deps.store

local recording = {}
local currentMode = nil

-- Single-run mode is a one-run category session that starts over once a run counts.
local SINGLE_RUN_SETTINGS = {
    runs = 1,
    distinct = "none",
    same = "none",
    onDeath = "continue",
}
-- The single-run session while single-run recording is armed; nil when not armed.
local singleSession = nil

local function readRecordingMode(runtime)
    return normalizeRecordingMode(runtime.data.read("RecordingMode"))
end

local function readTargetRuns(runtime)
    return runtime.data.read("BatchTargetRuns")
end

local function isRecordingReady(runtime)
    return runtime.status.read("RecordingReady") == true
end

local function setRecordingReady(runtime, value)
    runtime.status.write("RecordingReady", value == true)
end

-- Whether batch or split recording is currently armed in memory.
local function isArmed()
    return batch.isReady() or splits.isStarted()
end

-- Ends recording after a finished batch while keeping its result rows visible.
local function disarm(runtime)
    setRecordingReady(runtime, false)
    splits.disarm()
    singleSession = nil
end

local function clearSingleRecording(keepReady)
    splits.clear(keepReady == true)
    singleSession = keepReady == true and newSession(SINGLE_RUN_SETTINGS) or nil
end

local function beginSingleAttempt(run)
    if singleSession == nil or singleSession:getOutcome() ~= nil then
        singleSession = newSession(SINGLE_RUN_SETTINGS)
    end
    singleSession:startAttempt(resolveKeys(run))
end

local function singleStatus()
    if singleSession == nil then
        return { kind = "idle", text = "Not recording" }
    end
    if singleSession:getActiveAttempt() ~= nil then
        return { kind = "active", text = "Recording current run" }
    end
    local lastAttempt = singleSession:getLastFinishedAttempt()
    if lastAttempt ~= nil and lastAttempt.status == "failed" then
        return { kind = "failed", text = "Recording failed" }
    end
    if lastAttempt ~= nil then
        return { kind = "recorded", text = "Recording complete" }
    end
    return { kind = "ready", text = "Recording ready" }
end

local function clearBatchRecording(targetRuns)
    batch.clear(targetRuns)
end

local function startBatchRecording(targetRuns)
    batch.start(targetRuns)
end

-- Multi-run session persistence ----------------------------------------------------------------

local function clearSavedSession(runtime)
    if runtime.status.read("SessionState") ~= "" then
        store.clear(runtime.status)
    end
end

local function saveSessionAttempt(runtime, attempt)
    local session = batch.getSession()
    if session == nil or attempt == nil then
        return
    end
    local record = session:toRecord()
    store.saveAttempt(runtime.status, record, attempt.index)
    store.saveTotals(runtime.status, record, batch.targetRuns())
end

--- Arms batch recording, resuming the saved session when allowed and one exists.
local function armBatch(runtime, targetRuns, allowResume)
    if allowResume and runtime.data.read("ResumeAfterRestart") == true then
        local record, savedRuns = store.load(runtime.status)
        if record ~= nil then
            batch.restore(restoreSession(batch.settingsFor(savedRuns), record), savedRuns)
            return
        end
    end
    startBatchRecording(targetRuns)
    clearSavedSession(runtime)
end

--- Resumes a restored session once play is underway again. An attempt whose run finished while
--- the game was closed is settled from run history first.
local function resumeSession(runtime)
    local session = batch.getSession()
    if session == nil or not session:isSuspended() then
        return
    end
    local active = session:getActiveAttempt()
    local ordinal = currentRunOrdinal()
    if active ~= nil and active.runOrdinal ~= nil and ordinal ~= nil and ordinal > active.runOrdinal then
        local result = findRunResult(active.runOrdinal)
        local finished = batch.finishRestoredAttempt(result ~= nil and result.cleared,
            result and result.igtSeconds or 0)
        saveSessionAttempt(runtime, finished)
        if not batch.isActive() then
            disarm(runtime)
        end
    end
    session:resume()
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
    local wasArmed = isArmed()
    local nextMode = readRecordingMode(runtime)
    local nextTargetRuns = readTargetRuns(runtime)
    local nextReady = isRecordingReady(runtime)

    currentMode = nextMode

    if not nextReady then
        if wasArmed then
            stopBatchRecording()
            clearSingleRecording(false)
        end
        return
    end

    if nextMode == "multi" then
        if previousMode ~= "multi" then
            clearSingleRecording(true)
            armBatch(runtime, nextTargetRuns, false)
            return
        end
        if not batch.isReady() then
            armBatch(runtime, nextTargetRuns, true)
            return
        end
        if batch.targetRuns() ~= nextTargetRuns and not batch.hasProgress() then
            startBatchRecording(nextTargetRuns)
        end
        return
    end

    if previousMode == "multi" then
        clearBatchRecording(nextTargetRuns)
        clearSavedSession(runtime)
    end

    if not splits.isStarted() then
        clearSingleRecording(true)
    end
end

function recording.status()
    if recording.isMultiRunMode() then
        return batch.status()
    end
    return singleStatus()
end

function recording.start(runtime)
    local targetRuns = readTargetRuns(runtime)
    setRecordingReady(runtime, true)
    currentMode = readRecordingMode(runtime)
    clearSavedSession(runtime)
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
    clearSavedSession(runtime)
    clearBatchRecording(targetRuns)
    clearSingleRecording(isRecordingReady(runtime))
end

function recording.stop(runtime)
    setRecordingReady(runtime, false)
    clearSavedSession(runtime)
    stopBatchRecording()
    clearSingleRecording(false)
end

-- Drops in-progress recording state while the module is disabled but keeps it armed:
-- RecordingReady is left as-is, so syncSettings re-arms recording when the module is enabled again.
function recording.suspend()
    stopBatchRecording()
    clearSingleRecording(false)
end

function recording.onRunStarted(runtime, run)
    if isRecordingReady(runtime) and splits.startRun(run) and not recording.isMultiRunMode() then
        beginSingleAttempt(run)
    end
    if recording.isMultiRunMode() then
        resumeSession(runtime)
        if batch.startRun(resolveKeys(run), currentRunOrdinal()) then
            saveSessionAttempt(runtime, batch.getSession():getActiveAttempt())
        end
    end
end

--- Play is underway (a room was entered); resumes a session restored after a restart.
function recording.onPlayResumed(runtime)
    if recording.isMultiRunMode() then
        resumeSession(runtime)
    end
end

--- The game wrote a checkpoint; save the session clocks with it.
function recording.checkpoint(runtime)
    if not recording.isMultiRunMode() then
        return
    end
    resumeSession(runtime)
    local session = batch.getSession()
    if session ~= nil and session:isOpen() then
        store.saveClocks(runtime.status, session:toRecord())
    end
end

-- Picks up a run that was already underway when recording was armed.
function recording.adoptRun(run)
    if splits.adoptRun(run) and not recording.isMultiRunMode() then
        beginSingleAttempt(run)
    end
end

function recording.onLoadEvent(isLoading)
    if recording.isMultiRunMode() then
        batch.processLoadEvent(isLoading)
    end
end

function recording.onRunFinalized(runtime, timer, run, snapshot)
    if recording.isMultiRunMode() then
        if batch.finalizeRun(timer, run) then
            saveSessionAttempt(runtime, batch.getSession():getLastFinishedAttempt())
        end
        -- A completed or failed batch disarms recording so its result stays until Start New.
        if not batch.isActive() then
            disarm(runtime)
        end
    elseif splits.finalizeRun(timer, run, snapshot) and singleSession ~= nil then
        singleSession:finishAttempt(isRunSuccess(run) == true, timer and timer:getInGameTime() or 0)
    end
end

function recording.initialize(runtime)
    currentMode = readRecordingMode(runtime)
    local recordingReady = isRecordingReady(runtime)

    if currentMode == "multi" then
        clearSingleRecording(recordingReady)
        if recordingReady then
            armBatch(runtime, readTargetRuns(runtime), true)
        else
            stopBatchRecording()
            -- A finished batch's result is shown again after a restart.
            local record, savedRuns = store.load(runtime.status)
            if record ~= nil and record.state ~= "open" and runtime.data.read("ResumeAfterRestart") == true then
                batch.restore(restoreSession(batch.settingsFor(savedRuns), record), savedRuns)
            end
        end
    else
        clearBatchRecording(readTargetRuns(runtime))
        clearSingleRecording(recordingReady)
        clearSavedSession(runtime)
    end
end

return recording
