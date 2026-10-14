local deps = ... or {}
local core = deps.core
local isMultiRunMode = deps.isMultiRunMode

local LiveRunTimer = {}

function LiveRunTimer:new()
    local o = {}
    o.Running = false
    o.RtaTimer = core.RtaTimer:new()
    o.LrtTimer = core.LrtTimer:new({ rtaTimer = o.RtaTimer })
    o.IgtTimer = core.IgtTimer:new()
    setmetatable(o, self)
    self.__index = self
    return o
end

function LiveRunTimer:start()
    self.Running = true
    self.RtaTimer:start()
    self.LrtTimer:start()
end

function LiveRunTimer:stop()
    self.Running = false
    self.RtaTimer:stop()
    self.LrtTimer:stop()
end

function LiveRunTimer:getRealTime()
    return self.RtaTimer:getTime()
end

function LiveRunTimer:getLoadRemovedTime()
    return self.LrtTimer:getTime()
end

function LiveRunTimer:getInGameTime()
    return self.IgtTimer:getTime()
end

local singleRun = {}
local activeTimer = nil
local runFinalized = false
local showCompletedRun = false
local snapshot = {
    active = false,
    finalized = false,
    hasSummary = false,
    igtCs = 0,
    rtaCs = 0,
    lrtCs = 0,
}

local function updateSnapshotValue(key, value)
    snapshot[key .. "Cs"] = core.toCentiseconds(value)
end

local function updateSnapshot()
    updateSnapshotValue("igt", activeTimer and activeTimer:getInGameTime() or 0)
    updateSnapshotValue("rta", activeTimer and activeTimer:getRealTime() or 0)
    updateSnapshotValue("lrt", activeTimer and activeTimer:getLoadRemovedTime() or 0)
    snapshot.active = activeTimer ~= nil and activeTimer.Running == true
    snapshot.finalized = runFinalized == true
    snapshot.hasSummary = singleRun.hasSummary()
end

function singleRun.clear()
    if activeTimer then
        activeTimer:stop()
    end
    activeTimer = nil
    runFinalized = false
    showCompletedRun = false
    updateSnapshot()
end

function singleRun.beginRun()
    singleRun.clear()
    activeTimer = LiveRunTimer:new()
    updateSnapshot()
    return activeTimer
end

function singleRun.startDisplayLoop()
    local started = false
    if activeTimer and not activeTimer.Running and not runFinalized then
        activeTimer:start()
        started = true
    end
    if activeTimer then
        updateSnapshot()
    end
    return started
end

function singleRun.updateTick()
    updateSnapshot()
    return activeTimer
end

function singleRun.finalizeRun()
    if runFinalized or not activeTimer then
        return false, nil
    end
    runFinalized = true
    activeTimer:stop()
    showCompletedRun = not isMultiRunMode()
    updateSnapshot()
    return true, activeTimer
end

function singleRun.processLoadEvent(isLoading)
    if not (activeTimer and activeTimer.Running) then
        return false
    end
    activeTimer.LrtTimer:processLoadEvent(isLoading)
    return true
end

function singleRun.hasSummary()
    return activeTimer ~= nil and (activeTimer.Running == true or showCompletedRun == true)
end

function singleRun.getActiveTimer()
    return activeTimer
end

function singleRun.getSnapshot()
    return snapshot
end

singleRun.LiveRunTimer = LiveRunTimer

return singleRun
