-- Multi-run recording: one category session projected into overlay rows, status and history.
--
-- The category settings (timer/categories.lua) decide the rules and how attempts are labeled.
-- Categories that keep splits record each attempt's biome splits with session-cumulative times.

local deps = ...
local newSession = deps.newSession
local isRunSuccess = deps.isRunSuccess
local keys = deps.keys
local categoryNames = deps.categoryNames

local batch = {}

local function newRow()
    return { label = "", igtCs = nil, rtaCs = nil, lrtCs = nil }
end

local function newGroup()
    return { heading = newRow(), biomes = {}, biomeCount = 0 }
end

local rows = {
    hasSession = false,
    active = false,
    failed = false,
    -- True when attempts show their biome splits (the category keeps splits).
    splits = false,
    title = "",
    targetRuns = 0,
    completedRuns = 0,
    -- Finished attempts are rows.groups[1..finishedCount]; failedCount of them died.
    finishedCount = 0,
    failedCount = 0,
    groups = {},
    current = newGroup(),
    currentTime = { igtCs = nil, rtaCs = nil, lrtCs = nil },
    total = newRow(),
}

local state = {
    ready = false,
    settings = nil,
    session = nil,
}

local function setRow(row, label, igtCs, rtaCs, lrtCs)
    row.label = label or ""
    row.igtCs = igtCs
    row.rtaCs = rtaCs
    row.lrtCs = lrtCs
    return row
end

local function targetRuns()
    return state.settings and state.settings.runs or 0
end

local function countedRuns()
    return state.session and state.session:getCountedTotal() or 0
end

local function keepsSplits()
    return state.settings ~= nil and state.settings.completedRun == "splits"
end

local function getActiveRunIgt(activeTimer)
    if activeTimer and activeTimer.getInGameTime then
        return activeTimer:getInGameTime()
    end
    return 0
end

local function keyName(attempt)
    local labelKey = state.settings.label
    return keys.nameOf(labelKey, attempt.keys[labelKey]) or "Unknown"
end

local STATUS_SUFFIX = {
    failed = " (died)",
    duplicate = " (repeat)",
    invalid = " (invalid)",
}

local PAUSED_LABEL = "Paused"

local function finishedAttemptLabel(attempt)
    if attempt.status == "paused" then
        return PAUSED_LABEL
    end
    if state.settings.label == "index" then
        if attempt.status == "counted" then
            return ("Run %d/%d"):format(attempt.countIndex, targetRuns())
        end
        return attempt.status == "failed" and "Failed" or attempt.status == "duplicate" and "Duplicate"
            or "Invalid"
    end
    return keyName(attempt) .. (STATUS_SUFFIX[attempt.status] or "")
end

local function currentAttemptLabel(attempt)
    if state.settings.label == "index" then
        local runIndex = math.min(countedRuns() + 1, math.max(targetRuns(), 1))
        return ("Current %d/%d"):format(runIndex, targetRuns())
    end
    return "Current: " .. keyName(attempt) .. (STATUS_SUFFIX[attempt.status] or "")
end

local function title()
    local category = state.settings and state.settings.category
    if category == nil or category == "custom" then
        return "Runs"
    end
    return categoryNames[category] or "Runs"
end

function batch.start(settings)
    state.ready = true
    state.settings = settings
    state.session = nil
end

function batch.stop()
    state.ready = false
    state.session = nil
end

--- Drops the session and keeps the readiness; `settings`, when given, replaces the rules.
function batch.clear(settings)
    if settings ~= nil then
        state.settings = settings
    end
    state.session = nil
end

function batch.startRun(attemptKeys, runOrdinal)
    if not state.ready then
        return false
    end
    if state.session == nil then
        state.session = newSession(state.settings)
    end
    local attempt = state.session:startAttempt(attemptKeys or {}, runOrdinal)
    if attempt ~= nil then
        attempt.biomes = {}
    end
    return attempt ~= nil
end

--- Records biome splits the active attempt completed, with session-cumulative times. Returns
--- true when a split was added (categories that keep splits only).
function batch.captureBiomes(run)
    local session = state.session
    local attempt = session and session:getActiveAttempt()
    if not keepsSplits() or attempt == nil or run == nil or run.BiomeVisitOrder == nil then
        return false
    end
    local seen = {}
    for _, split in ipairs(attempt.biomes) do
        seen[split.code] = true
    end
    local added = false
    for _, code in ipairs(run.BiomeVisitOrder) do
        local gameplayTime = run.BiomeGameplayTimes and run.BiomeGameplayTimes[code]
        if gameplayTime ~= nil and not seen[code] then
            attempt.biomes[#attempt.biomes + 1] = {
                code = code,
                igtCs = session:igtCs(gameplayTime),
                rtaCs = session:rtaCs(),
                lrtCs = session:lrtCs(),
            }
            seen[code] = true
            added = true
        end
    end
    return added
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
    batch.captureBiomes(run)
    local attempt = state.session:finishAttempt(isRunSuccess(run) == true, getActiveRunIgt(activeTimer))
    if attempt == nil then
        return false
    end
    if state.session:getOutcome() ~= nil then
        state.ready = false
    end
    return true
end

local function setBiomeRows(group, attempt)
    local count = 0
    for _, split in ipairs(attempt.biomes or {}) do
        count = count + 1
        group.biomes[count] = group.biomes[count] or newRow()
        setRow(group.biomes[count], keys.BIOME_NAMES[split.code] or split.code, split.igtCs, split.rtaCs, split.lrtCs)
    end
    group.biomeCount = count
end

-- The active attempt's route: captured splits, then the biome in progress with live times.
local function setCurrentBiomeRows(group, attempt, run, activeTimer)
    local captured = {}
    for _, split in ipairs(attempt.biomes or {}) do
        captured[split.code] = split
    end
    local currentBiome = run and run.CurrentRoom and run.CurrentRoom.RoomSetName
    local count = 0
    for _, code in ipairs(keys.ROUTES[attempt.keys.route] or {}) do
        count = count + 1
        group.biomes[count] = group.biomes[count] or newRow()
        local split = captured[code]
        local label = keys.BIOME_NAMES[code] or code
        if split ~= nil then
            setRow(group.biomes[count], label, split.igtCs, split.rtaCs, split.lrtCs)
        elseif code == currentBiome then
            setRow(group.biomes[count], label, batch.time("igt", activeTimer), batch.time("rta"), batch.time("lrt"))
        else
            setRow(group.biomes[count], label, nil, nil, nil)
        end
    end
    group.biomeCount = count
end

function batch.updateRows(activeTimer, run)
    local attempts = state.session and state.session:getAttempts() or {}
    local finishedCount = 0
    local failedCount = 0
    local splits = keepsSplits()
    for _, attempt in ipairs(attempts) do
        if attempt.status == "failed" then
            failedCount = failedCount + 1
        end
        if attempt.finished then
            finishedCount = finishedCount + 1
            local group = rows.groups[finishedCount] or newGroup()
            rows.groups[finishedCount] = group
            if attempt.status == "paused" then
                -- A pause shows how long the session clocks were stopped; no in-game time passed.
                local pausedCs = state.session:pausedCs(attempt)
                setRow(group.heading, PAUSED_LABEL, nil, pausedCs, pausedCs)
            else
                setRow(group.heading, finishedAttemptLabel(attempt),
                    attempt.sessionIgtCs, attempt.sessionRtaCs, attempt.sessionLrtCs)
            end
            if splits and attempt.status ~= "paused" then
                setBiomeRows(group, attempt)
            else
                group.biomeCount = 0
            end
        end
    end
    for index = finishedCount + 1, #rows.groups do
        setRow(rows.groups[index].heading, "", nil, nil, nil)
        rows.groups[index].biomeCount = 0
    end

    local active = batch.isActive() and state.session:getActiveAttempt() or nil
    if active ~= nil then
        setRow(rows.current.heading, currentAttemptLabel(active), nil, nil, nil)
        if splits then
            setCurrentBiomeRows(rows.current, active, run, activeTimer)
        else
            rows.current.biomeCount = 0
        end
        setRow(rows.currentTime, nil, batch.time("igt", activeTimer), batch.time("rta"), batch.time("lrt"))
    else
        setRow(rows.current.heading, "", nil, nil, nil)
        rows.current.biomeCount = 0
        setRow(rows.currentTime, nil, nil, nil, nil)
    end

    if batch.hasSession() then
        setRow(rows.total, "Session", batch.time("igt", activeTimer), batch.time("rta"), batch.time("lrt"))
    else
        setRow(rows.total, "", nil, nil, nil)
    end

    rows.title = title()
    rows.splits = splits
    rows.finishedCount = finishedCount
    rows.failedCount = failedCount
    rows.hasSession = batch.hasSession()
    rows.active = batch.isActive()
    rows.failed = state.session ~= nil and state.session:getOutcome() == "failed"
    rows.targetRuns = targetRuns()
    rows.completedRuns = countedRuns()
end

function batch.status()
    local session = state.session
    local progress = ("%d / %d"):format(countedRuns(), targetRuns())
    if session ~= nil and session:isPaused() then
        return { kind = "paused", text = "Paused (" .. progress .. ")", canResume = true }
    end
    if batch.isActive() then
        return { kind = "active", text = "Recording " .. progress, canPause = session:canPause() }
    end
    if session ~= nil and session:getOutcome() == "failed" then
        return { kind = "failed", text = ("Failed (%s complete)"):format(progress) }
    end
    if session ~= nil and session:getLastFinishedAttempt() ~= nil then
        return { kind = "recorded", text = "Recorded " .. progress }
    end
    if state.ready then
        return { kind = "ready", text = ("Recording ready for %d runs"):format(targetRuns()) }
    end
    return { kind = "idle", text = "Not recording" }
end

--- Pauses the session between attempts; returns the pause row, or nil when not allowed.
function batch.pause()
    return state.session ~= nil and state.session:pause() or nil
end

--- Ends a pause; returns the pause row, or nil when not paused.
function batch.unpause()
    return state.session ~= nil and state.session:unpause() or nil
end

function batch.isPaused()
    return state.session ~= nil and state.session:isPaused()
end

function batch.isActive()
    return state.session ~= nil and state.session:isOpen()
end

function batch.isReady()
    return state.ready == true
end

function batch.targetRuns()
    return targetRuns()
end

function batch.getSettings()
    return state.settings
end

function batch.hasSession()
    return state.session ~= nil and state.session:hasStarted()
end

function batch.hasProgress()
    return batch.hasSession()
end

--- Finishes the restored session's active attempt with a result read from run history.
function batch.finishRestoredAttempt(cleared, igtSeconds)
    local attempt = state.session and state.session:finishAttempt(cleared, igtSeconds) or nil
    if attempt ~= nil and state.session:getOutcome() ~= nil then
        state.ready = false
    end
    return attempt
end

--- The current session, or nil before the first run.
function batch.getSession()
    return state.session
end

--- Adopts a restored session. An ended session keeps its result visible with recording disarmed.
function batch.restore(session, settings)
    state.settings = settings
    state.session = session
    state.ready = session:getOutcome() == nil
end

-- Finished-attempt history for the module UI, rebuilt only when it changes. A pause changes its
-- row's duration without adding a row, so the paused state is part of the cache key.
local history = {
    session = nil,
    finishedCount = -1,
    paused = false,
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
    local paused = session ~= nil and session:isPaused()
    if session == history.session and finishedCount == history.finishedCount and paused == history.paused then
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
                pausedCs = attempt.status == "paused" and attempt.pausedCs or nil,
                -- The pause in progress; its duration is final once it ends.
                live = paused and attempt == attempts[#attempts] or nil,
            }
        end
    end
    history.session = session
    history.finishedCount = finishedCount
    history.paused = paused
    history.entries = entries
    return entries
end

function batch.session(activeTimer, run)
    batch.updateRows(activeTimer, run)
    return rows
end

return batch
