local support = dofile("tests/support.lua")
local assertEqual = support.assertEqual
local setTime = support.setTime
local newRuntimeState = support.newRuntimeState
local withImport = support.withImport
local currentRun = support.currentRun
local getFakeTime = support.getFakeTime
local core = support.core

local timerInitStoreValues = {
    ShowIGT = false,
    ShowRawTimers = false,
}
local timerInitRuntimeContext = {
    data = {
        read = function(alias)
            return timerInitStoreValues[alias]
        end,
    },
    status = newRuntimeState(),
}
local timerInit = withImport(function()
    return assert(loadfile("src/timer/00_init.lua"))({
        runtime = timerInitRuntimeContext,
        game = {
            getTime = function()
                return getFakeTime()
            end,
            getCurrentRun = currentRun,
        },
    })
end)
local timerInitDisplay = withImport(function()
    return assert(loadfile("src/display/display.lua"))({
        fonts = support.fonts,
        timer = timerInit,
    })
end)
assert(type(timerInit.currentRun.summary) == "function", "expected timer current-run summary")
assert(type(timerInit.currentRun.detailsSnapshot) == "function", "expected timer current-run details snapshot")
assert(type(timerInit.batch.session) == "function", "expected timer batch session")
assert(type(timerInit.recording.status) == "function", "expected timer recording status")
assertEqual(timerInitDisplay.settings.isModeVisible("igt", timerInitRuntimeContext), false)
assertEqual(timerInitDisplay.settings.isRawTimerRowsEnabled(timerInitRuntimeContext), false)

local splitTimer = {
    getInGameTime = function()
        return 12.34
    end,
    getRealTime = function()
        return 13.45
    end,
    getLoadRemovedTime = function()
        return 12.89
    end,
}
local splitSnapshot = {
    igtCs = 1234,
    rtaCs = 1345,
    lrtCs = 1289,
}
local recordingSettings = {
    RecordingMode = "single",
    BatchTargetRuns = 2,
}
local recordingCache = {}
local recordingRuntime = {
    data = {
        read = function(alias)
            return recordingSettings[alias]
        end,
    },
    status = newRuntimeState(recordingCache),
}
local recordingSplits = assert(loadfile("src/timer/splits.lua"))({
    toCentiseconds = core.toCentiseconds,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
local recordingBatch = assert(loadfile("src/timer/batch.lua"))({
    core = core,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
local recording = assert(loadfile("src/timer/recording.lua"))({
    splits = recordingSplits,
    batch = recordingBatch,
})
recording.initialize(recordingRuntime)
assertEqual(recording.status().kind, "idle")
recording.start(recordingRuntime)
assertEqual(recordingCache.RecordingReady, true)
assertEqual(recording.status().kind, "ready")
recording.onRunStarted({
    CurrentRoom = { RoomSetName = "F" },
})
assertEqual(recording.status().kind, "active")
recording.onRunFinalized(splitTimer, {
    Cleared = true,
    BiomeVisitOrder = { "F" },
    BiomeGameplayTimes = {
        F = 65.43,
    },
}, splitSnapshot)
assertEqual(recording.status().kind, "recorded")

recordingSettings.RecordingMode = "multi"
recording.syncSettings(recordingRuntime)
assertEqual(recording.status().kind, "ready")
assertEqual(recording.status().text, "Recording ready for 2 runs")
recordingSettings.BatchTargetRuns = 4
recording.syncSettings(recordingRuntime)
assertEqual(recording.status().text, "Recording ready for 4 runs")
recording.onRunStarted({
    CurrentRoom = { RoomSetName = "F" },
})
assertEqual(recording.status().kind, "active")
setTime(20)
recordingBatch.updateTimer()
recording.onRunFinalized({
    getInGameTime = function()
        return 15
    end,
}, {
    Cleared = true,
})
assertEqual(recording.status().text, "Recording 1 / 4")
assertEqual(recordingBatch.row(1).igtCs, 1500)
recording.stop(recordingRuntime)
assertEqual(recordingCache.RecordingReady, false)
assertEqual(recording.status().kind, "idle")
setTime(0)

local restoredSettings = {
    RecordingMode = "multi",
    BatchTargetRuns = 6,
}
local restoredRuntime = {
    data = {
        read = function(alias)
            return restoredSettings[alias]
        end,
    },
    status = newRuntimeState({
        RecordingReady = true,
    }),
}
local restoredSplits = assert(loadfile("src/timer/splits.lua"))({
    toCentiseconds = core.toCentiseconds,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
local restoredBatch = assert(loadfile("src/timer/batch.lua"))({
    core = core,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
local restoredRecording = assert(loadfile("src/timer/recording.lua"))({
    splits = restoredSplits,
    batch = restoredBatch,
})
restoredRecording.initialize(restoredRuntime)
assertEqual(restoredRecording.status().kind, "ready")
assertEqual(restoredRecording.status().text, "Recording ready for 6 runs")

local bridgeSettings = {
    RecordingMode = "single",
    BatchTargetRuns = 2,
}
local bridgeSplits = assert(loadfile("src/timer/splits.lua"))({
    toCentiseconds = core.toCentiseconds,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
local bridgeBatch = assert(loadfile("src/timer/batch.lua"))({
    core = core,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
local bridgeRecording
local bridgeSingleRun = assert(loadfile("src/timer/single_run/single_run.lua"))({
    core = core,
    isMultiRunMode = function()
        return bridgeRecording and bridgeRecording.isMultiRunMode() or false
    end,
})
bridgeSingleRun.installHooks = assert(loadfile("src/timer/single_run/hooks.lua"))(bridgeSingleRun).installHooks
local bridgeEvents = {}
local bridgeEventNames = {
    currentRunSummaryChanged = "currentRunSummaryChanged",
    currentRunDetailsChanged = "currentRunDetailsChanged",
    batchSessionChanged = "batchSessionChanged",
    recordingStatusChanged = "recordingStatusChanged",
    currentRunStarted = "currentRunStarted",
    currentRunFinalized = "currentRunFinalized",
    currentRunDisplayStarted = "currentRunDisplayStarted",
    loadRemovalStarted = "loadRemovalStarted",
    loadRemovalEnded = "loadRemovalEnded",
}
local function emitBridgeEvent(name)
    bridgeEvents[name] = (bridgeEvents[name] or 0) + 1
end
local bridgeHost = {
    isEnabled = function()
        return true
    end,
}
local bridgeRuntime = {
    data = {
        read = function(alias)
            return bridgeSettings[alias]
        end,
    },
    status = newRuntimeState(),
}
bridgeRecording = assert(loadfile("src/timer/recording.lua"))({
    splits = bridgeSplits,
    batch = bridgeBatch,
})
local runLoop = assert(loadfile("src/timer/run_loop.lua"))({
    singleRun = bridgeSingleRun,
    recording = bridgeRecording,
    splits = bridgeSplits,
    batch = bridgeBatch,
    getCurrentRun = function()
        return CurrentRun
    end,
    emit = emitBridgeEvent,
    events = bridgeEventNames,
})
local bridgeHooks = {}
runLoop.installHooks({
    wrap = function(name, callback)
        bridgeHooks[name] = callback
    end,
})
bridgeRecording.start(bridgeRuntime)
setTime(0)
_G.CurrentRun = {
    GameplayTime = 0,
    CurrentRoom = { RoomSetName = "F" },
    EnteredBiomes = 1,
    Cleared = true,
    BiomeVisitOrder = { "F" },
    BiomeGameplayTimes = {
        F = 6,
    },
}
bridgeHooks.StartNewRun(bridgeHost, bridgeRuntime, function()
    return CurrentRun
end)
assertEqual(bridgeRecording.status().kind, "active")
assertEqual(runLoop.ensureDisplayLoop(), true)
assertEqual(bridgeSingleRun.hasSummary(), true)
bridgeHooks.RoomEntranceMaterialize(bridgeHost, bridgeRuntime, function()
    return true
end)
setTime(7)
_G.CurrentRun.GameplayTime = 6
runLoop.updateTick()
local bridgeSplitRow = bridgeSplits.row(1, bridgeSingleRun.getActiveTimer(), CurrentRun, bridgeSingleRun.getSnapshot())
assertEqual(bridgeSplitRow.igtCs, 600)
bridgeHooks.RecordRunStats(bridgeHost, bridgeRuntime, function()
    return true
end)
assertEqual(bridgeRecording.status().kind, "recorded")
assert((bridgeEvents.currentRunStarted or 0) > 0, "expected currentRunStarted event")
assert((bridgeEvents.currentRunSummaryChanged or 0) > 0, "expected currentRunSummaryChanged event")
assert((bridgeEvents.currentRunDetailsChanged or 0) > 0, "expected currentRunDetailsChanged event")

bridgeSettings.RecordingMode = "multi"
bridgeRecording.syncSettings(bridgeRuntime)
setTime(0)
local bridgeMultiRun = {
    GameplayTime = 0,
    CurrentRoom = { RoomSetName = "F" },
    EnteredBiomes = 1,
}
_G.CurrentRun = bridgeMultiRun
bridgeHooks.StartNewRun(bridgeHost, bridgeRuntime, function()
    return CurrentRun
end)
bridgeHooks.RoomEntranceMaterialize(bridgeHost, bridgeRuntime, function()
    return true
end)
setTime(9)
_G.CurrentRun.GameplayTime = 5
runLoop.updateTick()
bridgeHooks.RecordRunStats(bridgeHost, bridgeRuntime, function()
    bridgeMultiRun.Cleared = true
    return true
end)
assertEqual(bridgeRecording.status().text, "Recording 1 / 2")
assertEqual(bridgeBatch.row(1).igtCs, 500)
setTime(0)
_G.CurrentRun = nil
