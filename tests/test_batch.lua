local support = dofile("tests/support.lua")
local assertEqual = support.assertEqual
local setTime = support.setTime
local formatCache = support.formatCache
local overlay = support.overlay
local data = support.data

local timerBatch = assert(loadfile("src/timer/batch.lua"))(support.batchDeps())
timerBatch.start(support.batchSettings(2))
assertEqual(timerBatch.status().kind, "ready")
assertEqual(timerBatch.status().text, "Recording ready for 2 runs")
assertEqual(timerBatch.time("rta"), nil)
assertEqual(timerBatch.startRun(), true)
assertEqual(timerBatch.status().kind, "active")
assertEqual(timerBatch.session().current.heading.label, "Current 1/2")
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
assertEqual(timerBatch.session().groups[1].heading.label, "Run 1/2")
assertEqual(timerBatch.session().current.heading.label, "")
assertEqual(timerBatch.startRun(), true)
assertEqual(timerBatch.session().current.heading.label, "Current 2/2")
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
assertEqual(timerBatch.session().groups[2].heading.label, "Run 2/2")
assertEqual(timerBatch.session().current.heading.label, "")

timerBatch.start(support.batchSettings(3))
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
assertEqual(timerBatch.session().groups[1].heading.label, "Failed")
assertEqual(timerBatch.session().groups[1].heading.igtCs, 900)
-- Session IGT sums every attempt, failed ones included.
assertEqual(timerBatch.time("igt"), 900)
setTime(0)

timerBatch.start(support.batchSettings(12))
assertEqual(timerBatch.status().text, "Recording ready for 12 runs")
assertEqual(timerBatch.startRun(), true)
assertEqual(timerBatch.session().current.heading.label, "Current 1/12")
timerBatch.stop()

local overlayBatch = assert(loadfile("src/timer/batch.lua"))(support.batchDeps())
local batchPaging = dofile("src/display/paging.lua")
local batchPageSize = 2
local batchOverlayAdapter = assert(loadfile("src/display/overlay_batch.lua"))({
    batch = {
        hasSession = overlayBatch.hasSession,
        session = overlayBatch.session,
    },
    overlay = overlay,
    isVisible = function()
        return true
    end,
    isModeVisible = function(mode)
        return mode ~= "rta"
    end,
    formatCache = formatCache,
    paging = batchPaging,
    readPageSize = function()
        return batchPageSize
    end,
    maxPageSize = data.pageSize.max,
    maxBiomes = data.maxAttemptBiomes,
})
local batchOverlayDeclarations = {}
batchOverlayAdapter.register({
    createTable = function(name, spec)
        batchOverlayDeclarations[name] = spec
    end,
}, 300)
assert(batchOverlayDeclarations.batch ~= nil, "expected batch table declaration")
assertEqual(batchOverlayDeclarations.batch.order, 300)
assertEqual(batchOverlayDeclarations.batch.maxRows, data.pageSize.max + data.maxAttemptBiomes + 3)
assertEqual(batchOverlayDeclarations.batch.visible(), false)
overlayBatch.start(support.batchSettings(5))
overlayBatch.startRun()
assertEqual(batchOverlayDeclarations.batch.visible(), true)
local batchOverlayRows = batchOverlayAdapter.buildRows(nil)
assertEqual(batchOverlayRows[1].key, "header")
assertEqual(batchOverlayRows[1].label, "Runs 0/5")
assertEqual(batchOverlayRows[1].igt, "IGT")
assertEqual(batchOverlayRows[1].rta, "")
assertEqual(batchOverlayRows[2].key, "current")
assertEqual(batchOverlayRows[2].label, "Current 1/5")
assertEqual(batchOverlayRows[2].igt, "")
assertEqual(batchOverlayRows[3].key, "total")
assertEqual(batchOverlayRows[3].label, "Total")
local batchSession = overlayBatch.session({
    getInGameTime = function()
        return 7
    end,
})
assertEqual(batchSession.currentTime.igtCs, 700)

local function finishBatchRun(igt)
    overlayBatch.finalizeRun({
        getInGameTime = function()
            return igt
        end,
    }, {
        Cleared = true,
    })
end
setTime(10)
finishBatchRun(8)
local projectedBatchTables = {}
-- Mirrors display.project, which takes the pending page change as it projects.
local function projectBatch()
    batchPaging.takePending()
    batchOverlayAdapter.project({
        setTable = function(name, rows)
            projectedBatchTables[name] = rows
        end,
    })
    return projectedBatchTables.batch
end
local projected = projectBatch()
assertEqual(projected[2].key, "page1")
assertEqual(projected[2].label, "Run 1/5")
assertEqual(projected[2].igt, "00:08.00")
assertEqual(projected[3].label, "Total")
assertEqual(projected[3].igt, "00:08.00")

-- Paging: two attempts per page, following the newest page by default.
for _, igt in ipairs({ 1, 1 }) do
    overlayBatch.startRun()
    finishBatchRun(igt)
end
projected = projectBatch()
assertEqual(projected[1].label, "Runs 3/5 · p2/2")
assertEqual(projected[2].label, "Run 3/5")
assertEqual(projected[3].label, "Total")
batchPaging.previous()
assertEqual(batchPaging.isPending(), true)
projected = projectBatch()
assertEqual(projected[1].label, "Runs 3/5 · p1/2")
assertEqual(projected[2].label, "Run 1/5")
assertEqual(projected[3].label, "Run 2/5")
batchPaging.previous()
assertEqual(batchPaging.isPending(), false)
-- A finished attempt snaps back to the newest page.
overlayBatch.startRun()
finishBatchRun(1)
projected = projectBatch()
assertEqual(projected[1].label, "Runs 4/5 · p2/2")
assertEqual(projected[2].label, "Run 3/5")
assertEqual(projected[3].label, "Run 4/5")
-- Next past the last page returns to following the newest page.
batchPaging.previous()
batchPaging.next()
projected = projectBatch()
assertEqual(projected[1].label, "Runs 4/5 · p2/2")
setTime(0)
