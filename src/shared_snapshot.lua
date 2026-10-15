local deps = ...
local timer = deps.timer

local sharedSnapshot = {}

local SHARED_TIMER_SNAPSHOT = "speedrun.timer"
local SHARED_DECLARATION = "TimerSnapshot"

-- Last published values; publish skips the shared write while they are unchanged.
local published = {}

local function buildSnapshot()
    local snapshot = timer.currentRun.summary()
    return {
        realTimeCs = snapshot.rtaCs,
        loadRemovedTimeCs = snapshot.lrtCs,
        inGameTimeCs = snapshot.igtCs,
        recordingStatus = timer.recording.status(),
    }
end

local function isUnchanged(snapshot)
    local status = snapshot.recordingStatus
    return published.realTimeCs == snapshot.realTimeCs
        and published.loadRemovedTimeCs == snapshot.loadRemovedTimeCs
        and published.inGameTimeCs == snapshot.inGameTimeCs
        and published.statusKind == status.kind
        and published.statusText == status.text
end

local function remember(snapshot)
    published.realTimeCs = snapshot.realTimeCs
    published.loadRemovedTimeCs = snapshot.loadRemovedTimeCs
    published.inGameTimeCs = snapshot.inGameTimeCs
    published.statusKind = snapshot.recordingStatus.kind
    published.statusText = snapshot.recordingStatus.text
end

function sharedSnapshot.register(shared)
    local snapshot = buildSnapshot()
    shared.data.owner(SHARED_DECLARATION, {
        id = SHARED_TIMER_SNAPSHOT,
        default = snapshot,
    })
    remember(snapshot)
end

function sharedSnapshot.publish(shared)
    local snapshot = buildSnapshot()
    if isUnchanged(snapshot) then
        return true
    end
    local ok, err = shared.set(SHARED_DECLARATION, snapshot)
    if ok then
        remember(snapshot)
    end
    return ok, err
end

return sharedSnapshot
