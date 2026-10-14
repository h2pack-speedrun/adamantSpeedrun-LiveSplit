local support = dofile("tests/support.lua")
local assertEqual = support.assertEqual
local core = support.core
local formatCache = support.formatCache
local overlay = support.overlay

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

local timerSplits = assert(loadfile("src/timer/splits.lua"))({
    toCentiseconds = core.toCentiseconds,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
timerSplits.clear(true)
timerSplits.startRun({
    CurrentRoom = { RoomSetName = "F" },
})
timerSplits.updateRows(splitTimer, {
    CurrentRoom = { RoomSetName = "F" },
    EnteredBiomes = 1,
}, splitSnapshot)
assertEqual(support.splitRow(timerSplits, 1, splitTimer, {
    CurrentRoom = { RoomSetName = "F" },
    EnteredBiomes = 1,
}, splitSnapshot).label, "Erebus")
assertEqual(support.splitRow(timerSplits, 1, splitTimer, {
    CurrentRoom = { RoomSetName = "F" },
    EnteredBiomes = 1,
}, splitSnapshot).igtCs, 1234)
timerSplits.startRun({
    CurrentRoom = { RoomSetName = "N" },
})
timerSplits.updateRows(splitTimer, {
    CurrentRoom = { RoomSetName = "N" },
    EnteredBiomes = 1,
}, splitSnapshot)
assertEqual(support.splitRow(timerSplits, 1, splitTimer, {
    CurrentRoom = { RoomSetName = "N" },
    EnteredBiomes = 1,
}, splitSnapshot).label, "Ephyra")
timerSplits.startRun({
    CurrentRoom = { RoomSetName = "F" },
})
timerSplits.recordCompletedBiomes(splitTimer, {
    BiomeVisitOrder = { "F" },
    BiomeGameplayTimes = {
        F = 65.43,
    },
}, splitSnapshot)
local completedSplitRow = support.splitRow(timerSplits, 1, splitTimer, {
    CurrentRoom = { RoomSetName = "G" },
    EnteredBiomes = 2,
}, splitSnapshot)
assertEqual(completedSplitRow.label, "Erebus")
assertEqual(completedSplitRow.igtCs, 6543)
timerSplits.finalizeRun(splitTimer, {
    Cleared = true,
    BiomeVisitOrder = { "F" },
    BiomeGameplayTimes = {
        F = 65.43,
    },
}, splitSnapshot)
assertEqual(timerSplits.status().kind, "recorded")
assertEqual(timerSplits.hasDetails(), true)
timerSplits.clear(false)
assertEqual(timerSplits.status().kind, "idle")

local overlaySplits = assert(loadfile("src/timer/splits.lua"))({
    toCentiseconds = core.toCentiseconds,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
local splitsOverlayAdapter = assert(loadfile("src/display/overlay_splits.lua"))({
    currentRun = {
        hasDetails = overlaySplits.hasDetails,
        detailsSnapshot = function(liveOnly)
            if liveOnly then
                overlaySplits.updateLiveRows(splitTimer, {
                    CurrentRoom = { RoomSetName = "F" },
                    EnteredBiomes = 1,
                }, splitSnapshot)
            else
                overlaySplits.updateRows(splitTimer, {
                    CurrentRoom = { RoomSetName = "F" },
                    EnteredBiomes = 1,
                }, splitSnapshot)
            end
            return overlaySplits.details()
        end,
    },
    overlay = overlay,
    isVisible = function()
        return true
    end,
    isModeVisible = function(mode)
        return mode ~= "lrt"
    end,
    formatCache = formatCache,
})
local splitOverlayDeclarations = {}
splitsOverlayAdapter.register({
    createTable = function(name, spec)
        splitOverlayDeclarations[name] = spec
    end,
}, 200)
assert(splitOverlayDeclarations.splits ~= nil, "expected split table declaration")
assertEqual(splitOverlayDeclarations.splits.order, 200)
assertEqual(splitOverlayDeclarations.splits.visible(), false)
overlaySplits.clear(true)
overlaySplits.startRun({
    CurrentRoom = { RoomSetName = "F" },
})
local splitOverlayRows = splitsOverlayAdapter.buildRows(nil, false)
assertEqual(splitOverlayDeclarations.splits.visible(), true)
assertEqual(splitOverlayRows[1].key, "header")
assertEqual(splitOverlayRows[2].label, "Erebus")
assertEqual(splitOverlayRows[2].igt, "00:12.34")
local projectedSplitTables = {}
splitsOverlayAdapter.project({
    setTable = function(name, rows)
        projectedSplitTables[name] = rows
    end,
}, nil, true)
assertEqual(projectedSplitTables.splits[2].label, "Erebus")
