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

-- Route keys.
local keys = support.keys
assertEqual(keys.routeOf(nil), nil)
assertEqual(keys.routeOf({ IsDreamRun = true }), "dream")
assertEqual(keys.routeOf({ CurrentRoom = { RoomSetName = "O" } }), "surface")
assertEqual(keys.routeOf({ CurrentRoom = { RoomSetName = "F" }, BiomesReached = { N = true } }), "surface")
assertEqual(keys.routeOf({ CurrentRoom = { RoomSetName = "F" } }), "underworld")
assertEqual(keys.resolve({ CurrentRoom = { RoomSetName = "F" } }).route, "underworld")
