local support = dofile("tests/support.lua")
local assertEqual = support.assertEqual
local setTime = support.setTime
local Session = support.Session
local store = support.store

local BATCH_SETTINGS = {
    runs = 2,
    distinct = "none",
    same = "none",
    onDeath = "reset",
}

-- Session record round trip: attempts, totals and frozen clocks come back; an open session is
-- suspended and resumes from its saved elapsed time without counting downtime.
setTime(0)
local session = Session.new({
    runs = 3,
    distinct = "weapon",
    same = "none",
    onDeath = "continue",
})
session:startAttempt({ route = "underworld", weapon = "Staff" }, 4)
setTime(30)
session:finishAttempt(true, 25)
session:startAttempt({ route = "surface", weapon = "Staff" }, 5)
setTime(50)
session:finishAttempt(true, 15)
session:startAttempt({ route = "underworld", weapon = "Axe" }, 6)
setTime(60)
local record = session:toRecord()
assertEqual(record.state, "open")
assertEqual(record.rtaCs, 6000)
assertEqual(record.igtCs, 4000)
assertEqual(#record.attempts, 3)
assertEqual(record.attempts[2].status, "duplicate")
assertEqual(record.attempts[3].status, "active")
assertEqual(record.attempts[3].runOrdinal, 6)

setTime(5000)
local restored = Session.restore(session.settings, record)
assertEqual(restored:isSuspended(), true)
assertEqual(restored:isOpen(), true)
assertEqual(restored:rtaCs(), 6000)
assertEqual(restored:getCountedTotal(), 1)
assertEqual(restored:getActiveAttempt().keys.weapon, "Axe")
restored:resume()
setTime(5010)
assertEqual(restored:rtaCs(), 7000)
local axe = restored:finishAttempt(true, 8)
assertEqual(axe.status, "counted")
assertEqual(axe.sessionIgtCs, 4800)
restored:startAttempt({ weapon = "Staff" }, 7)
assertEqual(restored:finishAttempt(true, 1).status, "duplicate")

local endedRecord = Session.restore(BATCH_SETTINGS, {
    state = "failed",
    rtaCs = 1234,
    loadCs = 34,
    igtCs = 900,
    attempts = { { status = "failed", igtCs = 900 } },
})
assertEqual(endedRecord:getOutcome(), "failed")
assertEqual(endedRecord:isSuspended(), false)
assertEqual(endedRecord:rtaCs(), 1234)
assertEqual(endedRecord:lrtCs(), 1200)

-- Store: incremental attempt rows, totals, load and clear.
local backing = {}
local status = support.newRuntimeState(backing)
local storeRecord = {
    state = "open",
    rtaCs = 100,
    loadCs = 10,
    igtCs = 50,
    attempts = {
        { status = "active", route = "surface", runOrdinal = 0 },
    },
}
store.saveAttempt(status, storeRecord, 1)
store.saveTotals(status, storeRecord, 3)
storeRecord.attempts[1] = { status = "counted", route = "surface", runOrdinal = 0, igtCs = 50, countIndex = 1 }
store.saveAttempt(status, storeRecord, 1)
local loaded, loadedRuns = store.load(status)
assertEqual(loadedRuns, 3)
assertEqual(loaded.state, "open")
assertEqual(loaded.rtaCs, 100)
assertEqual(#loaded.attempts, 1)
assertEqual(loaded.attempts[1].status, "counted")
assertEqual(loaded.attempts[1].route, "surface")
assertEqual(loaded.attempts[1].weapon, nil)
assertEqual(loaded.attempts[1].runOrdinal, 0)
assertEqual(loaded.attempts[1].countIndex, 1)
store.clear(status)
assertEqual(store.load(status), nil)
assertEqual(#backing.SessionAttempts, 0)

-- Recording across a simulated restart. `persisted` plays the role of the module config file.
local persisted = {}
local settings = {
    RecordingMode = "multi",
    BatchTargetRuns = 2,
    ResumeAfterRestart = true,
}
local gameOrdinal = 0
local runHistory = {}

local function boot()
    local runtime = {
        data = {
            read = function(alias)
                return settings[alias]
            end,
        },
        status = support.newRuntimeState(persisted),
    }
    local batch = assert(loadfile("src/timer/batch.lua"))({
        newSession = support.newSession,
        isRunSuccess = support.isRunSuccess,
    })
    local splits = assert(loadfile("src/timer/splits.lua"))({
        routeOf = support.routeOf,
        toCentiseconds = support.core.toCentiseconds,
        isRunSuccess = support.isRunSuccess,
    })
    local recording = assert(loadfile("src/timer/recording.lua"))(support.recordingDeps({
        splits = splits,
        batch = batch,
        currentRunOrdinal = function()
            return gameOrdinal
        end,
        findRunResult = function(ordinal)
            return runHistory[ordinal + 1]
        end,
    }))
    recording.initialize(runtime)
    return recording, batch, runtime
end

local runTimer = {
    getInGameTime = function()
        return 40
    end,
}
local clearedRun = { CurrentRoom = { RoomSetName = "F" }, Cleared = true }

setTime(0)
local recording, batch, runtime = boot()
recording.start(runtime)
recording.onRunStarted(runtime, clearedRun)
assertEqual(persisted.SessionState, "open")
assertEqual(#persisted.SessionAttempts, 1)
assertEqual(persisted.SessionAttempts[1].Status, "active")
setTime(50)
recording.checkpoint(runtime)
assertEqual(persisted.SessionRtaCs, 5000)

-- Crash mid-run, relaunch much later: the run is still in progress and continues.
setTime(900)
recording, batch, runtime = boot()
assertEqual(batch.getSession():isSuspended(), true)
assertEqual(recording.status().text, "Recording 0 / 2")
assertEqual(batch.time("rta"), 5000)
setTime(905)
recording.onPlayResumed(runtime)
assertEqual(batch.getSession():isSuspended(), false)
setTime(915)
assertEqual(batch.time("rta"), 6000)
recording.onRunFinalized(runtime, runTimer, clearedRun, {})
assertEqual(recording.status().text, "Recording 1 / 2")
assertEqual(persisted.SessionAttempts[1].Status, "counted")
gameOrdinal = 1

-- Next run starts, then the game closes; that run finishes as a clear before LiveSplit sees it.
recording.onRunStarted(runtime, clearedRun)
assertEqual(persisted.SessionAttempts[2].RunOrdinal, 1)
setTime(950)
recording.checkpoint(runtime)
gameOrdinal = 2
runHistory[2] = { cleared = true, igtSeconds = 30 }
setTime(2000)
recording, batch, runtime = boot()
recording.onPlayResumed(runtime)
assertEqual(recording.status().text, "Recorded 2 / 2")
assertEqual(persisted.RecordingReady, false)
assertEqual(persisted.SessionState, "completed")
assertEqual(persisted.SessionAttempts[2].Status, "counted")
assertEqual(persisted.SessionIgtCs, 7000)

-- A finished batch's result is shown again after the next restart.
recording, batch, runtime = boot()
assertEqual(recording.status().text, "Recorded 2 / 2")

-- Start New clears the saved session.
recording.start(runtime)
assertEqual(persisted.SessionState, "")
assertEqual(#persisted.SessionAttempts, 0)

-- With resume turned off, a saved session is discarded on the next boot.
recording.onRunStarted(runtime, clearedRun)
assertEqual(persisted.SessionState, "open")
settings.ResumeAfterRestart = false
recording, batch, runtime = boot()
assertEqual(batch.hasSession(), false)
assertEqual(recording.status().text, "Recording ready for 2 runs")
assertEqual(persisted.SessionState, "")
setTime(0)
