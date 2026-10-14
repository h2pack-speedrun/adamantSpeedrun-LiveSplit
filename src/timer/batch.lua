local deps = ...
local core = deps.core
local isRunSuccess = deps.isRunSuccess

local batch = {}
local rows = {
    hasSession = false,
    active = false,
    failed = false,
    targetRuns = 0,
    completedRuns = 0,
    runs = {},
    current = { label = "", igtCs = nil, rtaCs = nil, lrtCs = nil },
    currentTime = { igtCs = nil, rtaCs = nil, lrtCs = nil },
}

local state = {
    ready = false,
    active = false,
    failed = false,
    targetRuns = 0,
    completedRuns = 0,
    completedIgt = 0,
    runRows = {},
    timer = nil,
    currentRunActive = false,
}
local BatchTimer = {}

function BatchTimer:new()
    local o = {}
    o.Running = false
    o.RtaTimer = core.RtaTimer:new()
    o.LrtTimer = core.LrtTimer:new({ rtaTimer = o.RtaTimer })
    setmetatable(o, self)
    self.__index = self
    return o
end

function BatchTimer:start()
    self.Running = true
    self.RtaTimer:start()
    self.LrtTimer:start()
end

function BatchTimer:stop()
    self.Running = false
    self.RtaTimer:stop()
    self.LrtTimer:stop()
end

function BatchTimer:getRealTime()
    return self.RtaTimer:getTime()
end

function BatchTimer:getLoadRemovedTime()
    return self.LrtTimer:getTime()
end

function BatchTimer:processLoadEvent(isLoading)
    if self.Running then
        self.LrtTimer:processLoadEvent(isLoading)
    end
end

local function normalizeTargetRuns(value)
    return math.floor(tonumber(value) or 0)
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

local function getCurrentRunLabel()
    local runIndex = state.completedRuns + 1
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

local function getBatchRta()
    return state.timer and state.timer:getRealTime() or 0
end

local function getBatchLrt()
    return state.timer and state.timer:getLoadRemovedTime() or 0
end

local function getActiveRunIgtCs(activeTimer)
    return core.toCentiseconds(getActiveRunIgt(activeTimer))
end

local function getBatchRtaCs()
    return core.toCentiseconds(getBatchRta())
end

local function getBatchLrtCs()
    return core.toCentiseconds(getBatchLrt())
end

local function stopTimer()
    if state.timer and state.timer.Running then
        state.timer:stop()
    end
end

local function resetCurrentBatch(clearTimer)
    state.active = false
    state.failed = false
    state.completedRuns = 0
    state.completedIgt = 0
    state.runRows = {}
    state.currentRunActive = false
    if clearTimer ~= false then
        stopTimer()
        state.timer = nil
    end
end

local function finishCurrentBatch()
    state.ready = false
    state.active = false
    state.currentRunActive = false
    stopTimer()
end

function batch.start(targetRuns)
    state.ready = true
    state.targetRuns = normalizeTargetRuns(targetRuns)
    resetCurrentBatch(true)
end

function batch.stop()
    state.ready = false
    resetCurrentBatch(true)
end

function batch.clear(targetRuns)
    if targetRuns ~= nil then
        state.targetRuns = normalizeTargetRuns(targetRuns)
    end
    resetCurrentBatch(true)
end

function batch.startRun()
    if not state.ready then
        return false
    end
    if not state.active then
        resetCurrentBatch(true)
        state.active = true
    end
    if not state.timer then
        state.timer = BatchTimer:new()
        state.timer:start()
    end
    state.currentRunActive = true
    return true
end

function batch.processLoadEvent(isLoading)
    if state.active and state.timer then
        state.timer:processLoadEvent(isLoading)
        return true
    end
    return false
end

function batch.time(mode, activeTimer)
    if not batch.hasSession() then
        return nil
    end
    if mode == "igt" then
        local activeIgtCs = state.currentRunActive and getActiveRunIgtCs(activeTimer) or 0
        return core.toCentiseconds(state.completedIgt) + activeIgtCs
    end
    if mode == "rta" then
        return getBatchRtaCs()
    end
    if mode == "lrt" then
        return getBatchLrtCs()
    end
    return nil
end

function batch.finalizeRun(activeTimer, run)
    if not state.active then
        return false
    end

    local runIgt = getActiveRunIgt(activeTimer)
    if isRunSuccess(run) then
        state.completedIgt = state.completedIgt + runIgt
        state.completedRuns = state.completedRuns + 1
        state.runRows[#state.runRows + 1] = {
            label = getRunLabel("Run", state.completedRuns),
            igtCs = core.toCentiseconds(state.completedIgt),
            rtaCs = getBatchRtaCs(),
            lrtCs = getBatchLrtCs(),
        }
        state.currentRunActive = false
        if state.completedRuns >= state.targetRuns then
            finishCurrentBatch()
        end
        return true
    end

    state.failed = true
    state.currentRunActive = false
    state.runRows[#state.runRows + 1] = {
        label = "Failed",
        igtCs = core.toCentiseconds(state.completedIgt + runIgt),
        rtaCs = getBatchRtaCs(),
        lrtCs = getBatchLrtCs(),
    }
    finishCurrentBatch()
    return true
end

function batch.updateRows(activeTimer)
    local rowCount = math.max(state.targetRuns, #state.runRows)
    for index = 1, rowCount do
        rows.runs[index] = rows.runs[index] or { label = "", igtCs = nil, rtaCs = nil, lrtCs = nil }
        local source = state.runRows[index]
        if source then
            setRow(rows.runs[index], source.label, source.igtCs, source.rtaCs, source.lrtCs)
        else
            setRow(rows.runs[index], "", nil, nil, nil)
        end
    end
    for index = rowCount + 1, #rows.runs do
        setRow(rows.runs[index], "", nil, nil, nil)
    end

    if state.active and state.currentRunActive then
        setRow(rows.current, getCurrentRunLabel(), nil, nil, nil)
        setRow(rows.currentTime, nil,
            batch.time("igt", activeTimer),
            batch.time("rta"),
            batch.time("lrt"))
    else
        setRow(rows.current, "", nil, nil, nil)
        setRow(rows.currentTime, nil, nil, nil, nil)
    end

    rows.hasSession = batch.hasSession()
    rows.active = state.active == true
    rows.failed = state.failed == true
    rows.targetRuns = state.targetRuns
    rows.completedRuns = state.completedRuns
end

function batch.status()
    if state.active then
        return {
            kind = "active",
            text = ("Recording %d / %d"):format(state.completedRuns, state.targetRuns),
        }
    end
    if state.failed then
        return {
            kind = "failed",
            text = ("Failed (%d / %d complete)"):format(state.completedRuns, state.targetRuns),
        }
    end
    if #state.runRows > 0 then
        return {
            kind = "recorded",
            text = ("Recorded %d / %d"):format(state.completedRuns, state.targetRuns),
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
    return state.active == true
end

function batch.isReady()
    return state.ready == true
end

function batch.targetRuns()
    return state.targetRuns
end

function batch.hasSession()
    return state.timer ~= nil or state.failed == true or state.completedRuns > 0
end

function batch.hasProgress()
    return state.active == true or state.failed == true or state.completedRuns > 0
end

function batch.session(activeTimer)
    batch.updateRows(activeTimer)
    return rows
end

return batch
