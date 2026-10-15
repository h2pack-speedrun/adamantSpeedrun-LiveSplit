local support = dofile("tests/support.lua")
local assertEqual = support.assertEqual
local setTime = support.setTime
local newSession = support.newSession

local function settings(overrides)
    local result = {
        runs = 3,
        distinct = "none",
        same = "none",
        onDeath = "continue",
    }
    for key, value in pairs(overrides or {}) do
        result[key] = value
    end
    return result
end

-- Timers start with the first attempt; RTA spans the session; IGT sums every attempt.
setTime(0)
local session = newSession(settings({ runs = 2 }))
assertEqual(session:hasStarted(), false)
assertEqual(session:isOpen(), false)
setTime(10)
local first = session:startAttempt({ route = "underworld" })
assertEqual(first.status, "active")
assertEqual(session:isOpen(), true)
setTime(40)
assertEqual(session:rtaCs(), 3000)
assertEqual(session:igtCs(5), 500)
session:finishAttempt(false, 20)
assertEqual(first.status, "failed")
assertEqual(first.igtCs, 2000)
assertEqual(first.sessionIgtCs, 2000)
assertEqual(session:isOpen(), true)
assertEqual(session:igtCs(5), 2000)
session:startAttempt({ route = "surface" })
setTime(70)
local second = session:finishAttempt(true, 25)
assertEqual(second.status, "counted")
assertEqual(second.countIndex, 1)
assertEqual(second.sessionIgtCs, 4500)
assertEqual(second.sessionRtaCs, 6000)
session:startAttempt({ route = "underworld" })
setTime(100)
session:finishAttempt(true, 10)
assertEqual(session:getOutcome(), "completed")
assertEqual(session:isOpen(), false)
setTime(500)
assertEqual(session:rtaCs(), 9000)
assertEqual(session:startAttempt({}), nil)
assertEqual(#session:getAttempts(), 3)
assertEqual(session:getLastFinishedAttempt().status, "counted")

-- onDeath = reset ends the session on the first failure.
setTime(0)
local resetSession = newSession(settings({ onDeath = "reset" }))
resetSession:startAttempt({})
resetSession:finishAttempt(false, 3)
assertEqual(resetSession:getOutcome(), "failed")
assertEqual(resetSession:startAttempt({}), nil)

-- distinct: repeats of a counted value are duplicates; a failed value can be retried.
local distinctSession = newSession(settings({ runs = 2, distinct = "weapon" }))
distinctSession:startAttempt({ weapon = "Staff" })
assertEqual(distinctSession:finishAttempt(false, 1).status, "failed")
distinctSession:startAttempt({ weapon = "Staff" })
assertEqual(distinctSession:finishAttempt(true, 1).status, "counted")
distinctSession:startAttempt({ weapon = "Staff" })
assertEqual(distinctSession:finishAttempt(true, 1).status, "duplicate")
assertEqual(distinctSession:getCountedTotal(), 1)
distinctSession:startAttempt({ weapon = "Axe" })
assertEqual(distinctSession:finishAttempt(true, 1).status, "counted")
assertEqual(distinctSession:getOutcome(), "completed")

-- same: attempts must share the first valid attempt's key; violations are invalid and never count.
local sameSession = newSession(settings({ runs = 2, distinct = "route", same = "aspect" }))
sameSession:startAttempt({ route = "underworld", aspect = "Melinoe" })
assertEqual(sameSession:finishAttempt(true, 1).status, "counted")
local wrongAspect = sameSession:startAttempt({ route = "surface", aspect = "Circe" })
assertEqual(wrongAspect.status, "invalid")
assertEqual(sameSession:finishAttempt(true, 1).status, "invalid")
assertEqual(sameSession:isOpen(), true)
sameSession:startAttempt({ route = "surface", aspect = "Melinoe" })
assertEqual(sameSession:finishAttempt(true, 1).status, "counted")
assertEqual(sameSession:getOutcome(), "completed")

-- An attempt left unfinished is replaced by the next start.
local abandonSession = newSession(settings())
abandonSession:startAttempt({})
abandonSession:startAttempt({})
assertEqual(#abandonSession:getAttempts(), 1)

-- Load time is removed from the session's LrT while open.
setTime(0)
local loadSession = newSession(settings())
loadSession:startAttempt({})
setTime(10)
assertEqual(loadSession:processLoadEvent(true), true)
setTime(14)
loadSession:processLoadEvent(false)
setTime(20)
assertEqual(loadSession:lrtCs(), 1600)
setTime(0)

-- Pauses: only between attempts; the session clocks stop and a Paused row records how long.
setTime(0)
local pauseSession = newSession(settings({ runs = 3 }))
assertEqual(pauseSession:canPause(), false)
assertEqual(pauseSession:pause(), nil)
pauseSession:startAttempt({})
assertEqual(pauseSession:canPause(), false)
setTime(10)
pauseSession:finishAttempt(true, 8)
assertEqual(pauseSession:canPause(), true)
setTime(12)
local pauseRow = pauseSession:pause()
assertEqual(pauseRow.status, "paused")
assertEqual(pauseRow.finished, true)
assertEqual(pauseRow.sessionRtaCs, 1200)
assertEqual(pauseSession:isPaused(), true)
assertEqual(pauseSession:canPause(), false)
setTime(100)
assertEqual(pauseSession:rtaCs(), 1200)
assertEqual(pauseSession:lrtCs(), 1200)
assertEqual(pauseSession:pausedCs(pauseRow), 8800)
-- Loads while paused are not counted.
assertEqual(pauseSession:processLoadEvent(true), true)
setTime(110)
pauseSession:processLoadEvent(false)
pauseSession:unpause()
assertEqual(pauseRow.pausedCs, 9800)
setTime(115)
assertEqual(pauseSession:rtaCs(), 1700)
assertEqual(pauseSession:lrtCs(), 1700)
-- A second pause in the same gap continues the same row.
pauseSession:pause()
setTime(120)
assertEqual(#pauseSession:getAttempts(), 2)
assertEqual(pauseSession:pausedCs(pauseRow), 10300)
-- Starting a run ends the pause.
local afterPause = pauseSession:startAttempt({})
assertEqual(pauseSession:isPaused(), false)
assertEqual(pauseRow.pausedCs, 10300)
assertEqual(afterPause.index, 3)
setTime(125)
assertEqual(pauseSession:rtaCs(), 2200)
assertEqual(pauseSession:getCountedTotal(), 1)
-- Saved while paused, a session comes back paused once play resumes.
pauseSession:finishAttempt(true, 4)
pauseSession:pause()
setTime(130)
local pausedRecord = pauseSession:toRecord()
assertEqual(pausedRecord.paused, true)
assertEqual(pausedRecord.attempts[4].pausedCs, 500)
setTime(1000)
local restoredPause = support.Session.restore(settings({ runs = 3 }), pausedRecord)
assertEqual(restoredPause:isPaused(), false)
restoredPause:resume()
assertEqual(restoredPause:isPaused(), true)
setTime(1010)
assertEqual(restoredPause:rtaCs(), pausedRecord.rtaCs)
assertEqual(restoredPause:pausedCs(restoredPause:getAttempts()[4]), 1500)
restoredPause:unpause()
setTime(1020)
assertEqual(restoredPause:rtaCs(), pausedRecord.rtaCs + 1000)
assertEqual(restoredPause:getCountedTotal(), 2)
setTime(0)

-- Route keys.
local keys = support.keys
assertEqual(keys.routeOf(nil), nil)
assertEqual(keys.routeOf({ IsDreamRun = true }), "dream")
assertEqual(keys.routeOf({ CurrentRoom = { RoomSetName = "O" } }), "surface")
assertEqual(keys.routeOf({ CurrentRoom = { RoomSetName = "F" }, BiomesReached = { N = true } }), "surface")
assertEqual(keys.routeOf({ CurrentRoom = { RoomSetName = "F" } }), "underworld")
assertEqual(keys.resolve({ CurrentRoom = { RoomSetName = "F" } }).route, "underworld")
