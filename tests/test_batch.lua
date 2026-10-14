local support = dofile("tests/support.lua")
local assertEqual = support.assertEqual
local setTime = support.setTime
local core = support.core
local formatCache = support.formatCache
local overlay = support.overlay
local data = support.data

local timerBatch = assert(loadfile("src/timer/batch.lua"))({
    core = core,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
timerBatch.start(2)
assertEqual(timerBatch.status().kind, "ready")
assertEqual(timerBatch.status().text, "Recording ready for 2 runs")
assertEqual(timerBatch.time("rta"), nil)
assertEqual(timerBatch.startRun(), true)
assertEqual(timerBatch.status().kind, "active")
assertEqual(timerBatch.currentRow().label, "Current 1/2")
setTime(100)
timerBatch.finalizeRun({
    getInGameTime = function()
        return 80
    end,
}, {
    Cleared = true,
})
assertEqual(timerBatch.status().text, "Recording 1 / 2")
assertEqual(timerBatch.time("igt"), 8000)
assertEqual(timerBatch.time("rta"), 10000)
assertEqual(timerBatch.row(1).label, "Run 1/2")
assertEqual(timerBatch.currentRow().label, "")
assertEqual(timerBatch.startRun(), true)
assertEqual(timerBatch.currentRow().label, "Current 2/2")
setTime(190)
timerBatch.finalizeRun({
    getInGameTime = function()
        return 70
    end,
}, {
    Cleared = true,
})
assertEqual(timerBatch.status().kind, "recorded")
assertEqual(timerBatch.status().text, "Recorded 2 / 2")
assertEqual(timerBatch.time("igt"), 15000)
assertEqual(timerBatch.row(2).label, "Run 2/2")
assertEqual(timerBatch.currentRow().label, "")

timerBatch.start(3)
assertEqual(timerBatch.startRun(), true)
setTime(12)
timerBatch.finalizeRun({
    getInGameTime = function()
        return 9
    end,
}, {
    Cleared = false,
})
assertEqual(timerBatch.status().kind, "failed")
assertEqual(timerBatch.status().text, "Failed (0 / 3 complete)")
assertEqual(timerBatch.row(1).label, "Failed")
assertEqual(timerBatch.row(1).igtCs, 900)
assertEqual(timerBatch.time("igt"), 0)
setTime(0)

timerBatch.start(12)
assertEqual(timerBatch.status().text, "Recording ready for 12 runs")
assertEqual(timerBatch.startRun(), true)
assertEqual(timerBatch.currentRow().label, "Current 1/12")
timerBatch.stop()

local overlayBatch = assert(loadfile("src/timer/batch.lua"))({
    core = core,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
local batchOverlayAdapter = assert(loadfile("src/display/overlay_batch.lua"))({
    batch = {
        hasSession = overlayBatch.hasSession,
        session = overlayBatch.session,
    },
    maxRows = data.batchTargetRuns.max,
    overlay = overlay,
    isVisible = function()
        return true
    end,
    isModeVisible = function(mode)
        return mode ~= "rta"
    end,
    formatCache = formatCache,
})
local batchOverlayDeclarations = {}
batchOverlayAdapter.register({
    createTable = function(name, spec)
        batchOverlayDeclarations[name] = spec
    end,
}, 300)
assert(batchOverlayDeclarations.batch ~= nil, "expected batch table declaration")
assertEqual(batchOverlayDeclarations.batch.order, 300)
assertEqual(batchOverlayDeclarations.batch.maxRows, data.batchTargetRuns.max + 1)
assertEqual(batchOverlayDeclarations.batch.visible(), false)
overlayBatch.start(2)
overlayBatch.startRun()
assertEqual(batchOverlayDeclarations.batch.visible(), true)
local batchOverlayRows = batchOverlayAdapter.buildRows(nil)
assertEqual(batchOverlayRows[1].key, "current")
assertEqual(batchOverlayRows[1].label, "Current 1/2")
assertEqual(batchOverlayRows[1].igt, "")
assertEqual(batchOverlayRows[1].rta, "")
assertEqual(batchOverlayRows[1].lrt, "")
local batchSession = overlayBatch.session({
    getInGameTime = function()
        return 7
    end,
})
assertEqual(batchSession.currentTime.igtCs, 700)
setTime(10)
overlayBatch.finalizeRun({
    getInGameTime = function()
        return 8
    end,
}, {
    Cleared = true,
})
local projectedBatchTables = {}
batchOverlayAdapter.project({
    setTable = function(name, rows)
        projectedBatchTables[name] = rows
    end,
})
assertEqual(projectedBatchTables.batch[1].key, "run1")
assertEqual(projectedBatchTables.batch[1].label, "Run 1/2")
assertEqual(projectedBatchTables.batch[1].igt, "00:08.00")
setTime(0)
