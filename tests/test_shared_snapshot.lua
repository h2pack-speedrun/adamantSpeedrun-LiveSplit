local support = dofile("tests/support.lua")
local assertEqual = support.assertEqual

local currentSummary = {
    rtaCs = 12,
    lrtCs = 10,
    igtCs = 8,
}
local currentStatus = {
    kind = "idle",
}

local sharedSnapshot = assert(loadfile("src/shared_snapshot.lua"))({
    timer = {
        currentRun = {
            summary = function()
                return currentSummary
            end,
        },
        recording = {
            status = function()
                return currentStatus
            end,
        },
    },
})

local ownerCalls = {}
local sharedWrites = {}
local shared = {
    data = {
        owner = function(name, opts)
            ownerCalls[#ownerCalls + 1] = {
                name = name,
                opts = opts,
            }
        end,
    },
    set = function(name, value)
        sharedWrites[#sharedWrites + 1] = {
            name = name,
            value = value,
        }
        return true
    end,
}

local function assertSnapshot(snapshot, expectedRta, expectedLrt, expectedIgt, expectedStatus)
    assertEqual(snapshot.realTimeCs, expectedRta)
    assertEqual(snapshot.loadRemovedTimeCs, expectedLrt)
    assertEqual(snapshot.inGameTimeCs, expectedIgt)
    assertEqual(snapshot.recordingStatus, expectedStatus)
end

sharedSnapshot.register(shared)

assertEqual(#ownerCalls, 1)
assertEqual(ownerCalls[1].name, "TimerSnapshot")
assertEqual(ownerCalls[1].opts.id, "speedrun.timer")
assertSnapshot(ownerCalls[1].opts.default, 12, 10, 8, currentStatus)

currentSummary = {
    rtaCs = 30,
    lrtCs = 24,
    igtCs = 18,
}
currentStatus = {
    kind = "recording",
}

assert(sharedSnapshot.publish(shared))
assertEqual(#sharedWrites, 1)
assertEqual(sharedWrites[1].name, "TimerSnapshot")
assertSnapshot(sharedWrites[1].value, 30, 24, 18, currentStatus)

-- Unchanged values and status skip the shared write.
currentStatus = {
    kind = "recording",
}
assert(sharedSnapshot.publish(shared))
assertEqual(#sharedWrites, 1)

currentSummary = {
    rtaCs = 44,
    lrtCs = 33,
    igtCs = 22,
}
assert(sharedSnapshot.publish(shared))
assertEqual(#sharedWrites, 2)
assertSnapshot(sharedWrites[2].value, 44, 33, 22, currentStatus)

currentStatus = {
    kind = "recording",
    text = "Recording 1 / 3",
}
assert(sharedSnapshot.publish(shared))
assertEqual(#sharedWrites, 3)

-- A failed write is retried on the next publish.
local failingShared = {
    set = function()
        return false, "rejected"
    end,
}
currentSummary = {
    rtaCs = 50,
    lrtCs = 40,
    igtCs = 30,
}
assertEqual(sharedSnapshot.publish(failingShared), false)
assert(sharedSnapshot.publish(shared))
assertEqual(#sharedWrites, 4)
assertSnapshot(sharedWrites[4].value, 50, 40, 30, currentStatus)
