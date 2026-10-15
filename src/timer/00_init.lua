local deps = ...

local timer = {
    currentRun = {},
    batch = {},
    recording = {},
}
-- Called whenever timer or recording output may have changed.
local onChanged = deps.onChanged

local game = import('timer/game.lua')

local core = import('timer/core/00_init.lua', nil, {
    getTime = game.getTime,
    getCurrentRun = game.getCurrentRun,
})
local singleRun
local splits
local batch
local recording
local runLoop

singleRun = import('timer/single_run/single_run.lua', nil, {
    core = core,
    isMultiRunMode = function()
        return recording.isMultiRunMode()
    end,
})
singleRun.installHooks = import('timer/single_run/hooks.lua', nil, singleRun).installHooks

local keys = import('timer/keys.lua')
local Session = import('timer/session.lua', nil, {
    core = core,
})
local newSession = Session.new

splits = import('timer/splits.lua', nil, {
    toCentiseconds = core.toCentiseconds,
    isRunSuccess = game.isRunSuccess,
    keys = keys,
})
local categories = import('timer/categories.lua')
batch = import('timer/batch.lua', nil, {
    newSession = newSession,
    isRunSuccess = game.isRunSuccess,
    keys = keys,
    categoryNames = categories.NAMES,
})
recording = import('timer/recording.lua', nil, {
    splits = splits,
    batch = batch,
    normalizeRecordingMode = import('data.lua').normalizeRecordingMode,
    newSession = newSession,
    restoreSession = Session.restore,
    resolveKeys = keys.resolve,
    isRunSuccess = game.isRunSuccess,
    currentRunOrdinal = game.currentRunOrdinal,
    findRunResult = game.findRunResult,
    store = import('timer/session_store.lua'),
    categories = categories,
})
runLoop = import('timer/run_loop.lua', nil, {
    singleRun = singleRun,
    recording = recording,
    splits = splits,
    batch = batch,
    getCurrentRun = game.getCurrentRun,
    onChanged = onChanged,
})

function timer.currentRun.summary()
    return singleRun.getSnapshot()
end

function timer.currentRun.detailsSnapshot(liveOnly)
    local activeTimer = singleRun.getActiveTimer()
    local run = game.getCurrentRun()
    local snapshot = singleRun.getSnapshot()
    if liveOnly then
        splits.updateLiveRows(activeTimer, run, snapshot)
    else
        splits.updateRows(activeTimer, run, snapshot)
    end
    return splits.details()
end

function timer.currentRun.hasSummary()
    return singleRun.hasSummary()
end

function timer.currentRun.hasDetails()
    return splits.hasDetails()
end

function timer.batch.session()
    return batch.session(singleRun.getActiveTimer(), game.getCurrentRun())
end

function timer.batch.history()
    return batch.history()
end

function timer.batch.hasSession()
    return batch.hasSession()
end

function timer.recording.status()
    return recording.status()
end

function timer.recording.isMultiRunMode()
    return recording.isMultiRunMode()
end

function timer.recording.start(runtime)
    local result = recording.start(runtime)
    onChanged(runtime)
    return result
end

function timer.recording.stop(runtime)
    local result = recording.stop(runtime)
    onChanged(runtime)
    return result
end

function timer.recording.togglePause(runtime)
    local result = recording.togglePause(runtime)
    onChanged(runtime)
    return result
end

function timer.recording.clear(runtime)
    local result = recording.clear(runtime)
    onChanged(runtime)
    return result
end

function timer.recording.syncSettings(runtime)
    local result = recording.syncSettings(runtime)
    onChanged(runtime)
    return result
end

function timer.initialize(runtime)
    recording.initialize(runtime)
    onChanged(runtime)
end

function timer.installHooks(hooks)
    runLoop.installHooks(hooks)
end

function timer.hasActiveDisplayLoop()
    return runLoop.hasActiveDisplayLoop()
end

function timer.ensureDisplayLoop()
    return runLoop.ensureDisplayLoop()
end

function timer.updateTick(runtime)
    runLoop.updateTick(runtime)
    onChanged(runtime)
end

function timer.cleanup(runtime)
    local result = runLoop.cleanup()
    onChanged(runtime)
    return result
end

return timer
