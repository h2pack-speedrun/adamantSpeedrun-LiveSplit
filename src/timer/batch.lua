-- Multi-run batch: the advanced category session (any runs, no key rules, a death ends the
-- batch) projected into the batch overlay rows and status.

local deps = ...
local newSession = deps.newSession
local isRunSuccess = deps.isRunSuccess

local batch = {}
local rows = {
    hasSession = false,
    active = false,
    failed = false,
    targetRuns = 0,
    completedRuns = 0,
    -- Finished attempts in rows.runs (the first finishedCount entries), and how many failed.
    finishedCount = 0,
    failedCount = 0,
    runs = {},
    current = { label = "", igtCs = nil, rtaCs = nil, lrtCs = nil },
    currentTime = { igtCs = nil, rtaCs = nil, lrtCs = nil },
    total = { label = "", igtCs = nil, rtaCs = nil, lrtCs = nil },
}

local state = {
    ready = false,
    targetRuns = 0,
    session = nil,
}

local function normalizeTargetRuns(value)
    return math.floor(tonumber(value) or 0)
end

local function batchSettings(targetRuns)
    return {
        runs = targetRuns,
        distinct = "none",
        same = "none",
        onDeath = "reset",
    }
end

local function setRow(row, label, igtCs, rtaCs, lrtCs)
    row.label = label or ""
    row.igtCs = igtCs
    row.rtaCs = rtaCs
    row.lrtCs = lrtCs
    return row
end

local function getRunLabel(prefix, runIndex)
    return ("%s %d/%d"):format(prefix, runIndex, state.targetRuns)
end

local function countedRuns()
    return state.session and state.session:getCountedTotal() or 0
end

local function getCurrentRunLabel()
    local runIndex = countedRuns() + 1
    if state.targetRuns > 0 and runIndex > state.targetRuns then
        runIndex = state.targetRuns
    end
    return getRunLabel("Current", runIndex)
end

local function getActiveRunIgt(activeTimer)
    if activeTimer and activeTimer.getInGameTime then
        return activeTimer:getInGameTime()
    end
    return 0
end

local function finishedAttemptLabel(attempt)
    if attempt.status == "counted" then
        return getRunLabel("Run", attempt.countIndex)
    end
    return "Failed"
end

function batch.start(targetRuns)
    state.ready = true
    state.targetRuns = normalizeTargetRuns(targetRuns)
    state.session = nil
end

function batch.stop()
    state.ready = false
    state.session = nil
end

function batch.clear(targetRuns)
    if targetRuns ~= nil then
        state.targetRuns = normalizeTargetRuns(targetRuns)
    end
    state.session = nil
end

function batch.startRun(attemptKeys, runOrdinal)
    if not state.ready then
        return false
    end
    if state.session == nil then
        state.session = newSession(batchSettings(state.targetRuns))
    end
    state.session:startAttempt(attemptKeys or {}, runOrdinal)
    return true
end

--- Finishes the restored session's active attempt with a result read from run history.
function batch.finishRestoredAttempt(cleared, igtSeconds)
    local attempt = state.session and state.session:finishAttempt(cleared, igtSeconds) or nil
    if attempt ~= nil and state.session:getOutcome() ~= nil then
        state.ready = false
    end
    return attempt
end

--- The current batch session, or nil before the first run.
function batch.getSession()
    return state.session
end

--- Settings for a batch of `targetRuns`, for restoring a saved batch session.
function batch.settingsFor(targetRuns)
    return batchSettings(normalizeTargetRuns(targetRuns))
end

--- Adopts a restored session. An ended session keeps its result visible with recording disarmed.
function batch.restore(session, targetRuns)
    state.targetRuns = normalizeTargetRuns(targetRuns)
    state.session = session
    state.ready = session:getOutcome() == nil
end

function batch.processLoadEvent(isLoading)
    return state.session ~= nil and state.session:processLoadEvent(isLoading)
end

function batch.time(mode, activeTimer)
    if not batch.hasSession() then
        return nil
    end
    if mode == "igt" then
        return state.session:igtCs(getActiveRunIgt(activeTimer))
    end
    if mode == "rta" then
        return state.session:rtaCs()
    end
    if mode == "lrt" then
        return state.session:lrtCs()
    end
    return nil
end

function batch.finalizeRun(activeTimer, run)
    if not batch.isActive() then
        return false
    end
    local attempt = state.session:finishAttempt(isRunSuccess(run) == true, getActiveRunIgt(activeTimer))
    if attempt == nil then
        return false
    end
    if state.session:getOutcome() ~= nil then
        state.ready = false
    end
    return true
end

function batch.updateRows(activeTimer)
    local attempts = state.session and state.session:getAttempts() or {}
    local finishedCount = 0
    local failedCount = 0
    for _, attempt in ipairs(attempts) do
        if attempt.status == "failed" then
            failedCount = failedCount + 1
        end
        if attempt.finished then
            finishedCount = finishedCount + 1
            rows.runs[finishedCount] = rows.runs[finishedCount] or { label = "", igtCs = nil, rtaCs = nil, lrtCs = nil }
            setRow(rows.runs[finishedCount], finishedAttemptLabel(attempt),
                attempt.sessionIgtCs, attempt.sessionRtaCs, attempt.sessionLrtCs)
        end
    end
    local rowCount = math.max(state.targetRuns, finishedCount)
    for index = finishedCount + 1, rowCount do
        rows.runs[index] = rows.runs[index] or { label = "", igtCs = nil, rtaCs = nil, lrtCs = nil }
        setRow(rows.runs[index], "", nil, nil, nil)
    end
    for index = rowCount + 1, #rows.runs do
        setRow(rows.runs[index], "", nil, nil, nil)
    end

    if batch.isActive() and state.session:getActiveAttempt() ~= nil then
        setRow(rows.current, getCurrentRunLabel(), nil, nil, nil)
        setRow(rows.currentTime, nil,
            batch.time("igt", activeTimer),
            batch.time("rta"),
            batch.time("lrt"))
    else
        setRow(rows.current, "", nil, nil, nil)
        setRow(rows.currentTime, nil, nil, nil, nil)
    end

    if batch.hasSession() then
        setRow(rows.total, "Total", batch.time("igt", activeTimer), batch.time("rta"), batch.time("lrt"))
    else
        setRow(rows.total, "", nil, nil, nil)
    end

    rows.finishedCount = finishedCount
    rows.failedCount = failedCount
    rows.hasSession = batch.hasSession()
    rows.active = batch.isActive()
    rows.failed = state.session ~= nil and state.session:getOutcome() == "failed"
    rows.targetRuns = state.targetRuns
    rows.completedRuns = countedRuns()
end

function batch.status()
    local session = state.session
    if batch.isActive() then
        return {
            kind = "active",
            text = ("Recording %d / %d"):format(countedRuns(), state.targetRuns),
        }
    end
    if session ~= nil and session:getOutcome() == "failed" then
        return {
            kind = "failed",
            text = ("Failed (%d / %d complete)"):format(countedRuns(), state.targetRuns),
        }
    end
    if session ~= nil and session:getLastFinishedAttempt() ~= nil then
        return {
            kind = "recorded",
            text = ("Recorded %d / %d"):format(countedRuns(), state.targetRuns),
        }
    end
    if state.ready then
        return {
            kind = "ready",
            text = ("Recording ready for %d runs"):format(state.targetRuns),
        }
    end
    return {
        kind = "idle",
        text = "Not recording",
    }
end

function batch.isActive()
    return state.session ~= nil and state.session:isOpen()
end

function batch.isReady()
    return state.ready == true
end

function batch.targetRuns()
    return state.targetRuns
end

function batch.hasSession()
    return state.session ~= nil and state.session:hasStarted()
end

function batch.hasProgress()
    return batch.hasSession()
end

-- Finished-attempt history for the module UI, rebuilt only when it changes.
local history = {
    session = nil,
    finishedCount = -1,
    entries = {},
}

--- Every finished attempt, oldest first: { label, status, igtCs, sessionIgtCs, sessionRtaCs,
--- sessionLrtCs }. The returned list is replaced, not mutated, when attempts finish.
function batch.history()
    local session = state.session
    local attempts = session and session:getAttempts() or {}
    local finishedCount = 0
    for _, attempt in ipairs(attempts) do
        if attempt.finished then
            finishedCount = finishedCount + 1
        end
    end
    if session == history.session and finishedCount == history.finishedCount then
        return history.entries
    end
    local entries = {}
    for _, attempt in ipairs(attempts) do
        if attempt.finished then
            entries[#entries + 1] = {
                label = finishedAttemptLabel(attempt),
                status = attempt.status,
                igtCs = attempt.igtCs,
                sessionIgtCs = attempt.sessionIgtCs,
                sessionRtaCs = attempt.sessionRtaCs,
                sessionLrtCs = attempt.sessionLrtCs,
            }
        end
    end
    history.session = session
    history.finishedCount = finishedCount
    history.entries = entries
    return entries
end

function batch.session(activeTimer)
    batch.updateRows(activeTimer)
    return rows
end

return batch
