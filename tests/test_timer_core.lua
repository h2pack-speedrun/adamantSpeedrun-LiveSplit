local support = dofile("tests/support.lua")
local assertEqual = support.assertEqual
local setTime = support.setTime
local core = support.core
local formatCache = support.formatCache
local overlay = support.overlay

local formatCallCount = 0
local countedFormatCache = assert(loadfile("src/display/format_cache.lua"))({
    formatCentiseconds = function(value)
        formatCallCount = formatCallCount + 1
        return support.timeFormat.formatCentiseconds(value)
    end,
})
local countedFormatRow = {}
assertEqual(countedFormatCache.cell(countedFormatRow, "igt", 1234), "00:12.34")
assertEqual(countedFormatCache.cell(countedFormatRow, "igt", 1234), "00:12.34")
assertEqual(formatCallCount, 1)
assertEqual(countedFormatCache.cell(countedFormatRow, "igt", nil), "")
assertEqual(countedFormatCache.cell(countedFormatRow, "igt", nil), "")
assertEqual(formatCallCount, 1)

local rtaTime = 7
local lrtBorrowedCalls = { start = 0, stop = 0, reset = 0 }
local borrowedRealTimer = {
    getTime = function()
        return rtaTime
    end,
    start = function()
        lrtBorrowedCalls.start = lrtBorrowedCalls.start + 1
    end,
    stop = function()
        lrtBorrowedCalls.stop = lrtBorrowedCalls.stop + 1
    end,
    reset = function()
        lrtBorrowedCalls.reset = lrtBorrowedCalls.reset + 1
    end,
}
local borrowedLrt = core.LrtTimer:new({ rtaTimer = borrowedRealTimer })
setTime(0)
borrowedLrt:start()
assertEqual(borrowedLrt:getTime(), 7)
setTime(10)
borrowedLrt:processLoadEvent(true)
setTime(12)
rtaTime = 12
assertEqual(borrowedLrt:getTime(), 10)
borrowedLrt:processLoadEvent(false)
assertEqual(borrowedLrt:getTime(), 10)
rtaTime = 15
assertEqual(borrowedLrt:getTime(), 13)
borrowedLrt:stop()
borrowedLrt:reset()
assertEqual(lrtBorrowedCalls.start, 0)
assertEqual(lrtBorrowedCalls.stop, 0)
assertEqual(lrtBorrowedCalls.reset, 0)
assertEqual(borrowedLrt:getLoadTime(), 0)

local singleRun = assert(loadfile("src/timer/single_run/single_run.lua"))({
    core = core,
    isMultiRunMode = function()
        return false
    end,
})
setTime(0)
_G.CurrentRun = {
    GameplayTime = 0,
}
singleRun.beginRun()
assertEqual(singleRun.getSnapshot().igtCs, 0)
assertEqual(singleRun.startDisplayLoop(), true)
setTime(12.34)
_G.CurrentRun.GameplayTime = 10.5
singleRun.updateTick()
assertEqual(singleRun.getSnapshot().rtaCs, 1234)
assertEqual(singleRun.getSnapshot().igtCs, 1050)
singleRun.processLoadEvent(true)
setTime(14.34)
singleRun.processLoadEvent(false)
singleRun.updateTick()
assertEqual(singleRun.getSnapshot().lrtCs, 1234)
local finalized, finalizedTimer = singleRun.finalizeRun()
assertEqual(finalized, true)
assert(finalizedTimer ~= nil, "expected finalized timer")
assertEqual(singleRun.hasSummary(), true)
singleRun.clear()
assertEqual(singleRun.hasSummary(), false)
setTime(0)
_G.CurrentRun = nil

local hookSingleRun = assert(loadfile("src/timer/single_run/single_run.lua"))({
    core = core,
    isMultiRunMode = function()
        return false
    end,
})
local hookAdapter = assert(loadfile("src/timer/single_run/hooks.lua"))(hookSingleRun)
local hookHost = {
    isEnabled = function()
        return true
    end,
}
local hookRuntime = {}
local hookCallbacks = {}
local hookEvents = {}
hookAdapter.installHooks({
    wrap = function(name, callback)
        hookCallbacks[name] = callback
    end,
}, {
    isEnabled = function()
        return true
    end,
    onRunStarted = function()
        hookEvents[#hookEvents + 1] = "started"
        hookEvents.startedRun = CurrentRun
        hookEvents.startedTimer = hookSingleRun.getActiveTimer()
    end,
    onDisplayLoopStarted = function()
        hookEvents[#hookEvents + 1] = "display"
        hookEvents.displayTimer = hookSingleRun.getActiveTimer()
    end,
    onLoadEvent = function(_, isLoading)
        hookEvents[#hookEvents + 1] = isLoading and "loadStart" or "loadStop"
    end,
    onRunFinalized = function()
        hookEvents[#hookEvents + 1] = "finalized"
        hookEvents.finalizedRun = CurrentRun
        hookEvents.finalizedTimer = hookSingleRun.getActiveTimer()
    end,
    onDisplayChanged = function()
        hookEvents[#hookEvents + 1] = "changed"
    end,
})
assert(hookCallbacks.StartNewRun ~= nil, "expected StartNewRun hook")
assert(hookCallbacks.RoomEntranceMaterialize ~= nil, "expected RoomEntranceMaterialize hook")
assert(hookCallbacks.RoomEntranceDreamBiomeStart ~= nil, "expected RoomEntranceDreamBiomeStart hook")
assert(hookCallbacks.RecordRunStats ~= nil, "expected RecordRunStats hook")
assert(hookCallbacks.AddTimerBlock ~= nil, "expected AddTimerBlock hook")
assert(hookCallbacks.RemoveTimerBlock ~= nil, "expected RemoveTimerBlock hook")
setTime(0)
_G.CurrentRun = {
    GameplayTime = 0,
}
local startedRun = hookCallbacks.StartNewRun(hookHost, hookRuntime, function()
    return CurrentRun
end)
assertEqual(startedRun, CurrentRun)
assertEqual(hookEvents[1], "started")
assert(hookEvents.startedTimer ~= nil, "expected started timer")
hookCallbacks.RoomEntranceMaterialize(hookHost, hookRuntime, function()
    return "entered"
end)
assertEqual(hookEvents[3], "display")
hookCallbacks.AddTimerBlock(hookHost, hookRuntime, function()
    return true
end, CurrentRun, "MapLoad")
local forwardedTimerBlockArgs = nil
hookCallbacks.AddTimerBlock(hookHost, hookRuntime, function(_, _, args)
    forwardedTimerBlockArgs = args
    return true
end, CurrentRun, "AthenaPresence", { MapState = true })
assert(forwardedTimerBlockArgs ~= nil and forwardedTimerBlockArgs.MapState == true,
    "expected AddTimerBlock args to reach the native function")
setTime(3)
hookCallbacks.RemoveTimerBlock(hookHost, hookRuntime, function()
    return true
end, CurrentRun, "MapLoad")
hookCallbacks.RecordRunStats(hookHost, hookRuntime, function()
    return "stats"
end)
assertEqual(hookEvents[#hookEvents - 1], "finalized")
assertEqual(hookEvents.finalizedRun, CurrentRun)
assertEqual(hookEvents.finalizedTimer, hookEvents.startedTimer)
setTime(0)
_G.CurrentRun = nil

local overlaySingleRun = assert(loadfile("src/timer/single_run/single_run.lua"))({
    core = core,
})
local overlaySingleRunAdapter = assert(loadfile("src/display/overlay_single_run.lua"))({
    singleRun = overlaySingleRun,
    overlay = overlay,
    isModeVisible = function(mode)
        return mode ~= "rta"
    end,
    isTimerDisplayVisible = function()
        return overlaySingleRun.hasSummary()
    end,
    getDisplayTime = function(row, mode)
        return formatCache.cell(row, "time", overlaySingleRun.getSnapshot()[mode .. "Cs"])
    end,
})
local singleRunOverlayDeclarations = {}
overlaySingleRunAdapter.register({
    createLine = function(name, spec)
        singleRunOverlayDeclarations[name] = spec
    end,
}, 100)
assert(singleRunOverlayDeclarations["summary.igt"] ~= nil, "expected IGT line declaration")
assert(singleRunOverlayDeclarations["summary.rta"] ~= nil, "expected RTA line declaration")
assert(singleRunOverlayDeclarations["summary.lrt"] ~= nil, "expected LrT line declaration")
assertEqual(singleRunOverlayDeclarations["summary.igt"].visible(), false)
setTime(0)
_G.CurrentRun = {
    GameplayTime = 0,
}
overlaySingleRun.beginRun()
overlaySingleRun.startDisplayLoop()
setTime(9.87)
_G.CurrentRun.GameplayTime = 8.76
overlaySingleRun.updateTick()
assertEqual(singleRunOverlayDeclarations["summary.igt"].visible(), true)
assertEqual(singleRunOverlayDeclarations["summary.rta"].visible(), false)
local projectedSingleRunLines = {}
overlaySingleRunAdapter.project({
    setLine = function(name, values)
        projectedSingleRunLines[name] = values
    end,
})
assertEqual(projectedSingleRunLines["summary.igt"].time, "00:08.76")
assertEqual(projectedSingleRunLines["summary.rta"].time, "")
setTime(0)
_G.CurrentRun = nil

local format = support.timeFormat.formatCentiseconds
assertEqual(format(0), "00:00.00")
assertEqual(format(123), "00:01.23")
assertEqual(format(5999), "00:59.99")
assertEqual(format(6000), "01:00.00")
assertEqual(format(6123), "01:01.23")
assertEqual(format(359999), "59:59.99")
assertEqual(format(360000), "01:00:00.00")
assertEqual(format(366123), "01:01:01.23")
